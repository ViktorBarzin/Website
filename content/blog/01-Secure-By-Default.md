---
title: "01 Secure by default - Why you shouldn't disable Django's CSRF middleware"
date: 2018-09-08T13:44:49+01:00
draft: false
sitemap:
   priority: 0.3
---

# Brief intro
Recently I've been messing around with various **client-side** web attacks. I've noticed that most web devs' knowledge goes as far as the framework their using requires and that's it.
When asked **what is the purpose of a csrf token**, they would say - "Oh, it's something for security and if I don't put it, my forms don't work so it must be there."

If you find yourself having a similar answer, **keep on reading.**

#### Why Django?
I really like the Django framework - it is really simple to use, the learning curve is quite lean, the code is reasonably clean, it is very well documented and last but not least is quite [secure with almost no major security vulnerabilities](https://www.cvedetails.com/product/18211/Djangoproject-Django.html?vendor_id=10199).

So let's break it!

#### Why CSRF?
Well, like most devs, all I knew about the csrf token was that it is for security and it must be there. But that's not good enough for me.
I wanted to know why? What would happen if it wasn't there?

# What is Cross-Site Request Forgery (CSRF) and why should I care?

According to the [OWASP page](https://www.owasp.org/index.php/Cross-Site_Request_Forgery_(CSRF)), Cross-Site Request Forgery (CSRF) is an attack that forces an end user to execute unwanted actions on a web application in which they're currently authenticated.
The following picture illustrates the attack:

![](/images/01-Secure-By-Default-cf13175f.png)

This means that if your bank's website was vulnerable to CSRF, you could end up sending money to someone by just opening the wrong website.

Doesn't sound good...

# How does this problem get resolved?

CSRF is a **solved problem**. There are multiple ways to prevent CSRF in your site and some of the most common and easy to implement ones are:

- CSRF tokens
- Check standard headers to verify the request is same origin
- Multiple cookies for sensitive operations

If you'd like to have a deeper insight, I **strongly recommend** familiarizing yourself with the [OWASP CSRF prevention cheat sheet page](https://www.owasp.org/index.php/Cross-Site_Request_Forgery_(CSRF)_Prevention_Cheat_Sheet)

# Django's CSRF error message

If you've done any sort of Django development, at some point or another, surely you have seen the following error:

![](/images/01-Secure-By-Default-67265d50.png)

To be fair, the **first thing that I see most people do is copy the error message and slam it into google**.
If only they read the *Help* segment of the page...

The TL;DR is that there was an error with the *CSRF Token* sent to the backend.

**Getting this error is GOOD**. It means that our website **is protected againts CSRF attacks**.
Unfortunately what some people do to *solve this problem* is disable the CsrfMiddleware which *does* fix the forms issue but it opens the site to CSRF attacks.

Let's see what can this lead to.

# The target app
#### DISCLAIMER
The following demonstration is not recommended for use in any production site (obviously).
I'm too lazy to write a proper site that makes use of user sessions so I'm using a [sample site I found online](https://github.com/egorsmkv/simple-django-login-and-register).

It is a simple sort of "template" application the has registration, login, password reset functionalities and what not - perfect for simulating user sessions.
Here are some screenshots to get a better feel:

![](/images/01-Secure-By-Default-d8c5535b.png)

Once logged in, this is the "My profile" page:

![](/images/01-Secure-By-Default-5e8795b1.png)

# Let's shoot ourselves in the leg

All we need to make this perfectly secure app susceptible to CSRF attacks is to comment out the CsrfMiddleware in settings.py:

![](/images/01-Secure-By-Default-e8df810a.png)

(Disabling the CsrfMiddleware in **any** Django app, would make it vulnerable to CSRF attacks so if you care about your users **DON'T DO IT**)

Now that we have the CSRF protection out of the way we can create a malicious website that exploits it.

# The malicious website

![](/images/01-Secure-By-Default-3d1d8ffb.png)

Apart from the really disturbing image we have, the site seems to be totally legit, right?
Checking out the source of the page reveals its true intentions. Take your time to ponder on what is actually happening:

![](/images/01-Secure-By-Default-09a08e3b.png)

So this seamingly innocent page is doing way more than it seems initially - **it creates a hidden form and upon loading it submits it**.

Now you can see that the form action parameter is localhost since my django app is hosted at this address. Obviously in a real attack this would be the target website's address.

Now what's even more scary is the fact **the victim won't even realise that something has happened** - posting is done to a hidden iframe.

# Objective:
So what we are going to be doing is send a request to change the victim's email address.

# Let's go CSRF-ing then
Now this is how a legitimate request looks:

    POST /accounts/change/email/ HTTP/1.1
    Host: 127.0.0.10:8000
    User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:59.0) Gecko/20100101 Firefox/59.0
    Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
    Accept-Language: en-US,en;q=0.5
    Referer: http://127.0.0.10:8000/accounts/change/email/
    Content-Type: application/x-www-form-urlencoded
    Content-Length: 107
    Cookie: csrftoken=MFZLEFbXLWeJ6wOOehIBKNuaaTo4q7JhfvA1ST4pESPuaqG5J8dYjMcbJlQN7TL1; sessionid=e3rgs3j9lyax3cgtsxy6xrmuljoigmdp
    Connection: close
    Upgrade-Insecure-Requests: 1

    csrfmiddlewaretoken=as2NnTUPLCqyrj5SNjk6M0rGSWo5Cuw1FyNqbJayFkAHwBF5FRk4xpeTo9y2RKlm&email=notkek%40kek.com


The important stuff to look in the above request are:

- The *Referer* and the *Host* fields point to the **same host** - where the Django app is hosted.
- The *sessionid* cookie - this is what we are after. Stealing this cookie **allows an attacker to impersonate the owner**. As far as the application is concerned - **if you have the cookie, then you are the real one and only owner of that cookie**.
- The csrf token is truly randomly generated, but **not verified by the backend thus useless**.

Unfortunately, the **[Same origin policy](https://en.wikipedia.org/wiki/Same-origin_policy) protects the cookie** - it can only be accessed from the *http://127.0.0.10:8000* origin.

### Wouldn't it be neat if we could make the victim's browser send the request for us as if the victim has submitted the change email form?

Well guess what - **we can!** This is exactly what the hidden post form does in the malicious site. Let's have a second look at it to understand how exactly it tricks our browser to send the *sessionid* cookie.

```html
<form id="form" method="post" action="http://127.0.0.10:8000/accounts/change/email/" target="my_iframe" style="display:none">
    <input type="hidden" name="csrfmiddlewaretoken" value="mz4LR3Umv8hpB2Go4VLNmkRslgLIwdgc1zr7m7YYhiys8cGES7xZSOQVD0534fgt">
    <div class="alert alert-danger alert-dismissable alert-link" role="alert">
        <button class="close" type="button" data-dismiss="alert" aria-label="close">&#215;</button>
        Please enter another email.
    </div>
    <div class="form-group is-invalid">
        <label for="id_email">Email</label>
        <input type="email" name="email" value="attacker@attacker.com"
                    class="form-control is-invalid" placeholder="Email" title="" required id="id_email">
     <div class="invalid-feedback">Please enter another
         email.
     </div>
    </div>
    <input type="submit" class="btn btn-success">Change</button>
</form>
<iframe style="display:none" width="0" height="0" border="0" name="my_iframe" id="my_iframe"></iframe>
```

This form is a copy of the legitimate form from our Django app, with the only difference that the **fields have set values**.
(The csrfmiddlewaretoken field's value is randomly set. It can even be omitted and it won't make a difference)

We **post the form to the iframe** so that the page **does not refresh**. (tbh I could delete all the labels and css classes - it won't make any difference for the exploit).

#### Basically, we want the victim to change their email address to "attacker@attacker.com".

Now since I haven't set up the mailing service, I'll use the backend database for a point of reference to whether a reset token was generated.
Currently we have a single row containing the token used when registering the user:

![](/images/01-Secure-By-Default-66b257a1.png)

If the attack executes successfully, we would have a second generated token.

Unfortunately, if a the site is susceptible to CSRF, **the only thing a victim has to do is open a malicious website** which we can do by simply opening the site in another tab. (Note that the victim needs to be currently signed in (or have a valid sessionid cookie set) in the Django app in order to carry out the attack).

### Django tries really hard to protect us though
Django has another trick upon its sleeve - it sets the [X-Frame-Options](https://www.owasp.org/index.php/Clickjacking_Defense_Cheat_Sheet#Defending_with_X-Frame-Options_Response_Headers) header. This header tells the browser whether it should **render the site in an iframe**.

By setting this value to **SAMEORIGIN** the browser will render the website only if the iframe is on **the same origin as our main application**.

Unfortunately **the attack does not rely on rendering the website**. It will only try to render the response after the malicious payload was already sent(which could not happen anyway because of the SOP).

By inspecting the browser console we can see the *X-Frame-Options* in action.
When the victim opens the malicious website, the form is submitted resulting in an additional row in our *accounts_activation* tables as well as the X-Frame-Options error in the console:


![](/images/01-Secure-By-Default-c8de4b93.png)


![](/images/01-Secure-By-Default-817f8853.png)

Done. At this point the attacker just needs to open their email and confirm their new email. Now if the user who got compromised was the webmaster, well that's game over.

# Django framework is quite secure though

There is one caveat - as of [Django 2.1 the framework enforces the *SameSite* flag](https://docs.djangoproject.com/en/2.1/releases/2.1/#csrf) when setting cookies.
[The OWASP page](https://www.owasp.org/index.php/SameSite) is a must read on this topic.

The TL;DR is that **the *SameSite* cookie flag prevents the browser from sending the cookie along with cross-site requests**. **This basically solves CSRF for good !**

Have a look at the response from the Django app upon successful login:

![](/images/01-Secure-By-Default-11d76756.png)

The bad news? Well **[apart from Chrome and Opera, almost nobody utilizes this cookie](https://caniuse.com/#search=samesite)**, meaning that even if you set it, client browsers will not understand it.

The good news? Starting from **version 60** (released 9 May 2018), **firefox** will start enforcing the ***SameSite*** cookie.
However, when I was testing this (September 2018), the latest firefox package in the Ubuntu (18.04) repositories was 59.

Unless you've hit this wall before I reckon you haven't come across this cookie flag. Neither had I.

# Conclusion
Finding out about the *SameSite* cookie the *hard way* was quite fun - I spent quite some time in Burp and Wireshark pondering at requests and once I got it working, why the heck did it work only in firefox and not in chrome?...

I had a good fun researching this topic and I hope you learnt something reading thie blog post!

Till next time :P
