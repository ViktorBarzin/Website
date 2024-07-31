---
title: "About me"
date: 2018-09-02T00:22:23+01:00
author: "Viktor Barzin"
draft: false
description: "This page tells more about myself."
tags: []
firstImgUrl: "https://viktorbarzin.me/images/index-f170bc66.png"
---

{{< messenger >}}

Hi there! I'm Viktor.

I'm {{ whatever year we are currently }} - 1998 years old and I'm currently working as a [Production Engineer](https://engineering.fb.com/category/production-engineering/) at Meta.

You can find me on [facebook](https://www.facebook.com/viktor.barzin), [github](https://github.com/ViktorBarzin), [instagram](https://www.instagram.com/vikkbarzin), [linkedin](https://linkedin.com/in/viktor-barzin).

## Contact me

If you want to chat, hmu on any of the above or email me using this PGP key:

```bash
curl https://viktorbarzin.me/gpg.asc | gpg --import
```

Email: [contact@viktorbarzin.me](mailto:contact@viktorbarzin.me)

{{< rawhtml >}}

<!-- Calendly badge widget begin -->
<!-- If you find this, well done, I'll be interested to chat :) -->
<!-- <div class="calendly-inline-widget" data-url="https://calendly.com/viktorbarzin/30min" style="min-width:320px;height:630px;"></div> -->
<!-- <script async type="text/javascript" src="https://assets.calendly.com/assets/external/widget.js"></script> -->
<!-- Calendly badge widget end -->

{{< /rawhtml >}}

### About this site

The website will mostly be me sharing my experience with various technologies. I'll post new articles every now and then on various technologies I've come across.

### Services

I found that the list below keeps getting out of date as I keep adding new services to my cluster so to solve this problem I (you guessed it) setup another service to display everything that I currently self-host.
You can find all my latest projects with links (some require authentication) at [dashy.viktorbarzin.me](https://dashy.viktorbarzin.me).

#### Apps

Here are some of the apps I self host.
The full list (besides the terraform modules in my github repo) can be found at [dashy.viktorbarzin.me](https://dashy.viktorbarzin.me).

- This website - https://viktorbarzin.me/
- Status page to monitor the status of my services - https://status.viktorbarzin.me/
- Vaultwarden password manager - https://vaultwarden.viktorbarzin.me/
- Immich (Open source Google Photos alternative) - https://immich.viktorbarzin.me/
- Technitium DNS server (forwarder with DNS over HTTPS and Adblock for maximum privacy)
- Ads and popup-free f1 streaming service - http://f1.viktorbarzin.me/ (I update the sides every now and then whenever they don't work so you can bookmark this)
- Infrastructure dashboard visualizations - https://grafana.viktorbarzin.me/
- Drone CI/CD - https://drone.viktorbarzin.me/
- Hackmd for online collaboration - https://hackmd.viktorbarzin.me/
- Private bin for secure text sharing - https://pb.viktorbarzin.me/

#### Dev

- DNS server (no recursion for public) - ns1.viktorbarzin.me and ns2.viktorbarzin.me
- KMS Windows activator - https://kms.viktorbarzin.me/
- Helper page to get access to my wireguard vpn - https://wg.viktorbarzin.me/
- Mailserver (imaps and pop3s)

#### Internal

- Kubernetes dashboard for a GUI overview of my cluster
- Ceph web UI to monitor the overall status of the CephFS
- Webhook handler service to allow remote events triggering such as from events originating from GitHub, DockerHub etc.
- Tailscale VPN instance to have secure access to all the rest and use exit nodes from various geographical locations.

In [the blog section](/blog) I occasionally blog about interesting issues and how I overcame them.

Happy reading! Hope you enjoy :-)
