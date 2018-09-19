---
title: "02 Blog a Blog - The creation of this blog"
date: 2018-09-17T15:36:49+03:00
draft: true
---

Keypoints:

- busy around hackconf
- simple blog about how this blog was made
- fuck @PARKED A record
- server_name in nginx config
- certbot is dodgy af
    - rate limits!
- ansible the world
- deployment process:
    - markdown in atom
    - hugo deploy command
    - git bare repo
    - git hooks
    - post-receive hook
- todo: add securityheaders to nginx

# Intro
Recently I've been quite busy. I was helping with the organisation of [HackConf](https://www.hackconf.bg/en/) this weekend which was both awesome and exhausting.

Therefore this blog will be covering something simpler - how I created this site.
I won't cover the ceation of the actual ui - it is a statically generated website from markdown files.
Just google for a [static site generator](https://www.creativebloq.com/features/10-best-static-site-generators) and you'll find plenty. I'm using [Hugo](https://gohugo.io/) and I quite like it.


available domain

![](/images/02-blog-a-blog-278df7d1.png)

endor directory info

![](/images/02-blog-a-blog-82934686.png)

godaddy A record

![](/images/02-blog-a-blog-b734bf08.png)

viktorbarzin.me home page

![](/images/02-blog-a-blog-41272fed.png)

domain parking

![](/images/02-blog-a-blog-b1569364.png)

nslookup viktorbarzin.me

![](/images/02-blog-a-blog-a843d8dc.png)


openwrt allowed ports

![](/images/02-blog-a-blog-dccb3c4e.png)

certbot error
![](images/02-blog-a-blog-34b0b184.png)
echo 'deb http://ftp.debian.org/debian stretch-backports main' >> /etc/apt/sources.list && apt update && apt-get install -y python-certbot-nginx -t stretch-backports && certbot --nginx -d viktorbarzin.me --webroot-path /usr/share/nginx/html --debug-challenges --staging
