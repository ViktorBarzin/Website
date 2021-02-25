---
title: "17 Home Lab v2"
date: 2021-02-25T19:17:55Z
author: "Viktor Barzin"
description: ""
sitemap:
   priority: 0.3
tags: ["home", "lab", "bind9", "dns", "dnscrypt", "drone", "ci", "cd", "f1", "stream", "hackmd", "kms", "kubernetes", "k8s", "dashboard", "mail", "server", "smtp", "imap", "metallb", "network", "load balancer", "prometheus", "grafana", "alertmanager", "pihole", "privatebin", "webhook", "website", "wireguard", "vpn"]
firstImgUrl: "https://viktorbarzin.me/images/17-home-lab-v2-4-19-27-38.png"
draft: false
---

# Introduction

My home lab setup has changed a lot since my last [post](/blog/03-a-walk-down-infrastructure-lane/) in 2018.
Now it's 2021 and hype dictionary has change significantly.

I've spent the last year or so adopting the cloud-first mindset and my infrastructure has evolved.
This will be a 2 part series where I'll showcase my home lab services and some of the interesting challenges I faced while building them.

In this post I'll list all the applications I am currently running and what's their use case and in the second part I will go into detail of how I built them and some of the more interesting challenges I faced during this endeavour.

# Service Showcase
(sorted alphabetically)
## [Bind9](https://www.isc.org/bind/) DNS Server
- Used as a primary DNS for [`viktorbarzin.me`](https://who.is/dns/viktorbarzin.me) zone.

   ```bash
   ╰─$ dig -t NS viktorbarzin.me

   ; <<>> DiG 9.16.11-RedHat-9.16.11-2.fc34 <<>> -t NS viktorbarzin.me
   ;; global options: +cmd
   ;; Got answer:
   ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 56877
   ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 5

   ;; OPT PSEUDOSECTION:
   ; EDNS: version: 0, flags:; udp: 4096
   ; COOKIE: 1ffbde5b921461e7010000006031b8f7ce52dd866264225d (good)
   ;; QUESTION SECTION:
   ;viktorbarzin.me.               IN      NS

   ;; ANSWER SECTION:
   viktorbarzin.me.        86400   IN      NS      ns2.viktorbarzin.me.
   viktorbarzin.me.        86400   IN      NS      ns1.viktorbarzin.me.

   ;; ADDITIONAL SECTION:
   ns1.viktorbarzin.me.    86400   IN      A       213.191.181.130
   ns2.viktorbarzin.me.    86400   IN      A       213.191.181.130
   ns1.viktorbarzin.me.    86400   IN      AAAA    2a00:4802:360::367
   ns2.viktorbarzin.me.    86400   IN      AAAA    2a00:4802:360::367

   ;; Query time: 57 msec
   ;; SERVER: 10.0.20.1#53(10.0.20.1)
   ;; WHEN: Sun Feb 21 01:35:51 GMT 2021
   ;; MSG SIZE  rcvd: 196
   ```
- [Terraform module](https://github.com/ViktorBarzin/infra/tree/master/modules/kubernetes/bind)
## [Dnscrypt](https://dnscrypt.info/)
- Service to issue DNS queries over HTTPS thus improving privacy.
- You can read more about it in my blog post about [DNS over HTTPS](/blog/14-dns-over-https/).
- Everything that uses internet on my network does DNS resolving via this dnscrypt which anonymises outgoing queries .
- [Terraform module](https://github.com/ViktorBarzin/infra/tree/master/modules/kubernetes/dnscrypt).

## [Drone CI/CD](https://www.drone.io/)
- Continuous Integration/Continuous Delivery service for dynamic infra update.
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/drone/main.tf).

| | Build Status  |
|:-:   |:-:|
| Infra  | [![Build Status](https://drone.viktorbarzin.me/api/badges/ViktorBarzin/infra/status.svg)](https://drone.viktorbarzin.me/ViktorBarzin/infra)  |
| Website  | [![Build Status](https://drone.viktorbarzin.me/api/badges/ViktorBarzin/Website/status.svg)](https://drone.viktorbarzin.me/ViktorBarzin/Website)  |
|   |   |

## F1 Stream
- Aggregator site which I use update and use to watch F1 without the annoying pop-ups.
- Links to existing services but I block all annoying popups and ads.
- Accessible at http://f1.viktorbarzin.me (Important to open as **http** because some streams use http as source and browser get annoyed by mixed content and I'm too lazy to reverse proxy them).
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/f1-stream/main.tf).

## [Hackmd](https://github.com/hackmdio)
- Service for _Real-time collaboration on documentation in markdown._
- FOSS version of google docs and quip.
- Accessible at https://hackmd.viktorbarzin.me
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/hackmd/main.tf).

## [KMS](https://docs.microsoft.com/en-us/windows-server/get-started/kmsclientkeys) Licensing Server
- KMS server that I use for licensing Microsoft Windows and Office packets.
- Instructions on how to use at https://kms.viktorbarzin.me
- Don't abuse :-)
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/kms/main.tf).

## [Kubernetes Dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/)
- Dashboard for visualizing Kubernetes resources.
- Accessible at https://k8s.viktorbarzin.me (client certificate required).

![](/images/17-home-lab-v2-0-01-49-51.png)
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/k8s-dashboard/main.tf).

## [Mail Server](https://github.com/docker-mailserver/docker-mailserver)
- SMTP, IMAP mail server used for accounts in `@viktorbarzin.me` domain.
- Try it out - send me an email at `contact@viktorbarzin.me`.
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/mailserver/main.tf).

## `metallb` Network Load Balancer
- Network load balancer to allow kubernetes services to use `LoadBalancer` service type and obtain an IP from outside the cluster.
- Removes the coupling and hence the single point of failure between kubernetes nodes and externally mapped ports (more on this later).
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/metallb/main.tf).


## Monitoring Services
### [Prometheus](https://prometheus.io/)
- Used for collecting metrics for the entire infra starting from Kubernetes resources to iDRAC SNMP readings and OpenWRT stats.
- Accessible at https://prometheus.viktorbarzin.me (client certificate required).

![](/images/17-home-lab-v2-0-01-55-29.png)

### [Grafana](https://grafana.com/)
- Used for prettier visualization based on the Prometheus metrics.
- Dashboards - https://grafana.viktorbarzin.me/dashboards
<iframe src="https://grafana.viktorbarzin.me/d/N9uZBy8Wz/kubernetes-cluster-overview?orgId=1&from=1613697460872&to=1613870260872&var-node=k8s-master&var-namespace=metallb-system&var-container=controller&var-duration=6h" scrolling="yes" width="100%" height=600> </iframe>

### [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/)
- Used for alerting based on Prometheus metrics.
- Accessible at https://alertmanager.viktorbarzin.me (client certificate required)

Example email alert:

![](/images/17-home-lab-v2-0-02-01-32.png)

- [Terraform module for all monitoring services](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/monitoring/main.tf).

## [Pihole](https://pi-hole.net/)
- Service to block Ads on DNS level which proves to be more effective than installing extensions.
- Accessible at https://pihole.viktorbarzin.me (client certificate required).
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/pihole/main.tf).

![](/images/17-home-lab-v2-0-02-18-46.png)

## [Privatebin](https://privatebin.info/)
- Service to securely share snippets. Similar to [pastebin](https://pastebin.com) but content is encrypted.
- Accessible at https://pb.viktorbarzin.me and https://privatebin.viktorbarzin.me
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/privatebin/main.tf).

![](/images/17-home-lab-v2-0-02-20-47.png)
# Status Page
- External status page to monitor my external availability.
- Accessible at https://status.viktorbarzin.me 
- Terraform resources part of monitoring module.

<script type="text/javascript" src="https://cdn.jsdelivr.net/gh/davidjbradshaw/iframe-resizer@master/js/iframeResizer.min.js"></script>
<iframe class="htframe" src="https://wl.hetrixtools.com/r/38981b548b5d38b052aca8d01285a3f3/" width="100%" scrolling="no" sandbox="allow-scripts allow-same-origin allow-popups" onload="iFrameResize([{log:false}],'.htframe')"></iframe>

## Webhook Handler

- A small project I used to get more experience with Golang.
- Used for handling arbitrary webhooks from various services and execute actions on the cluster side.
- Mostly deprecated in favor of Drone CI.
- Accessible at https://webhook.viktorbarzin.me/
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/webhook_handler/main.tf).

## Website
- This website you are currently looking at.
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/blog/main.tf).

## [Wireguard](https://www.wireguard.com/) VPN
- My VPN service of choice.
- Migrated off from OpenVPN due to better performance but mostly operational simplicity and hype. 
- There is also a web ui to make certificate creation easier.
- Accessible at https://wg.viktorbarzin.me/
- [Terraform module](https://github.com/ViktorBarzin/infra/blob/master/modules/kubernetes/wireguard/main.tf).

# High Level Overview

All of these services are deployed inside a Kubernetes cluster with 1 master and 5 worker nodes.
Each node is a VMWare virtual machine all of which run on a single ESXi host.

More technical details in part 2.
