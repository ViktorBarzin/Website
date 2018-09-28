---
title: "03 A Walk Down Infrastructure Lane - My Home Lab Setup"
date: 2018-09-28T15:36:21+03:00
draft: true
---

# Intro

As the tittle suggests It's time to go down infrastructure lane. In this blog post
I'll show my "home" lab and all the services I've built so far.

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
**I'll post the full network diagram at the end** so you can see for yourself each of the vms out there.

**Accessing the network can be done only via VPN** - this can be done at ***vpn.samitor.com***  on **port 1194/udp**.
Once you connect you'll find yourself connected to an **Ubuntu server** vm running the **vpn server only**.

I used to run the vpn service in docker but I recently changed that since [you cannot log container's iptables connections](https://stackoverflow.com/questions/39632285/how-to-enable-logging-for-iptables-inside-a-docker-container#answer-39681550) and I need the monitoring feature.

Depending on the VPN certificate that you have, you'll join a **different network** that will give you the correct permissions to access resources on the network.
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
and added as a rule in here (look the rule that allows clients on *10.3.3.0/24* access to *10.0.101.10* host).

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

### The *Container Host* currently runs the following containers:

- [**Nginx web server**](https://hub.docker.com/_/nginx/) that **hosts the website you're watching** right now.
- A [**socks5 proxy**](https://hub.docker.com/r/serjs/go-socks5-proxy/) which I give access to people that need proxying their traffic via a bulgarian ip and do not need to be issued a vpn certificate.
- A very important [**DNS container**](https://hub.docker.com/r/sameersbn/bind/) because noone likes remembering ip addresses anyway. It currently **has more than 20 A records just for my services**.
- [**Nginx web server**](https://hub.docker.com/_/nginx/) that hosts **my notes on how to activate windows machines** that I ocassionally give out access to friends

There used to be an owncloud service but I've removed that since it wasn't used.

#### Here is a nice cli summary:

![](/images/03-A-walk-down-infrastructure-lane-1b91c017.png)

### ELK Stack
I have a dedicated vm for **ELK** - this is the Ubuntu server at *10.0.20.13*.
It currently collects only **the logs from the pfSense appliance**. Here is how that looks like:

![](/images/03-A-walk-down-infrastructure-lane-e69a61a1.png)

Recently, I had some adventures debugging grok files. I'll soon be setting up **more monitoring via [beats](https://www.elastic.co/products/beats)**.
### The *Mail server* is where my mailing service runs.
It is a [Roundcube](https://roundcube.net/) installation with [postfix](http://www.postfix.org/) running as mail transfer agent.
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

![](/images/03-A-walk-down-infrastructure-lane-c1343164.png)

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

Now in the begining I said I have 2 sites - one that hosts my ESXi hosts and another one which I labeled *home*. What has *home* to do with my main infrastructure site?

Well the catch is that at my main site I **do not own and manage the public IP address**.
The **only open port I have is 1194** and this is quite insufficient for my needs.

#### So how do I run a mail server, 2 websites and what not with only 1 open port?

Remember the router at home? It is running [OpenWrt](https://openwrt.org/) which is a sort of distro for routers.
Maybe **busybox on steroids** is more accurate.

Anyway, it **has a VPN certificate that connects straight into the main site**.
**I've forwarded ports on my router at home to services in the vpn network** linking the 2 networks.

This is how the public site of my network looks like:

![](/images/03-A-walk-down-infrastructure-lane-a194c284.png)

So each time you are visiting this site, or sending me mail at [viktorbarzin@samitor.com](mailto:viktorbarzin@samitor.com) **you are going through the router at home which is routing traffic via the vpn eventually reaching its target service**.

I've also bridged the **wifi network at home to route the *10.0.0.0/8* network via the vpn interface** so when I'm at home I don't need to connect to the vpn.

#### You can see the full network topology [here](/images/net-topology.png)

# Conclusion

I hope this gives a general idea of what my lab setup looks like. I've spent an year or so building it.
In the near future I'd like to setup more monitoring via [ELK beats](https://www.elastic.co/products/beats) and also setup a [Kubernetes cluster](https://kubernetes.io/).
