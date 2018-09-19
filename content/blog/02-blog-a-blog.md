---
title: "02 Blog a Blog - The creation of this site"
date: 2018-09-17T15:36:49+03:00
draft: false
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
I won't cover the ceation of the actual ui - it is a statically generated website from markdown files (you can find the sources [here](https://github.com/ViktorBarzin/Website)).

Just google for a [static site generator](https://www.creativebloq.com/features/10-best-static-site-generators) and you'll find plenty. I'm using [Hugo](https://gohugo.io/) and I quite like it.

# Step 1: Get a domain
You could say I wasn't particularly creative when choosing the domain name but oh well.
I'm using the [GoDaddy](https://godaddy.com) registrar and I'm rather happy so far.
Their documentation is a bit sluggish  especially when it comes to more advanced DNS needs but
overall they are fine.

![](/images/02-blog-a-blog-278df7d1.png)

# Step 2: Setup DNS and run test site
Next we need a DNS A record to point to my website's host. I am hoting the website
myself on my own infrastructure which I may describe in another blog post.

![](/images/02-blog-a-blog-b734bf08.png)

Open some firewall ports and we have a running website publicly accessible!

![](/images/02-blog-a-blog-dccb3c4e.png)

![](/images/02-blog-a-blog-41272fed.png)

Done? Well if you were making a website in 2010 yes, maybe you're done, however, in 2018 we have DevOps and SecOps and what not.

As a security wanna-be consultant I'd like my site to be secure (despite it being just static content).

I wanted to add some other stuff:

- Automatic deployment
- SSL certificate
- Automate the deployment process so I can replicate it later if needed

# Step 3: Let's Encrypt it
If you don't know what [Let's Encrypt CA](https://letsencrypt.org) do and you own a website, you should get familiar with them.
The TL;DR is that they give free SSL certificates with almost no configuration required by you.

Since most people don't have a PhD in Cryptography, and setting up SSL may require one, I used
the [certbot client](https://certbot.eff.org/). If you have a general idea of what you need to do,
the certbot client will take care of the crypto for you. It supports many platforms and webservers
and makes setting up let's encrypt certificates as easy as clicking a few buttons on the installation prompt.

All good so far, I span up a [nginx container](https://hub.docker.com/_/nginx/) real quick and ran the installer.
The nginx container uses a lightweight Debian 9 (at the time of writing) and is supported by certbot.
The installer is quite user-friendly, however, at the end of the installation I hit an error:

![](/images/02-blog-a-blog-34b0b184.png)

Like most devs, I'm quite lazy, however, this error meant I had to do some more reading about certbot and let's encrypt.
If you notice the error message says something about lack of sufficient authorization - absolutely wrong!

I noticed the URI it was trying to access - "/.well-known/" - Tried opening that url and it gave me a 404. F**K!

After long hours of reading into the documentation of let's encrypt, certbot, understanding how SSL certificates work and what not I finally managed to narrow down the issue.
Some of the complications came from the fact that the installation is in a container so I wasn't quite sure where the issue was - was it permissions, was it invalid config ...

The ip you can see on the error page was also dodgy - why was my domain resolving to another IP?
I rerun the certbot client a few times and the ip seemed to change in seemingly random fashion - some times it would show this weird ip and others it would resolve to the correct one.
Let's look my domain again then

![](/images/02-blog-a-blog-a843d8dc.png)

Aha that looks like an issue! After some more time swearing I looked at the DNS web panel to find this weird record that was pointing to **@** and resolving to **PARKED**. So wtf is this **PARKED** thing?

![](/images/02-blog-a-blog-b1569364.png)

Obvious right?...

After removing the parked record, I rerun the client again but it failed once more:

![](/images/02-blog-a-blog-9ed96a28.png)

This seems worrying. After consulting the [documentation](https://letsencrypt.org/docs/rate-limits/) it turned out I have reached the rate limits for this hostname and I had to wait before I could issue any new certificates for this domain...

After waiting out the rate limit, I had some more issues with nginx config and docker but I finally got the craved message:

![](/images/02-blog-a-blog-1b590737.png)

Certbot can tweak your webserver's configuration to redirect all request to port 443.
In the case of nginx it is **really important** that you set the ***server_name*** parameter to point to your domain. Otherwise it will not be able to determine which config to alter.

Finally got it working with HTTPS

![](/images/02-blog-a-blog-a1601d49.png)


# Step 4: Automate deployment
So all I had to do now is automate the deployment process. At that moment I had a local work copy of the project on my laptop and a separate one on the hosting server.
My goal was to edit a markdown file, commit and the changes would be resembled on the website.
So the workflow I came up with looked like this:

![](/images/02-blog-a-blog-a5eb617d.png)

So rebuilding the static files is as easy as running the *hugo* command. Now, applying the changes
to a remote server without rsync-ing tar files would require some more configuration.

## Step 4.1: Setup bare repository
So what is a *bare repository*? [This answer](http://www.saintsjd.com/2011/01/what-is-a-bare-git-repository/) explains is pretty well.
Basically, the repository created with *git init* or *git clone* is called a *working directory* - we use them while developing the project.
A *bare repository* on the other hand, is used solely for sharing purposes - GitHub is the best example for a bare repository.

So lets create a directory that will hold the repository index:
{{< highlight bash >}}
mkdir blog.git
cd blog.git
git init --bare
{{< /highlight  >}}

I also need to add the remote origin to my git client:

```bash
git remote add production ssh://<user>@host/path/to/bare/repo.git
```

## Step 4.2: Git hooks
[Git hooks](https://githooks.com/) are scripts that execute on various git events - commits, push and receive.
This is a wonderful feature and if you haven't used them before, you should check them out.

Most of the time I am using the *post-receive* hook that triggers right after code has been pushed to a bare repository.
The script I wrote checks out the code from the repository and keeps only the static files:

```bash
#!/bin/bash
# Checkout repo
git --work-tree=/ansible_files/nginx/blog --git-dir=/ansible_files/nginx/blog.git/ checkout -f
# remove all but public folder
find /ansible_files/nginx/blog -maxdepth 1 | grep -v public | grep 'blog/' | xargs rm -rf
mv /ansible_files/nginx/blog/public/* /ansible_files/nginx/blog
rmdir /ansible_files/nginx/blog/public
docker exec nginx-blog service nginx reload
```

## Step 5: Deploy one-liner
So having this setup enables me to push changes to the live website using this simple one-liner:
```bash
hugo && git add . && git commit -m '<commit message>' && git push production
```

# Automate the infrastructure setup
I'd like to automate to setup process so if I were to set the entire thing again, it would be as easy as picking the right ansible role to run.

This would save me the pain of going through all the stuff I've already gone through before and waste time not learning anythin new.
I'd rather spend this time tweaking a role that can be reused later on.

Let me briefly describe my *"production"* vm. I'd like to segregate my services - each thing in its own box.
So instead of setting aside an entire vm just a single web server I run all the stuff in containers.

## Ansible + Docker = ♥

echo 'deb http://ftp.debian.org/debian stretch-backports main' >> /etc/apt/sources.list && apt update && apt-get install -y python-certbot-nginx -t stretch-backports && certbot --nginx -d viktorbarzin.me --webroot-path /usr/share/nginx/html --debug-challenges --staging
