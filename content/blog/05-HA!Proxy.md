---
title: "05 HA!Proxy - Discovering the wonders of proxying and load balancing"
date: 2018-10-14T14:04:13+01:00
draft: false
sitemap:
   priority: 0.3
---

# Introduction
In this week's post I'll share my experince with **[HAProxy](http://www.haproxy.org/)** - a high performance TCP/HTTP **load balancer**
#### Disclaimer: There will be nothing that you can't read in the [haproxy options manual](https://cbonte.github.io/haproxy-dconv/1.7/configuration.html) apart from my thoughts.
Still, if you're interested in my experience configuring this application for my setup keep on reading.

This post will be shorter than usual because **I am a bit low on time** since **I'm preparing for an important interview**.
**I don't feel like posting coding exercises** due to the fact that **there's plenty of material on the web for all of them** and I do not consider myself as an *"algo guru"* or something.

#### In the next couple of weeks I'll probably not post anything because of the reason above.

# Let's get started

In the [end of last week's post](blog/04-down-the-rabbit-hole/#time-to-haproxy) I ended up **using HAProxy to proxy connections made to my router at home to my container hosting the website**.
I went through a lot of hassle but in the end I was able to **log the original client's IP address** which I passed as a header from HAProxy to my web server.

I will not go through that again. If you are curiuos feel free to read [the whole story](blog/04-down-the-rabbit-hole/#time-to-haproxy).

This time I'll explain some of the options which are pretty well described in the documentation and my experience of using the software.


### Some prerequisites

If you're new to load balancing, **I'd strongly recommend reading [this blog on load balancing concepts in the context of HAProxy](https://www.digitalocean.com/community/tutorials/an-introduction-to-haproxy-and-load-balancing-concepts)** before reading on.

# Hiding behind 1 public address

If you've read [my post where I explained my network](/blog/03-a-walk-down-infrastructure-lane/) you know that I'm *a bit low on public ip addresses*.

If I had a single web service I wanted to be public that's fine - I can just let it slide through port 80 or 443 and no issues whatsoever.
However, recently **I've been setting up more and more web services** and I had to get creative to access them - **let's put that on port 8000, this other one on port 8080 etc**.

#### Unfortunately, there are 2 major issues with this strategy:

1. It is ***really inconvenient*** to have to remember what service on what port is
2. I started running out of traditional "web"-related ports and **running a web server on port 4443 is a bit odd, right?**

# HAProxy to the rescue

It turned out that appart from adding headers to requests, **HAProxy is able to check for both presence of headers, as well as their value which is interesting**.

This is what an ordinary get request to `www.google.com` looks like:

    GET / HTTP/1.1
    Host: www.google.com
    User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:59.0) Gecko/20100101 Firefox/59.0
    Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
    Accept-Language: en-US,en;q=0.5
    Connection: close
    Upgrade-Insecure-Requests: 1

This is what a request to `mail.google.com` looks like:

    GET / HTTP/1.1
    Host: mail.google.com
    User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:59.0) Gecko/20100101 Firefox/59.0
    Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
    Accept-Language: en-US,en;q=0.5
    Upgrade-Insecure-Requests: 1
    Connection: close

Notice how the `Host` header changes its value.

#### Well what if I setup multiple (sub)domains to point to the same ip address and then have something route requests based on the `Host` header?

##### Note that the domain I'm doing this is `samitor.com` as I consider is for more *proffesional*. The actual domain does not matter here

Here is how my dns zone looks like:

![](/images/05-HA!Proxy-b5202366.png)

Notice the **multiple CNAME records that point to the same address** which in my case is `213.191.184.70`.
**On layer 4 this wouldn't make much sense**, but **as we go up to layer 7, it makes all the difference.**

#### So what I eventually want to achieve is have a service that listens on ports 80 and 443 for HTTP requests. When one is received, I want it to inspect the `Host` header and route the request to the according backend service.

This is how this requirements look like in HAProxy config's terms:

    frontend http_proxy
    	bind 213.191.184.70:80             # Public address to bind to
    	mode http                          # We are routing http here
    	option forwardfor                  # Add Forward-For header to tell the backend server there is a proxy
    	option http-server-close
    	reqadd X-Forwared-Proto:\ http
    	reqadd X-Forwarded-Port:\ 80

    	acl host_website hdr(host) -i viktorbarzin.me      # ACL that matches requests with Host header = viktorbarzin.me
    	acl host_kms_info hdr(host) -i kms.samitor.com     # ACL that matches requests with Host header = kms.samitor.com
    	acl host_privatebin hdr(host) -i pb.samitor.com    # ACL that matches requests with Host header = pb.samitor.com

    	use_backend docker_gateway_http if host_website    # If host is viktorbarzin.me, then use backend that serves my site.
    	use_backend kms_info_http if host_kms_info         # If host is kms.samitor.com - use the backend that serves this
    	use_backend privatebin_http if host_privatebin     # --//--

    # The below logic is the same as the one above. The difference is adding the ssl settings.
    frontend https_proxy

    	# Bind to port 81 and 444 on all interfaces (0.0.0.0)
    	bind 213.191.184.70:443 ssl crt /root/le/live/viktorbarzin.me/viktorbarzin.me.pem

    	# We're proxying HTTP here...
    	mode http
    	option forwardfor
    	option http-server-close
    	reqadd X-Forwarded-Proto:\ https
    	reqadd X-Forwarded-Port:\ 443

    	acl host_website hdr(host) -i viktorbarzin.me
    	use_backend docker_gateway_https if host_website

Once an Access Control List (ACL) is matched, traffic is routed to the specified backend server. This is how they are configured:

    backend docker_gateway_http # Specify backend name
        mode http # We are routing http here
        option httpclose
        option forwardfor
        server node1 10.2.0.1:80 # Route traffic to this host at this port

    backend docker_gateway_https
        mode http
        option httpclose
        option forwardfor
        server node1 10.2.0.1:443 ssl verify none

    backend kms_info_http
        mode http
        option httpclose
        option forwardfor
        server node1 10.2.0.3:80

    backend privatebin_http
        mode http
        option httpclose
        option forwardfor
        server node1 10.2.0.1:8000

**The configuration is pretty clear and intuitive** and it doesn't take any debugging to make it work.
It *just works*.

So opening the domains, **despite they resolve to the same ip address, a different service is loaded:**

<center> ![](/images/05-HA!Proxy-1d379d4b.png) </center>

![](/images/05-HA!Proxy-64c65ce4.png)

<center> ![](/images/05-HA!Proxy-b6df7cfe.png) </center>

![](/images/05-HA!Proxy-a54ef1d3.png)

And of course accessing [viktorbarzin.me](https://viktorbarzin.me) routes to the website you're on right now.

#### If you try another domain that resolves to this IP address, HAProxy will not be able to find a matching ACL therefore will return an error:

![](/images/05-HA!Proxy-4560f875.png)


# Conclusion

In this post I showed you how I have implemented and how I use HAProxy in my home environment.

You saw how you could run potentially infinite amount of services all seemingly listening on the same IP address at the same port which may not be obvious if you have only your *Networking 101* knowledge.

Here is a list of some useful sources I went through when I was setting up HAProxy:

- [Digital Ocean article on introduction to load-balancing concepts and haproxy](https://www.digitalocean.com/community/tutorials/an-introduction-to-haproxy-and-load-balancing-concepts)
- [HAProxy - routing based on domain name](https://seanmcgary.com/posts/haproxy---route-by-domain-name/)
- [HAProxy configuration options](http://cbonte.github.io/haproxy-dconv/configuration-1.7.html#7)
- [Setting up Access Control Lists(ACL) in haproxy - HAProxy Documentation](https://www.haproxy.com/documentation/aloha/8-5/traffic-management/lb-layer7/acls/)
