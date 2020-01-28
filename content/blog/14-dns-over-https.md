---
title: "14 DNS Over HTTPS"
date: 2020-01-28T22:40:13Z
author: "Viktor Barzin"
description: "This post is mainly about me sharing some very useful resources and bringing light onto the cool idea behind DNS-over-HTTPS (aka. DoH). I'll also share a simple setup on how to run your own DoH server to hide your DNS lookups from spying eyes."
tags:
  [
    "dns",
    "dns-over-https",
    "dns-over-tls",
    "nginx",
    "mozilla",
    "cloudflare",
    "privacy",
    "http",
    "dockerfile",
    "docker",
    "docker-compose",
    "firefox",
    "trr",
    "trusted recursive resolver",
  ]
firstImgUrl: "https://viktorbarzin.me/images/14-dns-over-https-2-22-29-48.png"
draft: false
---

# Introduction

This post is mainly about me sharing some very useful resources and bringing light onto the cool idea behind DNS-over-HTTPS (aka. DoH).

I'll also share a simple setup on how to run your own DoH server to hide your DNS lookups from spying eyes.

# What is DNS-over-HTTPS and why do I need it?

As you know, DNS is a rather simple protocol, used for resolving domain names to IP addresses.
It's been around for some time now ([since 1985](https://en.wikipedia.org/wiki/Domain_Name_System)) and it is not going anywhere anytime soon.

Unfortunately, the DNS queries (where you ask for an IP address of something) are **not** encrypted and hence all sort of bad things can happen to them - being seen (breaking **confidentiality**), being modified (breaking **integrity**) or being dropped all together (breaking **availability**) (read more about the [CIA triad here](https://whatis.techtarget.com/definition/Confidentiality-integrity-and-availability-CIA)).

Basically it has all the issues that plain HTTP has.
To solve these issues, HTTP**S** was introduced which adds an entire layer of encryption magic that ensures that none of these horrible things can happen to your packets.

Unfortunately, the DNS protocol does **not** have a way to encrypt the queries ([DNSSEC](https://en.wikipedia.org/wiki/Domain_Name_System_Security_Extensions) just provides means to authorize the response but does **not** hide it and it is still in plain text, hence people can analyze it).
Due to this, if someone was between you and the service you want to access (say your service provider) they could easily sniff your DNS requests and roughly figure out what and where you are doing something (_and of course monetize this information_).
In fact, if you've done any network forensics, one of the first things you would look at is DNS traffic in order to gain the big picture of the traffic that has been seen.

# Ways to encrypt DNS traffic

To tackle these issues, there have been some attempts at encrypting DNS payload and in general there are 2 mainstream ways to do so - **DNS-over-TLS** and **DNS-over-HTTPS**.

## DNS-over-TLS (DoT)

tl;dr is that DoT is similar to how people have secured other protocols such as

- Web HTTP (tcp/80) -> HTTPS (tcp/443)
- Sending email SMTP (tcp/25) -> SMTPS (tcp/465)
- Receiving email IMAP (tcp/143) -> IMAPS (tcp/993)
- Now: DNS (tcp/53 or udp/53) -> DoT (tcp/853)

Essentially DoT is TLS packet, with DNS payload:

![](/images/14-dns-over-https-2-22-30-13.png)

The issue with introducing a new port is that existing firewalls may block it.
This means that if clients want to resolve names they will have to downgrade to plain DNS which could allow attackers to perform downgrading attacks (example for a downgrade attack is [SSL Stripping](https://blog.cloudflare.com/performing-preventing-ssl-stripping-a-plain-english-primer/)).

## DNS-over-HTTPS (DoH)

DNS-over-HTTPS (DoH) on the other hand, uses regular HTTPS traffic to transport the DNS queries:

![](/images/14-dns-over-https-2-21-44-28.png)

This is very smart because it reuses the already existing infrastructure of HTTPS (including allowed port tcp/443) to send encrypted DNS requests.
This makes it as easy as adding a route to your webserver that will handle that traffic and send it to its upstream resolver effectively anonimizing the user doing the DNS query.

I would **strongly** recommend reading [this article from Cloudflare's blog](https://blog.cloudflare.com/dns-encryption-explained/) about encrypted DNS.
Basically the existence of this post is the reason why I'm not going into details as it has been explained very well with the right amount of details and images and I'll definitely won't be able to write it in a better way.
So go now, read that blog post and come back to finish mine.

### Once you've read the cloudflare post...

Open Wireshark and start filtering to see only your DNS traffic.
Open a browser and go to a website.
You'll be surprised the amount of DNS lookups you make just to **open** any site.

The cloudflare blog post mentions that there are ways to configure all of your devices to use DoH and a public DoH provider and solve your issue with the unencrypted DNS traffic.
To do so, you effectively set your DNS lookups to use a particular service provider e.g Cloudflare or Google.

However, **do you trust them?**
This would mean that they would know **all** of your lookups, including the client you are using to do them, which, if you are a privacy-concerned person like me, may not sound like the best idea.
Surely, much better than using no encryption at all but we can do better.

# Hosting a DNS-over-HTTPS server

Parsing the HTTP payload for the DNS data and then doing the appropriate query manually might be a painful process to do in a secure and reliable manner.
Luckily, somebody has already done such a service and it's under the MIT license so you can use it and self host it!

[This is a simple DNS-over-HTTPS server](https://github.com/m13253/dns-over-https) written in go, that complies with the respective RFCs and is quite easy to setup.
If you want the **full** details of setting up the DoH server, with an upstream resolver, a frontend nginx server and what not, you can have a read at [this](https://www.bentasker.co.uk/documentation/linux/407-building-and-running-your-own-dns-over-https-server) rather long post.

In the end of the day, what you need to do is compile and run the DoH server on some port, setup an HTTP**S** nginx site with a path (by convention `/dns-query`) that is forwarded to the DoH server and finally (optionally) you can setup your own DNS resolver or use someoneelse's (This way they will still know you do these queries, but will be unable to identify the end device that requests them so if you're multiple people using the DoH resolver, it'll be very hard to determine who is querying what)

What follows is a brief description of what I did to setup a DoH server in my environment so you can follow the steps to setup one on your own.

# Setting up DoH in my environment

In my environment, most stuff run in docker containers so the first thing I did was to create a `Dockerfile` that sets up the dns-over-https server:

    FROM golang

    WORKDIR /
    COPY doh-server /doh-server
    COPY doh-server.conf /doh-server.conf

    CMD ["/doh-server"]

I had the `doh-server` binary already compiled locally.
It is a better idea to compile the `doh-server` code inside the container, but since my containers run on `x86` architecture it's fine to just copy over the binary.

To compile the binary run

```bash
make
```

inside the root directory of the project (where the `Makefile` is).

This creates a bunch of files as well as the `doh-server` binary which is inside the `doh-server` directory.

Another file you will need is the `doh-server.conf` config where we specify 2 important things -

- Port to listen onto (the DoH server is still an HTTP server)
- The upstream DNS resolver that we are going to use

My config looks like this (upstream DNS server IP intentionally hidden, you can use `1.1.1.1` or your own DNS service like I do)

    # HTTP listen port
    listen = [
        "0.0.0.0:8053",
    ]

    # TLS certification file
    # If left empty, plain-text HTTP will be used.
    # You are recommended to leave empty and to use a server load balancer (e.g.
    # Caddy, Nginx) and set up TLS there, because this program does not do OCSP
    # Stapling, which is necessary for client bootstrapping in a network
    # environment with completely no traditional DNS service.
    cert = ""

    # TLS private key file
    key = ""

    # HTTP path for resolve application
    path = "/dns-query"

    # Upstream DNS resolver
    # If multiple servers are specified, a random one will be chosen each time.
    upstream = [
        "<some DNS service that I own>:53"
    ]

    # Upstream timeout
    timeout = 10

    # Number of tries if upstream DNS fails
    tries = 3

    # Only use TCP for DNS query
    tcp_only = false

    # Enable logging
    verbose = true

    # Enable log IP from HTTPS-reverse proxy header: X-Forwarded-For or X-Real-IP
    # Note: http uri/useragent log cannot be controlled by this config
    log_guessed_client_ip = false

With that up and running, all is left is to setup an HTTPS nginx web server that will forward requests to the DoH container.
I have automated the bootstrapping process of the nginx container and the result config (with trimmed optimizations for simplicity) looks like this:

    events { }

    http {
        server {
            server_name viktorbarzin.me;
            listen 443 ssl;
            ssl_certificate /etc/fullchain.pem;
            ssl_certificate_key /etc/privkey.pem;

            location / {
                proxy_pass http://dns-over-https-server:8053;
            }
        }
    }

Note that this container has mounted the `fullchain.pem` and `privkey.pem` in `/etc`.
I'd recommend getting a valid SSL certificate to avoid invalid certificate issues.

The `docker-compose.yml` file has:

    version: '3.1'
    services:
        nginx:
            image: nginx:latest
            container_name: dns-over-https-server-nginx
            depends_on:
                - proxied_service
            volumes:
                - ./nginx.conf:/etc/nginx/nginx.conf:ro
                - ./fullchain.pem:/etc/fullchain.pem:ro
                - ./privkey.pem:/etc/privkey.pem:ro
            networks:
                dns-over-https-server-network:
            ports:
                - 54285:443
        proxied_service:
            build:
                context: /ansible_files/dns-over-https-server/dns-over-https-server
                dockerfile: Dockerfile
            container_name: dns-over-https-server
            expose:
                - 8053
            networks:
                dns-over-https-server-network:
                    aliases:
                        - dns-over-https-server
    networks:
        dns-over-https-server-network:

With that setup up and running, we can now start serving DNS over HTTPS!

# Testing the setup

The [Cloudflare post](https://blog.cloudflare.com/dns-encryption-explained/#deployment-of-dot-and-doh) I mentioned earlier has a section on how to setup DoH on your clients.

I tested the setup on latest Firefox (72.0.2) by going to `about:config`, then searched for `trr` (Trusted Recursive Resolver) and set `network.trr.mode = 2` and `network.trr.uri = https://dns.viktorbarzin.me/dns-query`.

There's 2 things to note about these 2 settings - firstly, the trr modes are explained in the [mozilla wiki](https://wiki.mozilla.org/Trusted_Recursive_Resolver#network.trr.mode).
Essentially `2` is _opportunistic_ which means that it will try to use DoH if possible, but if the server is unavailable it will fallback to standard DNS.
`3` is strict, which results in DNS errors if the server is unavailable for any reason (resistant to downgrading attacks) and `0` and `5` is not to use `trr` at all.

The simple test you can do to see that everything is working properly and you are not leaking your DNS queries is to set the mode to `2` and sniff you DNS traffic in Wireshark - it will be empty despite the fact that you are looking up domains when you browse the internet.
If you set the mode to `0` or `5`, you will instantly see all the DNS traffic generated by ads and what have you.

# Conclusion

I hope that you enjoyed this post as much as I enjoyed writing it.
You can share your thoughts in the comments section and share it with your friends to let them know about DNS-over-HTTPS!
