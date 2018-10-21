---
title: "03 A Walk Down Infrastructure Lane - My Home Lab Setup"
date: 2018-09-28T15:36:21+03:00
draft: false
sitemap:
   priority: 0.3
---

# Intro

As the tittle suggests It's time to go down infrastructure lane. In this blog post
I'll show my "home" lab and all the services I've built so far.

I will do my best to keep this up to date so check this post regularly for updates, both to the content and the image at the end.
#### If you are interested in just the network topology, you can find it [here](/images/net-topology.png)

Without further due let's get started.

# Physical topology

So the physical topology is rather simple. It can be best explained by this photo:

![](/images/03-A-walk-down-infrastructure-lane-9fa36db1.png)

Site 1 is where my **main infrastructure is located**. The catch there is that the public-facing router
**is not mine and I cannot manage it**. My control comes at the second router - the one at *192.168.88.226*. I only have configured the **public-facing router to port forward port 1194 to my router** and thus have my vpn run through (more on that later).
Site 1 consists of **2 ESXi hosts connected with a simple linksys router** (the one at 192.168.88.226 on the image).

Site 2 consists of just the router at home but you'll see later why it's important.

# Logical topology

Now the fun part - the **logical layout**. Instead of describing all the virtual machines that I have,
I reckon it would be **more useful to explain what you'll hit** and what you can **access** once you're on the network.

**Accessing the network can be done only via VPN** - this can be done at ***vpn.samitor.com***  on **port 1194/udp**.
Once you connect you'll find yourself connected to an **Ubuntu server** vm running the **vpn server only**.

I used to run the vpn service in docker but I recently changed that since [you cannot log container's iptables connections](https://stackoverflow.com/questions/39632285/how-to-enable-logging-for-iptables-inside-a-docker-container#answer-39681550) and I need the monitoring feature.

Depending on the VPN certificate that you have, you'll join a **different subnet** that will give you the correct permissions to access resources on the network.
The IP that you'll get is **not** NAT-ed so I can **filter and track** the outbound connections **based on client IP** at the nearest firewall which happens to be the [**pfSense**](https://www.pfsense.org/) appliance at *10.0.30.1*. This is what we know so far:

![](/images/03-A-walk-down-infrastructure-lane-bc1a97ab.png)

Ths VPN vm is the only host in *VLAN30* so it is, in a sense, isolated from everything else. All connections coming from it are considered as **untrusted**.

The pfSense appliance is dropping all connections apart from the ones in the whitelist that I've build:

![](/images/03-A-walk-down-infrastructure-lane-a9561a20.png)

So in simple words what the above configurations shows is:

- Any client can issue DNS requests and access the internet.
- All the traffic is logged and sent to ELK stack (more on this later)
- The *10.3.2.1* client can access anything (that's me :P)

If any of the clients on my vpn want access to anything on the internal network it will be **explicitly allowed**
and added as a whitelist rule in here (look the rule that allows clients on *10.3.3.0/24* access to *10.0.101.10* host).

The *10.0.101.10* host is a simple Windows Server VM that is given to a 3rd party for testing purposes.

Machines in the *10.0.40.0/24* network are in VLAN 40 which is marked as **unsafe** and nothing in this VLAN is allowed access to the internal network (apart from DNS requests and zabbix info):

![](/images/03-A-walk-down-infrastructure-lane-d5369cc8.png)

I have a couple of not important machines in there. So our knowledge for the network expands to:

![](/images/03-A-walk-down-infrastructure-lane-6fafe929.png)

### The next important vlan is *VLAN 20*. I've marked it as *Important/Management VMs*.
The following hosts are present in this VLAN:

- **Container host** - responsible for hosting all containerized services (more on this later)
- **ELK Stack** - ELK Stack is used for collecting and aggregating logs
- **Mail Server** - this is my mailing service - SMTPs, POP3 and IMAP services hosted on this vm.
- **Windows Domain Controller** - centrally manages my windows hosts' authentication and authorization
- **Openfiler storage vm** - this is supposed to be some sort of a global datastore and everything should store their data in here but alas I'm currently using is just for NFS datastores for the ESXi hosts.

### The *Container Host* changes the most frequently and it currently runs the following containers:

- [**Nginx web server**](https://hub.docker.com/_/nginx/) that **hosts the website you're watching** right now.
- A [**socks5 proxy**](https://hub.docker.com/r/serjs/go-socks5-proxy/) which I give access to people that need proxying their traffic via a bulgarian ip and do not need to be issued a vpn certificate.
- A very important [**DNS container**](https://hub.docker.com/r/sameersbn/bind/) because noone likes remembering ip addresses anyway. It currently **has more than 20 A records just for my services**.
- [**Nginx web server**](https://hub.docker.com/_/nginx/) that hosts **my notes on how to activate windows machines** that I ocassionally give out access to friends
- A [privatebin](https://hub.docker.com/r/jgeusebroek/privatebin/) instance for the times when I need a private pastebin.
- An [Open Web analytics](https://github.com/vladk1m0/docker-owa) container that keeps track of user activity on my website - it will soon be replaced by [goaccess](https://goaccess.io/) which I see as way simpler, easier to setup and less hassle to maintain.

There used to be an owncloud service but I've removed that since it wasn't used.

#### Here is a nice cli summary:

![](/images/03-A-walk-down-infrastructure-lane-1b91c017.png)

### ELK Stack
I have a dedicated vm for **ELK** - this is the Ubuntu server at *10.0.20.13*.
It currently collects the logs from the *pfSense appliance*, the *Container host* and the *VPN Server vm*. Here is how that looks like:

![](/images/03-A-walk-down-infrastructure-lane-e69a61a1.png)

### The *Mail server* is where my mailing service runs.
It is a [Roundcube](https://roundcube.net/) installation with [postfix](http://www.postfix.org/) running as mail transfer agent and [Dovecot](https://www.dovecot.org/) as a IMAP and POP3 server.
I don't use the Roundcube web ui to access my mail - I use KDE's powerful [kmail](https://www.kde.org/applications/internet/kmail/) client.

##### ProTip: After couple of reinstalls I figured out that the installation can be automated with [iredmail](https://www.iredmail.org/)

### The *Domain Controller* VM is a Windows Server 2016 which I use purely for my windows trainings
I've done [Active Directory](https://en.wikipedia.org/wiki/Active_Directory) management, played around with [Group Policies](https://en.wikipedia.org/wiki/Group_Policy), powershell and what not.

### Finally, the [*Openfiler*](https://www.openfiler.com/) appliance.
I set it up right after I found out that VMWare's vSAN feature [is not free](https://www.networkworld.com/article/3243579/virtualization/review-vmware-s-vsan-6-6.html).

Openfiler is some sort of a **virtual NAS that is FOSS**. The NAS capabilities include **CIFS, NFS and HTTP**. It can also be used as an **iSCSI device** if need be. It provides some failover and High Availability features which is always nice. The best part is the it can be managed via a web interface.
Despite being a bit sluggish for me (might be because of insufficient resources) it behaves quite well.
Here is a screenshot of the home screen:

![](/images/03-A-walk-down-infrastructure-lane-8f7257a5.png)

So this concludes VLAN 20 walkthrough

![](/images/03-A-walk-down-infrastructure-lane-25ca6ac3.png)

### Last but not least is VLAN 10 which is the infrastructure manager vlan.
This is where my [vCenter Server Appliance](https://www.vmware.com/products/vcenter-server.html) lives.

![](/images/03-A-walk-down-infrastructure-lane-f215a868.png)

It is also where my [Zabbix Server](https://www.zabbix.com/) resides.
I'm using zabbix for host monitoring and real time alerting if something goes wrong.
Here is what zabbix looks like:

![](/images/03-A-walk-down-infrastructure-lane-8bad19bf.png)

Access to these 2 machines is **strictly filtered** since breaking into the vCenter could allow an attacker to change anything in the infrastructure.

The zabbix instance also has privileges to access anything on the network therefore it lives in the most protected and limited VLAN in the network.

# The public part

Now in the beginning I said I have 2 sites - one that hosts my ESXi hosts and another one which I labeled *home*. What has *home* to do with my main infrastructure site?

Well the catch is that at my main site I **do not own and manage the public IP address**.
The **only open port I have is 1194** and this is quite insufficient for my needs.

#### So how do I run a mail server, multiple websites and what not with only 1 open port?

Remember the router at home? It is running [OpenWrt](https://openwrt.org/) which is a sort of distro for routers.
Maybe **busybox on steroids** is more accurate.

Anyway, it **has a VPN certificate that connects straight into the main site**.
**I've forwarded ports on my router at home to services in the vpn network** linking the 2 networks.

This is how the public side of my network looks like:

![](/images/03-A-walk-down-infrastructure-lane-92ee6897.png)

So each time you are visiting this site, or sending me mail at [viktorbarzin@samitor.com](mailto:viktorbarzin@samitor.com) **you are going through the router at home which is routing traffic via the vpn eventually reaching its target service**.

I've also bridged the **wifi network at home to route the *10.0.0.0/8* network via the vpn interface** so when I'm at home I don't need to connect to the vpn.

# The ugly part

Now that all seems pretty and nice, however, there is a *small* caveat. I showed you the logical part of the things, but I didn't show you **exactly how that translates to the physical topology**.

I have **2 ESXi hosts** controlled by a **vCenter appliance**.

If you have a **single host**, you **can virtualize everything** and do whatever you want and lie the vms as much as you want about the physical topology beneath.
However, **once you have to step outside** in the real world, **things change dramatically**.
The main issue is that **each of the hosts has its own TCP/IP networking stack** therefore routing and iterface subnets need to be configured again for the second host as well and more importantly, **each of the hosts needs to know where everything else is**.

I **hoped that vCenter will manage this in some "magical" way but alas it wasn't the case**.
I wanted eventually **to move a VM between hosts without worrying about networking**.

I looked into [Distirbuted switches](https://www.vmware.com/uk/products/vsphere/distributed-switch.html),
[Private VLANs](https://en.wikipedia.org/wiki/Private_VLAN) and what not. Unfortunately neither did the job for me
and eventually **I had to setup a copy instance of the PfSense on the second host**.

**I was really reluctant to do that** since changing any configs in one of the instances, I had to replicate them in the second one so that everything is consistent.
But oh well, there it is

![](/images/03-A-walk-down-infrastructure-lane-ec1a5d94.png)

Now if I want to move a VM to the other host **I also need to change the according routes to it**.

Firstly, I have to add the routing information in the first pfSense instance. Here is what I currently route:

![](/images/03-A-walk-down-infrastructure-lane-92686158.png)

All of the routes that use the *t610 10.0.0.115* gateway are hosted on my **second ESXi host**.

For some reason, when matching any of these, **it sends it first to the gateway at *10.0.0.1* which then has to make the same routing decision**. This is how it looks on my linksys router:

![](/images/03-A-walk-down-infrastructure-lane-c9873515.png)

**It also routes the other way around** - VMs on my second host that need to access VMs on my first hosts also need to know where to find them - **this is done both at the linksys level as well as at the second pfSense instance**.

By default it routes the **entire `10.0.0.0/16` subnet via the pfSense at `10.0.0.114`**

I've made **identical vSwitches on both of my ESXi hosts**, so moving a **VM is rather easy**... just add the appropriate routings and it all works.


# Conclusion

I hope this gives a general idea of what my lab setup looks like. I've spent an year or so to build it.
In the near future I'd like to setup more monitoring via [ELK beats](https://www.elastic.co/products/beats) and also setup a [Kubernetes cluster](https://kubernetes.io/).

#### You can see the full network topology [here](/images/net-topology.png)
#### NOTE: this image will be updated from time to time.
