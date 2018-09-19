---
title: "02 Blog a Blog"
date: 2018-09-17T15:36:49+03:00
draft: true
---

Keypoints:

- busy around hackconf
- simple blog about how this blog was made
- fuck @PARKED A record
- server_name in nginx config
- certbot is dodgy af

![](/images/02-blog-a-blog-278df7d1.png)

![](/images/02-blog-a-blog-82934686.png)

![](/images/02-blog-a-blog-b734bf08.png)

![](/images/02-blog-a-blog-41272fed.png)

![](/images/02-blog-a-blog-a9c7af6e.png)

echo 'deb http://ftp.debian.org/debian stretch-backports main' >> /etc/apt/sources.list && apt update && apt-get install -y python-certbot-nginx -t stretch-backports && certbot --nginx -d viktorbarzin.me --webroot-path /usr/share/nginx/html --debug-challenges --staging
