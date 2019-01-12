---
title: "08 Defeating Censorship And Improving Security With OpenVPN"
date: 2019-01-12T10:10:13Z
author: "Viktor Barzin"
description: "In this blogpost I show you how I set up multiple OpenVPN instances - one running on port 443/tcp to mask it as regular HTTPS traffic and avoid being blocked. I show how to do it and also some neat tricks about systemd and debugging openvpn-related networking issues."
tags: ["OpenVPN", "tcp OpenVPN", "port 443/tcp", "iptables", "SSL/TLS", "TLS", "multiple openvpn", "systemd", "service files", "systemd services", "openvpn-server@.service", "OpenWRT tunneling openvpn traffic", "firewall", "routing", "learn-address", "static routes", "sudoers", "/sbin/ip", "linux capabilities", "CapabilityBoundingSet"]
firstImgUrl: "https://viktorbarzin.me/images/08-defeating-censorship-with-tcp-openvpn-072ee9b6-ln.png"
draft: false
---

# Introduction

I do happen to travel from time to time and in order to stay online I have to use insecure public wifi.
Everyone who understands a bit about network security knows the risks of connecting to unsafe networks and how dangerous they could be.

One of the most common solutions to this problem, including mine, is a [VPN](https://en.wikipedia.org/wiki/Virtual_private_network) service.
That's all great, however, more and more network administrators put effort into blocking VPN traffic.

That annoys the heck out of me so in this post I'll show you how I've essentially bypassed any VPN filtering with some simple tweaks.

### Prerequisites
Now before reading this blogpost, I recommend getting yourself familiar with basic [OpenVPN](https://openvpn.net/community-resources/how-to/) as well as [systemd](https://www.digitalocean.com/community/tutorials/systemd-essentials-working-with-services-units-and-the-journal) concepts.

My setup consists of a OpenVPN instance so whenever I say "vpn" I refer to OpenVPN entity.

Let's get started!

# How is OpenVPN traffic filtered?

Having a quick look at the network traffic, we can easily spot the OpenVPN traffic:

![](/images/08-defeating-censorship-with-tcp-openvpn-bbd7bf06.png)

The image shows the beginning of the communication - firstly the *DNS* query, followed by the OpenVPN TLS handshake and finishing with the first packets of encrypted data sent over the secure channel.

By default, OpenVPN runs on port *1194/UDP* so filtering it can be as simple as

{{< highlight bash >}}
# iptables -A FORWARD -p udp --destination-port 1194 -j DROP
{{< /highlight >}}

Nowadays, network admins would probably use a more GUI-like user interface to do that, but that's essentially what it boils down to.

Port 1194 is what Wireshark recognises as OpenVPN traffic as well:

![](/images/08-defeating-censorship-with-tcp-openvpn-9e9c4f43.png)

# What can we do about it?

Whenever you connect to a secure website (including my blog) you are essentially sending HTTP requests over an encrypted channel that is set up beforehand.
The [SSL](https://www.instantssl.com/ssl.html)/[TLS](https://en.wikipedia.org/wiki/Transport_Layer_Security) protocols (see [difference between SSL and TLS](https://www.globalsign.com/en/blog/ssl-vs-tls-difference/)) lie at the heart of web security these days and there are plenty of other protocols that rely on SSL/TLS to securely transfer data around.
Once this channel is initialized, the outside world cannot see any data that travels inside it.

OpenVPN also uses TLS for its encrypted channel.
The TLS handshake is standardized and does not depend in any way on the protocol it carries.

So could we run the OpenVPN service on port 443/tcp to mask is as regular HTTPS traffic?
Absolutely!
Blocking 443/TCP would mean breaking the internet for the common user so no one will ever do it.

# The issue of running multiple OpenVPN instances

A funny thing is that in all the forums I read, everyone' opinion was that you can run multiple instances of OpenVPN simultaneously, but no one gave any guidelines on how exactly to do that. From the scarce information that I found, 2 things became clear to me:

- OpenVPN does not support listening on multiple ports simultaneously by design.
- but this task can be done and most people talk about creating 2 tap interfaces and bridging them in some fancy way

I really didn't want to go the bridging way so I kept on looking for an alternative. What's more I didn't want to spin up an entirely separate instance - it was a **must** to reuse my config files and client certificates.

# systemd hidden gems


I looked for a more Linux-y way of solving this issue so I had a think - OpenVPN is just a daemon ran by systemd. By default it has the following config:

{{< highlight bash >}}
# /lib/systemd/system/openvpn.service

# This service is actually a systemd target,
# but we are using a service since targets cannot be reloaded.

[Unit]
Description=OpenVPN service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecReload=/bin/true
WorkingDirectory=/etc/openvpn

[Install]
WantedBy=multi-user.target


{{< / highlight >}}

I had a second look at the directory where the service file lives (`/lib/systemd/system/`) and I noticed there are several openvpn related service files:

{{< highlight bash >}}

root@vpn:/lib/systemd/system# ls openvpn
openvpn-client@.service  openvpn-server@.service  openvpn.service          openvpn@.service
root@vpn:/lib/systemd/system# ls openvpn
{{< / highlight >}}

When managing the OpenVPN service I've always used the *openvpn* unit file, but what's that fancy `openvpn-server@.service` thingy?

That "**@**" looks dodgy, let's see what it stands for in the unit file name.

The answer lies in section 5 of the systemd manpage (`man 5 systemd.service`)


{{< highlight bash >}}

Table 1. Special executable prefixes
┌───────┬───────────────────────────────────────────┐
│Prefix │ Effect                                    │
├───────┼───────────────────────────────────────────┤
│"@"    │ If the executable path is prefixed with   │
│       │ "@", the second specified token will be   │
│       │ passed as "argv[0]" to the executed       │
│       │ process (instead of the actual filename), │
│       │ followed by the further arguments         │
│       │ specified.                                │
├───────┼───────────────────────────────────────────┤
{{< / highlight >}}

Woah! *systemd* can pass arguments to the daemon executables it runs, how awesome is that!

Having a look at the `openvpn-server@.service` file we can see that it's more complicated that the first one:


{{< highlight bash "linenos=inline,hl_lines=15">}}
# /lib/systemd/system/openvpn-server@.service

[Unit]
Description=OpenVPN service for %I
After=syslog.target network-online.target
Wants=network-online.target
Documentation=man:openvpn(8)
Documentation=https://community.openvpn.net/openvpn/wiki/Openvpn24ManPage
Documentation=https://community.openvpn.net/openvpn/wiki/HOWTO

[Service]
Type=notify
PrivateTmp=true
WorkingDirectory=/etc/openvpn/server
ExecStart=/usr/sbin/openvpn --status %t/openvpn-server/status-%i.log --status-version 2 --suppress-timestamps --config %i.conf
CapabilityBoundingSet=CAP_IPC_LOCK CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETGID CAP_SETUID CAP_SYS_CHROOT CAP_DAC_OVERRIDE
LimitNPROC=10
DeviceAllow=/dev/null rw
DeviceAllow=/dev/net/tun rw
ProtectSystem=true
ProtectHome=true
KillMode=process
RestartSec=5s
Restart=on-failure

[Install]
WantedBy=multi-user.target

{{< / highlight >}}

I'm interested in the `ExecStart` directive as this is what is being executed as a 'service'.
Obviously, this is the OpenVPN daemon being started and I'm keen on learning what this '**%i**' stands for since the config I want it to use is referenced as '**%i.conf**' (at the end of line 15)

Having a look at `man 5 systemd.unit` shows a neat table that explains is well:

{{< highlight bash >}}

Table 4. Specifiers available in unit files
┌──────────┬────────────────────────────┬─────────────────────────────┐
│Specifier │ Meaning                    │ Details                     │
├──────────┼────────────────────────────┼─────────────────────────────┤
│"%i"      │ Instance name              │ For instantiated units this │
│          │                            │ is the string between the   │
│          │                            │ first "@" character and the │
│          │                            │ type suffix. Empty for      │
│          │                            │ non-instantiated units.     │
├──────────┼────────────────────────────┼─────────────────────────────┤
{{< / highlight >}}

Aha! So I could start a openvpn-server@**some_name**.service and that would start an OpenVPN instance using **some_name**.conf as a config file.

By default, there is no *server* directory in */etc/openvpn* so after we make that we should get our hands on creating the new tcp config file:


{{< highlight bash >}}
# mkdir /etc/openvpn/server && cp /etc/openvpn/openvpn.conf /etc/openvpn/server/tcp.conf
{{< / highlight >}}

We want to have the same config, to make use of the same client certificates and what not, but run on port 443/tcp.
So the config has to be mostly the same with only a few changes :

![](/images/08-defeating-censorship-with-tcp-openvpn-641a88d0.png)

Let me explain why each of the changes is needed:

- server directive - instances need to have different IPs otherwise routing would get messed up and the kernel would not know which interface to use when sending data to clients
- proto directive - we want a *tcp* instance so that's quite obvious
- port - same reason
- dev - we need to setup a different interface that would handle clients connecting to the tcp instance. If we let both instances use the same interface we might get quite odd networking issues
- status - can be the same though it's handy to have separate log files for each instance

The rest of the config is the same. So let's start the second instance and keep our fingers crossed:

{{< highlight bash >}}
# systemctl start openvpn-server@tcp
{{< / highlight >}}

That seemed to have done the trick since the vpn instance was up and running.

Then I quickly crafted a client certificate that would be an exact copy of an existing one, with the exception of the port and the ip address.

Now if you've read my [post](/blog/03-a-walk-down-infrastructure-lane/#the-public-part) about my home network topology, you know that the only port I have on my disposal on the site where I'm hosting my vpn server is 1194.

However, I'd like to run another instance of OpenVPN that listens on another port. So I've hit a wall there ...

... or have I?

# OpenWRT to the rescue

Running OpenVPN over tcp hurts performance significantly due to the way of how tcp works.
I'm setting up this instance not to be fast, but to be stealthy so I am ready to sacrifice a little bit of performance.
Now given that I desperately need hole through which I can smuggle my service and that performance is not a priority, perhaps I could
make it run via my home router as I've [done previously](/blog/03-a-walk-down-infrastructure-lane/#the-public-part) with this site.

This would mean running a OpenVPN instance inside another OpenVPN instance.

![](/images/08-defeating-censorship-with-tcp-openvpn-8e6179ed.png)

# The meat of this hack

Let's step back and see what that means. Hopefully this picture clarifies things a bit:

![](/images/08-defeating-censorship-with-tcp-openvpn-072ee9b6.png)


Firstly, UDP clients are not affected in any way.
My home router is one and I use its udp vpn connection to send tcp vpn traffic from the client on the left.
When that nested conenction reaches the server, the udp one is stripped away and then the tcp connection afterwards so in the traffic logs on the server you could tell both clients appart even though one carries the traffic of the other.

Let's see if this even works:


{{< highlight bash "hl_lines=20" >}}
╭─viktor@yuhu 11:31:25 ~/
╰─$ sudo openvpn viktor-tcp.ovpn
Tue Jan 08 19:09:02 2019 OpenVPN 2.4.6 x86_64-redhat-linux-gnu [SSL (OpenSSL)] [LZO] [LZ4] [EPOLL] [PKCS11] [MH/PKTINFO]
[AEAD] built on Oct  6 2018
Tue Jan 08 19:09:02 2019 library versions: OpenSSL 1.1.1 FIPS  11 Sep 2018, LZO 2.08
Tue Jan 08 19:09:02 2019 TCP/UDP: Preserving recently used remote address: [AF_INET]213.191.184.70:443
Tue Jan 08 19:09:02 2019 Attempting to establish TCP connection with [AF_INET]213.191.184.70:443 [nonblock]
Tue Jan 08 19:09:03 2019 TCP connection established with [AF_INET]213.191.184.70:443
Tue Jan 08 19:09:03 2019 TCP_CLIENT link local: (not bound)
Tue Jan 08 19:09:03 2019 TCP_CLIENT link remote: [AF_INET]213.191.184.70:443
Tue Jan 08 19:09:04 2019 [vpn.samitor.com] Peer Connection Initiated with [AF_INET]213.191.184.70:443
Tue Jan 08 19:09:05 2019 Options error: Unrecognized option or missing or extra parameter(s) in [PUSH-OPTIONS]:1:
block-outside-dns (2.4.6)
Tue Jan 08 19:09:05 2019 TUN/TAP device tun0 opened
Tue Jan 08 19:09:05 2019 do_ifconfig, tt->did_ifconfig_ipv6_setup=0
Tue Jan 08 19:09:05 2019 /sbin/ip link set dev tun0 up mtu 1500
Tue Jan 08 19:09:05 2019 /sbin/ip addr add dev tun0 local 10.3.2.1 peer 10.3.2.2
Tue Jan 08 19:09:05 2019 WARNING: this configuration may cache passwords in memory -- use the auth-nocache option to
prevent this
Tue Jan 08 19:09:05 2019 Initialization Sequence Completed
{{< / highlight >}}
So we should be done by now right?

Ehm, not quite:

{{< highlight bash >}}
╭─viktor@yuhu 19:09:20 ~/
╰─$ ping 192.168.254.1
PING 192.168.254.1 (192.168.254.1) 56(84) bytes of data.
^C
--- 192.168.254.1 ping statistics ---
6 packets transmitted, 0 received, 100% packet loss, time 158ms
{{< / highlight >}}

There is neither ping on any of the machines on the internal network, nor access to public addresses.

# Is it the firewall or the routing?

So the OpenVPNpn client log indicates that a connection with the vpn server on the other side has been made successfully, but there is no internet access.
Now there are a few probable reasons for that:

- A: firewall dropping packets somewhere along the route
- B: misconfigured routes somewhere, most-likely on the vpn vm but can be elsewhere (maybe home router?)
- C: both?

# Putting the debugging hat on

The good news is that I don't have to debug the OpenVPN thingy but instead a networking issue.
Firing up `tcpdump` everywhere yeilded an odd result - the ping is being received by the vpn vm, however, nothing is sent back.

So it's probably `iptables` that's stopping my traffic isn't it?
Let's stop it for a moment:
{{< highlight bash >}}
# iptables -P {INPUT,OUTPUT,FORWARD} ACCEPT
{{< / highlight >}}

Nope, still no ping back.

Then, surely, it must be an issue with the routing table.
The weird thing about the whole thing was that I could cleary see the echo requests on tcpdump, but could not see any echo replies - if it was a routing error I would see the echo replies going out from a wrong interface, but I couldn't see any!

This took a good couple of days to figure out.

# OpenVPN routing quirks

I found this nice [blog post](https://thomas.gouverneur.name/2014/02/openvpn-listen-on-tcp-and-udp-with-tun/) from 2014 that explained how to do the entire thing - run a tcp and an udp instances of OpenVPN with the same config and without using a *tap* interface.

I had done most of the stuff the guy explained, I've just missed the last part - the routing.
There is this simple script that I'd missed. It takes care of the routing whenever a client connects and disconnects.
Basically, each time a client (dis)connects a static /32 route is being added   /removed that would tell the kernel to route the client via the according interface - if the client connected via tcp aka tun1 - then route him via that interface.
Otherwise route the client via the default tun0 interface:

{{< highlight bash >}}
#!/bin/bash
# /etc/openvpn/scripts/learn-address.sh
##
# learn-address script which allow
# OpenVPN to run on both TCP and UDP
# with the same range of address on both
# protocol.
#
# tgouverneur -- 2014
##

if [ $# -lt 2 ]; then
  exit 0;
fi
action=$1;
addr=$2;

case ${action} in
        add|update)
                echo "[-] ${addr} logged in to ${dev}" >> /etc/openvpn/server/tcp-vpn.log
                /usr/bin/sudo /sbin/ip ro del ${addr}/32
                /usr/bin/sudo /sbin/ip ro add ${addr}/32 dev ${dev};
        ;;
        delete)
               echo "[-] Deleting addr ${addr} -> ${dev}" >> /etc/openvpn/server/tcp-vpn.log
               /usr/bin/sudo /sbin/ip ro del ${addr}/32
        ;;
        *)
        ;;
esac

exit 0;
{{< / highlight >}}

Neat right?

We want this script to be executed each time a client (dis)connects.

There is a special directive in the OpenVPN server config for that (have to put it in both configs):

{{< highlight bash >}}
# /etc/openvpn/openvpn.conf
# /etc/openvpn/server/tcp.conf
 --- snip ---
learn-address /etc/openvpn/scripts/learn-address.sh
{{< / highlight >}}

#### PS: Remember to add your vpn daemon user to sudoers and allow him to execute */sbin/ip* as root - it needs to be able to change system routes:

{{< highlight bash >}}
# /etc/sudoers
 --- snip ---
vpn ALL=(ALL:ALL) NOPASSWD: /sbin/ip
{{< / highlight >}}

Finally it should be good to go!

# Not yet...

Alas even with this tweak there was no connection going out of the vpn server to the clients...

This time I decided to have a look at the server logs - something must have gone wrong server-side!


{{< highlight bash "linenos=inline,hl_lines=4 6 9-13 15-17 20-22" >}}

root@vpn:/etc/openvpn/server# journalctl -f -u openvpn-server@tcp -b
-- Logs begin at Fri 2018-09-21 20:18:43 EEST. --
Jan 10 21:52:51 vpn openvpn[28814]: Socket Buffers: R=[87380->87380] S=[16384->16384]
Jan 10 21:52:51 vpn openvpn[28814]: Listening for incoming TCP connection on [AF_INET][undef]:443
--- snip ---
Jan 10 21:52:57 vpn openvpn[28814]: 10.3.2.9:13131 [sgs7] Peer Connection Initiated with [AF_INET]10.3.2.9:13131
Jan 10 21:52:57 vpn openvpn[28814]: sgs7/10.3.2.9:13131 OPTIONS IMPORT: reading client specific options from: /etc/openvpn/ccd/sgs7
Jan 10 21:52:57 vpn openvpn[28814]: sgs7/10.3.2.9:13131 OPTIONS IMPORT: reading client specific options from: /tmp/openvpn_cc_2550293368432e205dcedc71562a78a3.tmp
Jan 10 21:52:57 vpn sudo[28844]:      vpn : TTY=unknown ; PWD=/etc/openvpn/server ; USER=root ; COMMAND=/sbin/ip ro del 10.3.2.5/32
Jan 10 21:52:57 vpn openvpn[28814]: sudo: unable to send audit message
Jan 10 21:52:57 vpn sudo[28844]: PAM audit_log_acct_message() failed: Operation not permitted
Jan 10 21:52:57 vpn sudo[28844]: pam_unix(sudo:session): session opened for user root by (uid=0)
Jan 10 21:52:57 vpn sudo[28844]:      vpn : pam_open_session: System error ; TTY=unknown ; PWD=/etc/openvpn/server ; USER=root ; COMMAND=/sbin/ip ro del 10.3.2.5/32
Jan 10 21:52:57 vpn openvpn[28814]: sudo: pam_open_session: System error
Jan 10 21:52:57 vpn openvpn[28814]: sudo: policy plugin failed session initialization
Jan 10 21:52:57 vpn sudo[28845]:      vpn : TTY=unknown ; PWD=/etc/openvpn/server ; USER=root ; COMMAND=/sbin/ip ro add 10.3.2.5/32 dev tun1
Jan 10 21:52:57 vpn sudo[28845]: PAM audit_log_acct_message() failed: Operation not permitted
Jan 10 21:52:57 vpn openvpn[28814]: sudo: unable to send audit message
Jan 10 21:52:57 vpn sudo[28845]: pam_unix(sudo:session): session opened for user root by (uid=0)
Jan 10 21:52:57 vpn openvpn[28814]: sudo: pam_open_session: System error
Jan 10 21:52:57 vpn openvpn[28814]: sudo: policy plugin failed session initialization
Jan 10 21:52:57 vpn sudo[28845]:      vpn : pam_open_session: System error ; TTY=unknown ; PWD=/etc/openvpn/server ; USER=root ; COMMAND=/sbin/ip ro add 10.3.2.5/32 dev tun1
Jan 10 21:52:57 vpn openvpn[28814]: sgs7/10.3.2.9:13131 MULTI: Learn: 10.3.2.5 -> sgs7/10.3.2.9:13131
Jan 10 21:52:57 vpn openvpn[28814]: sgs7/10.3.2.9:13131 MULTI: primary virtual IP for sgs7/10.3.2.9:13131: 10.3.2.5
--- snip ---
{{< / highlight >}}

From this log snippet I could tell that the daemon has started listening successfully (line 4), client has connected without any problems either (line 6) but then when running the *learn-address* script there is this **"Operation not permitted"** on multiple instances.

You could cleary see that **root** is executing the `/sbin/ip` command (so */etc/sudoers* is read properly) but then why does it still get permission denied?

Debugging this issue was a hard one.

Eventually I found the answer in a [debian bug report logs on openvpn](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=792653).

The issue was in the *.service* file of the openvpn tcp instance.
The **[CapabilityBoundingSet](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#Capabilities)** directive controls what capabilities the started process will run with.

Apparently the default set does not include the capability for changing routes (or some other, I haven't figure it out).

The easiest way to fix it is just to comment out that line:

{{< highlight bash "hl_lines=8" >}}
# /lib/systemd/system/openvpn-server@.service
 --- snip ---
[Service]
Type=notify
PrivateTmp=true
WorkingDirectory=/etc/openvpn/server
ExecStart=/usr/sbin/openvpn --status %t/openvpn-server/status-%i.log --status-version 2 --suppress-timestamps --config %i.conf
#CapabilityBoundingSet=CAP_IPC_LOCK CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETGID CAP_SETUID CAP_SYS_CHROOT CAP_DAC_OVERRIDE
LimitNPROC=10
DeviceAllow=/dev/null rw
DeviceAllow=/dev/net/tun rw
ProtectSystem=true
ProtectHome=true
KillMode=process
RestartSec=5s
Restart=on-failure
 --- snip ---
{{< / highlight >}}

Obviously the best way to fix it, is to find out what capability it is missing and add it to the list.
In my case it's not mission critical given that I run my default OpenVPN with default capabilities, I don't see that as an issue for the tcp instance.

#### After restarting the services I finally got it working properly:


{{< highlight bash >}}
root@vpn:/etc/openvpn/server# journalctl -f -u openvpn-server@tcp -b
--- snip ---
Jan 10 21:56:14 vpn openvpn[29039]: 10.3.2.9:28118 [sgs7] Peer Connection Initiated with [AF_INET]10.3.2.9:28118
Jan 10 21:56:14 vpn openvpn[29039]: sgs7/10.3.2.9:28118 OPTIONS IMPORT: reading client specific options from: /etc/openvpn/ccd/sgs7
Jan 10 21:56:14 vpn openvpn[29039]: sgs7/10.3.2.9:28118 OPTIONS IMPORT: reading client specific options from: /tmp/openvpn_cc_1fd11ab8ec0f2dad7ebbc6eb4de16a8a.tmp
Jan 10 21:56:14 vpn sudo[29072]:      vpn : TTY=unknown ; PWD=/etc/openvpn/server ; USER=root ; COMMAND=/sbin/ip ro del 10.3.2.5/32
Jan 10 21:56:14 vpn sudo[29072]: pam_unix(sudo:session): session opened for user root by (uid=0)
Jan 10 21:56:14 vpn openvpn[29039]: RTNETLINK answers: No such process
Jan 10 21:56:14 vpn sudo[29072]: pam_unix(sudo:session): session closed for user root
Jan 10 21:56:14 vpn sudo[29074]:      vpn : TTY=unknown ; PWD=/etc/openvpn/server ; USER=root ; COMMAND=/sbin/ip ro add 10.3.2.5/32 dev tun1
Jan 10 21:56:14 vpn sudo[29074]: pam_unix(sudo:session): session opened for user root by (uid=0)
Jan 10 21:56:14 vpn sudo[29074]: pam_unix(sudo:session): session closed for user root
Jan 10 21:56:14 vpn openvpn[29039]: sgs7/10.3.2.9:28118 MULTI: Learn: 10.3.2.5 -> sgs7/10.3.2.9:28118
Jan 10 21:56:14 vpn openvpn[29039]: sgs7/10.3.2.9:28118 MULTI: primary virtual IP for sgs7/10.3.2.9:28118: 10.3.2.5
--- snip ---
{{< / highlight >}}

.. with the appropriate route being set for tcp:


{{< highlight bash >}}
10.3.2.5 dev tun0 scope link
{{< / highlight >}}

and udp

{{< highlight bash >}}
10.3.2.5 dev tun1 scope link
{{< / highlight >}}

respectively.

# Future work

There's a problem that I haven't solved yet - proxying the tcp vpn instance on port 443 at my home router raises an issue.
The router at home runs a haproxy instance on 443/tcp ([read more here](/blog/05-haproxy/)) to forward traffic to my webserver and serve content over HTTPS.
I can't really tell which TLS traffic is for the website and which for the vpn - that was the point in the first place wasn't it.

Currently as I see it, I'll probably need another public IP but we shall see.
Or since I have the private key for the TLS certificate I might be able to make haproxy act as a router but I need to do more research on the topic.

# Conclusion

Running a second OpenVPN instance on the same machine seemed as a pretty easy task, however, there are some caveats that might get in your way.
I learnt a lot about systemd, how it operates and what awesome stuff one could do with it.
Moreover, it was fun debugging the networking issues after a client has connected and last but not least I've never had to debug capabilities issues so that's good experience as well.

Getting everything to work brought me great satisfaction and a feeling of a time productively spent.

# Resources

[OpenVPN over TCP or UDP - pros and cons](https://www.bestvpn.com/guides/openvpn-tcp-vs-udp-difference-choose/)

[GitHub issue hinting that multiple OpenVPN instances are possible, but not without further tinkering](https://github.com/Angristan/OpenVPN-install/issues/28)

[OpenVPN source file that searches for config files](https://github.com/Angristan/OpenVPN-install/blob/f681c0bd3426cc0f825345d483a283da537d34d2/openvpn-install.sh#L621)

[OpenVPN tcp config from docs](https://community.openvpn.net/openvpn/wiki/GettingStartedwithOVPN)

[OpenVPN forums thread that says OpenVPN can be run over tcp but doesn't specify how](https://forums.openvpn.net/viewtopic.php?t=14503)

[Thomas Gouverneur's blog bost on the topic that included the 'learn-address' script](https://thomas.gouverneur.name/2014/02/openvpn-listen-on-tcp-and-udp-with-tun/)

[Debian Bug report logs where I found the capabilities issue for systemd](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=792653)

[Digitalocean guide on systemd and how to manage services in linux](https://www.digitalocean.com/community/tutorials/how-to-use-systemctl-to-manage-systemd-services-and-units)
