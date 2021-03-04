---
title: "About me"
date: 2018-09-02T00:22:22+01:00
author: "Viktor Barzin"
draft: false
description: "This page tells more about myself."
tags: []
firstImgUrl: "https://viktorbarzin.me/images/index-f170bc66.png"
---

Hi there! I'm Viktor.

I'm {{ whatever year we are currently }} - 1998 years old and I'm currently working as a [Production Engineer](https://engineering.fb.com/category/production-engineering/) at Facebook.

You can find me on [facebook](https://www.facebook.com/viktor.barzin), [github](https://github.com/ViktorBarzin), [linkedin](https://linkedin.com/in/viktor-barzin) and [twitter](https://twitter.com/ViktorBarzin).

## Contact me
If you want to chat, hmu on any of the above or email me using this PGP key:
```bash
curl https://viktorbarzin.me/gpg | gpg --import
```
Email: [contact@viktorbarzin.me](mailto:contact@viktorbarzin.me)

### Reserve time with me
<!-- Calendly badge widget begin -->
<div class="calendly-inline-widget" data-url="https://calendly.com/viktorbarzin/30min" style="min-width:320px;height:630px;"></div>
<script type="text/javascript" src="https://assets.calendly.com/assets/external/widget.js"></script>
<!-- Calendly badge widget end -->

### About this site

The website will mostly be me sharing my experience with various technologies. I'll post new articles every now and then on various technologies I've come across.

### Services

This is a list of public services I currently operate:

#### Apps
- This website - https://viktorbarzin.me/
- Status page to monitor the status of my services - https://status.viktorbarzin.me/
- Ads-free f1 streaming service - http://f1.viktorbarzin.me/
- Infrastructure dashboard visualizations - https://grafana.viktorbarzin.me/
- Drone CI/CD - https://drone.viktorbarzin.me/
- Hackmd for online collaboration - https://hackmd.viktorbarzin.me/
- Private bin for secure text sharing - https://pb.viktorbarzin.me/

#### Dev
- DNS server (no recursion for public) - ns1.viktorbarzin.me and ns2.viktorbarzin.me
- KMS Windows activator - https://kms.viktorbarzin.me/
- Helper page to get access to my wireguard vpn - https://wg.viktorbarzin.me/
- Service to setup your `kubectl` to get access to my Kubernetes cluster - https://kubectl.viktorbarzin.me/
- Mailserver (imaps and pop3s)

#### Internal
- Pihole for ads-free browsing
- Kubernetes dashboard for a GUI overview of my cluster
- Ceph web UI to monitor the overall status of the CephFS
- DNSCrypt for DNS-over-HTTPS to anonymise my infra's DNS lookups
- Internal bind dns instance to map services to IPs
- Webhook handler service to allow remote events triggering such as from events originating from GitHub, DockerHub etc.
- Wireguard VPN instance to have secure access to all the rest.

In [the blog section](/blog) I occasionally blog about interesting issues and how I overcame them.

Happy reading! Hope you enjoy :-)

{{< rawhtml >}}
<div id="fb-root"></div>
    <script>
    window.fbAsyncInit = function() {
        FB.init({
        xfbml            : true,
        version          : 'v10.0'
        });
    };

    (function(d, s, id) {
    var js, fjs = d.getElementsByTagName(s)[0];
    if (d.getElementById(id)) return;
    js = d.createElement(s); js.id = id;
    js.src = 'https://connect.facebook.net/en_US/sdk/xfbml.customerchat.js';
    fjs.parentNode.insertBefore(js, fjs);
    }(document, 'script', 'facebook-jssdk'));
    </script>

    <!-- Your Chat Plugin code -->
    <div class="fb-customerchat"
    attribution="setup_tool"
    page_id="112276754007935"
theme_color="#0A7CFF">
      </div>

{{< /rawhtml >}}
