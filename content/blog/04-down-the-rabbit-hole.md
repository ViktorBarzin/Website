---
title: "04 Down the Rabbit Hole - How a simple monitoring task lead me to compiling a custom version of OpenWRT"
date: 2018-10-08T10:04:27+01:00
draft: true
---

# Introduction

In this blogpost I'll go through the journey I went when I was setting up monitoring with ELK for my infrastructure.
The task was simple - install \*beats and tell it to report to my elk stack vm.
You'll see why in my setup it wasn't as easy.

# The issue

If you recall my [network setup](/blog/03-a-walk-down-infrastructure-lane/#the-public-part") had a little issue - I do not own the public IP address where my infrastructure sits.
Therefore I've done some hacks to make it not matter that much. Well, that technical debt right there brought me some nasty headaches.

# When `apt install` doesn't work

So I wanted to setup monitoring on the access logs on my website - simple right?

`tail -f /var/log/nginx/host.access.log` gives me everything I need:

![](/images/04-down-the-rabbit-hole-e955cc2d.png)

All I had to do is install filebeat on the container and I'm done.

![](/images/04-down-the-rabbit-hole-fd41f4e8.png)

My network has a little quirk I [described in a previous post](/blog/03-a-walk-down-infrastructure-lane/#the-public-part") - namely any public service goes through the router at home which routes it via a vpn network to reach its destination endpoint.

A simple [layer 4](https://searchnetworking.techtarget.com/definition/Transport-layer) forwarding looks like this:

![](/images/04-down-the-rabbit-hole-93481567.png)

However, this means that as far as the webserver is concerned, the client accessing it, is my router since it is [NAT-ting](https://en.wikipedia.org/wiki/Network_address_translation) the connection.
This means that regardless of your IP, all I get in the logs is the router's vpn ip:

![](/images/04-down-the-rabbit-hole-64e92763.png)

Well that's an issue since that information is useless.

# Let's log *iptables* then!

If you're not familiar with [iptables](https://en.wikipedia.org/wiki/Iptables), well you should change that!
tl;dr; is that *iptables* is a user-space program that allows you to configure the kernel's built-in firewall.

iptables tries to match connections and take an appropriate action. One of these actions is *LOG* which writes a line in the kernel's log that looks like this:

`Mon Oct  8 13:52:12 2018 kern.warn kernel: [512827.190000] IN=br-wan OUT= MAC=12:34:56:78:90:12:34:56:78:90:12:34:56:78 SRC=82.103.122.186 DST=213.191.184.70 LEN=84 TOS=0x00 PREC=0x00 TTL=57 ID=5863 DF PROTO=ICMPTYPE=8 CODE=0 ID=34598 SEQ=1
`

Cool stuff! - The *SRC* address is the public address I am looking for. Let's shove this into elk.

# Logstash-ing OpenWRT's iptables

[Logstash](https://www.elastic.co/products/logstash), for those of you who haven't heard of it, is part of the becomming more and more famous [ELK Stack](https://www.elastic.co/elk-stack).

Logstash is the part that receives logs in any format, parses them to make sense out of them and sends them to [Elasticsearch](https://www.elastic.co/products/elasticsearch) which stores them in a queryable format.

## Objective overview

So what I need to do is the following:

1. Create an *iptables* rule that matches traffic to the website container and log any connections going there.
2. Send the kernel logs over to Logstash.
3. Parse the logs and send them to Elasticsearch.
4. Check result in Kibana
5. Profit!

## Let's get started then

So there's an little inconvenience with iptables, namely it [cannot log to an external file](https://askubuntu.com/questions/348439/where-can-i-find-the-iptables-log-file-and-how-can-i-change-its-location#answer-348448), or at least not easily.
Well that's fine, I'll read the logs from the `/var/log/kern.log` file...

![](/images/04-down-the-rabbit-hole-96fb77e8.png)

... if there was one!


It turns out that there are a few a [user-space utilities that are used to read/write to the system log (namely the *wtmp* file)](https://wiki.openwrt.org/doc/howto/log.essentials#logd_and_logread).

Cool stuff, before sending it to Logstash, let's see what are we actually logging:

![](/images/04-down-the-rabbit-hole-a8540aeb.png)

Right, that's just sending a simple GET request to my website...
You can see the entire SSL Handshake occuring and what not...

But I don't want that - I'm interested in something way more simpler - who accessed what on and when my website - I don't give a damn about the SSL handshake...

## Back to the drawing board

Perhaps I'm doing it wrong - I don't need logging at layer 4 but way higher - at level 7 (If you don't know what I'm referring, it's the [OSI Layers - a must know](https://www.webopedia.com/quick_ref/OSI_Layers.asp)).
HTTP is a layer 7 protocol and logging it cannot be done by a router which operates at layer 4 - it needs a higher level application to do that.

## So what can log traffic at layer 7?
[Nginx can do that!](https://superuser.com/questions/1266826/openwrt-redirect-incoming-wan-traffic-based-on-domain-name#answer-1266827) with the `proxy_pass` directive.
What's even better - OpenWRT has a nginx package! How better can it get?

So before tinkering with my router (which is kinda critical not to be down - see my [previous post](/blog/03-a-walk-down-infrastructure-lane/#the-public-part)) I decided to install the nginx proxy on another server and test it out.

The host I chose was `10.0.20.13`. So it basically runs an nginx instance that proxies connections to the `10.2.0.1` hosts that runs the website. Here is a picture that illustrates what I want to do:


![](/images/04-down-the-rabbit-hole-740c9e7f.png)

Having this setup, the goal is to see `10.3.2.1` in the access logs on `10.2.0.1`.

![](/images/04-down-the-rabbit-hole-8f780785.png)

Well, partial success.. - On one hand I still got the website but the web server still logged the proxy's address.

Luckily, it was a small tweak I had to do in the server settings.

[Here](https://ma.ttias.be/nginx-access-log-log-the-real-users-ip-instead-of-the-proxy/) is what I needed to do.

Have a read but the tl;dr; of it is that I needed to change the log format to log the original client's source ip which is passed as a header from the proxy server.

Add this to the **http {}** section of the nginx conf:

    log_format main '$http_x_forwarded_for - $remote_user [$time_local] '
    '"$request" $status $body_bytes_sent "$http_referer" '
    '"$http_user_agent"'

Afterwards make use of the specified log format by addind the `access_log` directive in your server block:

    access_log  /var/www/site/logs/access.log main


Adding these changes to the config produces the result I'm after:

![](/images/04-down-the-rabbit-hole-40f93cf5.png)

## Cool stuff! Let's smash it onto OpenWRT then

[Installing packages in OpenWRT is rather simple](https://openwrt.org/packages/start) - there is a package manager which is quite similar to `yum` and `apt` - it's called `opkg`:

`opkg update && opkg install nginx`

This will get our nginx instance up and running.

The next thing I did was to edit the config file located at `/etc/nginx/nginx.conf` and add the `proxy_pass` directive.:

    -- snip --
    server {
        listen       80;
        server_name  localhost;

        #charset koi8-r;

        #access_log  logs/host.access.log  main;

        location / {
            root   html;
            index  index.html index.htm;
            proxy_pass http://10.2.0.1
        }

    -- snip --

`curl`-ing the *http* port worked fine and I got the right client address in the access logs, however, my site is running *https* and all the examples of `proxy_pass` I saw were using *http* as backend server.

Just before getting worried that this won't be possible because of the SSL part I saw the [nginx documentation on the matter](https://docs.nginx.com/nginx/admin-guide/security-controls/securing-http-traffic-upstream/) that suggested proxying to ***https*** instead of ***http***.

Now in order to make this work I had to terminate the SSL connection at the OpenWRT nginx and setup a new one with the backend server. I also had to copy the Let's encrypt certs on the OpenWRT to allow SSL termination to occur.

The documentation link I referred specifies some optimisation options to reduce CPU usage and it all seemed perfect.

Well let's try it out!

![](/images/04-down-the-rabbit-hole-66e4d436.png)

WTF?

Goggliing the error yields only tutorials on how to recompile the nginx package...
A bit more searching finally [answers my question](https://github.com/openwrt/packages/issues/864#issuecomment-73244902) on why it doesn't work:

![](/images/04-down-the-rabbit-hole-b37bd2bc.png)

To save some space, the OpenWRT team (or however maintains the nginx package for OpenWRT) has decided to not include the SSL module and I get it - why would you use your router as a web proxy that will also encrypt the traffic to the upstream servers right?

### Let the recompilation begin then...

So I followed [this guide](https://wonpn.com/2018-03-15-compile-nginx-with-ssl.html) to figure out how to recompile the nginx package so that it includes the SSL module...

The guide suggested downloading the [OpenWRT's source code](https://github.com/openwrt/openwrt.git), using `make menuconfig` to add SSL support to the nginx package and compiling it. Afterward I had to copy over the nginx binary that would supposedly *just work*.

It took me like 2 hours or so to obtain a compiled version of OpenWRT and then another 40 minutes to compile the nginx package with SSL support...

[opkg's documentation](https://wiki.openwrt.org/doc/techref/opkg#package_manipulation) suggested installing *.ipk* files by running `opkg install /path/to/ipk_file.ipk`.
Right, but when I ran that for some reason it just downloaded the official package from OpenWRT's repositories.

### Well screw you then opkg

[It turned out that ipk files are just normal tar archives](https://www.linkedin.com/pulse/manual-extractioninstallation-ipk-packages-openwrt-amit-kumar/) that just need to be extracted at the right location.

The steps to manually install an .ipk file are as follows:

1. Extract the ipk file somewhere: `tar zxpvf /path/to/ipk_file.ipk`

    This extracts 3 files:

        ./debian-binary
        ./data.tar.gz
        ./control.tar.gz
2. data.tar.gz is the file we need. To install it we just need to extract it to `/`:

        cd /
        tar zxpvf /path/to/data.tar.gz


It seemed that all my hopes and dreams would come true as I saw the nginx files being extracted to their correct locations.

### The unfortunate part

Alas, running `/etc/init.d/nginx start` would not start the nginx service for some reason. After spending some time debugging I tried running the **nginx** binary itself which just exited with an `-ash` error that complains that `/usr/sbin/nginx` file is missing.
And that's when I'm running that binary ... obvious error right?
I couldn't figure out why this error occurer so I was back to square 1...

### A new hope - HAProxy?

I got quite frustrated after being so close and failing eventually. Then I decided to do a bit more reading on what exactly I want to acomplish and the tools that I'll need.

After reading carefully through all the posts and guides on the nginx SSL issue, I noticed something I had missed before:

![](/images/04-down-the-rabbit-hole-db75dc6c.png)

What is this fancy haproxy thing? I've heard it before and I know it is quite used but I didn't really need to implement it in my infrastrucutre... yet

And it has SSL support and that is quite important to me as it turned out.
### Time to HAProxy!

HAProxy's configuration is quite intuitive - the main parts being `frontend`, `backend` and `listen` block that combines the former 2 for brevity.
As you'd expect the `frontend` part is what is facing the world and accepts input traffic whereas the `backend` part is where traffic is being proxied to.

#### To terminate or not to terminate?

Now there is something important you need to know when dealing with proxies and *https* traffic - the concept ot SSL passthrough and SSL termination. [In this blog post both concepts are explained quite well in the context of HAProxy](https://serversforhackers.com/c/using-ssl-certificates-with-haproxy).

Basically you have to choose whether you want to terminate the ssl connection at the proxy and speak http to the backend server or make the proxy work on a lower level and just pass through tcp packets without knowing what they are about and leave the ssl termination for the backend web server.
Each of these methods has their pros and cons and there is no *better* choice - it all depends on your need.

So I had to take back a step and thing what would best fit my needs:

I want my backend server to speak https regardless of whether there is a proxy in front of it or not - this would allow me to remove the proxy anytime I want without leaving my server serving plain http content.
This means using the proxy in passthrough mode, however, I also need to add a header to the request to ensure I'm logging the original client's address and not the proxy's one - this means ssl termination.

As it happens quite often - my needs required a mix from both options.
After reading a couple of guides on [SSL termination](https://en.wikipedia.org/wiki/TLS_termination_proxy) and SSL passthrough I came up with the following config:


    listen http_proxy
    	bind 213.191.184.70:80
    	mode http
    	option forwardfor
    	option http-server-close
    	reqadd X-Forwared-Proto:\ http
    	reqadd X-Forwarded-Port:\ 80
    	balance roundrobin
    	server server01 10.2.0.1:80

    listen https_proxy

    	# Bind to port 81 and 444 on all interfaces (0.0.0.0)
    	bind 213.191.184.70:443 ssl crt /root/le/live/viktorbarzin.me/viktorbarzin.me.pem

    	# We're proxying HTTP here...
    	mode http
    	option forwardfor
    	option http-server-close
    	reqadd X-Forwarded-Proto:\ https
    	reqadd X-Forwarded-Port:\ 443

    	# Simple HTTP round robin over two servers using the specified
    	# source ip 192.168.1.1 .
    	balance roundrobin
    	server server01 10.2.0.1:443 ssl verify none

It basically forwards both plain `http` and `https` requests to the backend leaving it to decide what to do with them.
When doing the https part, it terminates the SSL connection and establishes a new one with the backend server.
On both occasions it adds `X-Forwarded-*` headers to let the nginx server on the other side know it is behind a proxy.
A little quirk I found in HAProxy is that when binding to a SSL port and specifying that it should listen for ssl connections, the certificate you specify needs to containt both the cert and the public key (cat the cert and key files into a pem one and let HAProxy use it).

The last thing to do is start the HAProxy service and look at the logs:

![](/images/04-down-the-rabbit-hole-2d9ccfaa.png)

I didn't need to wait for long to find some dodgy requests coming over all the time...

I didn't have time to setup \*beats services to send the logs over to ELK but when I do, I may or may not update this post.

# Conclusion

This experience was very fullfilling once I got the HAProxy up and running and most importantly doing what I needed it to do.
Messing around with the *kb* 's of space that was available on my router was also fun - you don't get deal with so little amount of space every day.
Oh I also wrote grok patterns to parse the iptables' logs since I did send them over to logstash and at the time I didn't check that it was actually what I needed. So yeah, wrote those awful regexes to parse iptables log only to find out that I don't need that...

Till next time.
