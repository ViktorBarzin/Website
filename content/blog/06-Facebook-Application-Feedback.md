---
author: "Viktor Barzin"
title: "06 In the big 4! - Facebook Application Experience"
date: 2018-11-18T19:31:50Z
draft: false
sitemap:
  priority: 0.3
firstImgUrl: "/images/06-Facebook-Application-Feedback-5fbb016d.png"
description: "In this blogpost I share my experience from my application process with Facebook which resulted with an offer and some tips and tricks on what I believe made me a successful candidate."
tags:
  [
    "Facebook",
    "Production Engineer Internship",
    "London",
    "2019",
    "CV",
    "Online test",
    "technical interview",
    "Coding interview",
    "Systems interview",
    "Big O complexity",
    "Clean code",
    "Uncle Bob",
    "Cracking the coding interview",
    "Data structures and algorithms",
  ]
---

# Introduction

It's been a while since my last post.
This was due to the fact I was preparing for my interview for [**Facebook's 2019 Production Engineering Internship Program**](https://www.facebook.com/careers/jobs/513843009077435/) as well as doing some uni related work which is not really worth blogging about.

### Anyway, the good news is that I got that offer from Facebook!

![](/images/06-Facebook-Application-Feedback-5fbb016d.png)

I decided this post to be about my overall experience so if you're looking for technical post, come back next week.

I'll share what, from my point of view, made me a successful candidate.

#### Note I will not share any of the questions I was asked due to the fact I respect the people who came up with these questions and the time they've spent.

# First things first - get that CV right

Right, so obviously to get to the interview phase, you'll need a _rather shiny_ CV to impress the recruiters with.

[Here](/images/06-cv.pdf) you can find my CV to get some inspiration.

Now **I am not by any means a CV expert** or something but here are **my thoughts and views on what a good CV should have.**

What's more, there are plenty of guides and tutorials on how to make a good CV so I won't turn this post into one.

Just spend some time choosing an appropriate and **good looking template** and then just fill in!
Something quite important I see people don't get is the way you **word your experience section** - you should **use active verbs** like _led_, _managed_, _was responsible for_... - instead of passive ones.

Now you can, and probably should, have a _Skills_ section where you list what your skills are but what I feel attracts more attention is a _Personal Projects_ section.
**I can't stress enough the importance of having projects that are not related to school or university.**
**The more, the better** but also **the more completed the better - quality over quantity!**

There was this youtube video that described precisely this - it went on with the story of 2 characters one of which had many many **incomplete projects and couldn't really use any of the to put in their CV** as none were complete, whereas the other character **didn't have as many** projects, but the few he had were **all completed, well documented and tested which is the better option**.

I had an issue with the aforementioned section since I have several projects I want to list but I lack space.
What did I do? - **I setup my own site** where I could put a [/projects](/projects) section which could have **unlimited space!**

Then what's left is to **put a link to the website's project page** which turns the situation in a a **win-win** - I both show off my projects and also show that **I've dedicated some time into setting up** my own website.
Furthermore, I feel like it is a big plus if you spend that extra time **to setup a HTTPS version** - just for the sake of it.
[You can check out how I did that here](/blog/02-blog-a-blog/).

# Step 2 - Online test

For the [**Production Engineering Internship**](https://www.facebook.com/careers/jobs/513843009077435/) I had to do an **online test** before getting to the one-to-one interview.

The online test was more of a **sanity check** on simple linux and unix commands so if you _use_ linux on a daily basis (I mean **the terminal part**, not the gui stuff) and occasionally write simple bash scripts you won't have any trouble passing this stage.

![](/images/06-Facebook-Application-Feedback-f34e0ea6.png)

# The 1-to-1 Interviews

I've spoken to some recruiting people at Facebook and I've been told that regardless of the position you apply for, **surely there will a coding interview**.

The Production Engineer Intern role includes two **45 minute technical interviews**

- A coding interview
- A systems interview

## The Coding Interview

Recently, I've focused more on the [OPS](https://en.wikipedia.org/wiki/Information_technology_operations)-y side of things and, well you know, **coding interviews at tech giants are supposed to be very hard**.

The main resource I used to prepare myself for this interview was **The Bible of coding interview books** - [**Cracking the Coding Interview**](https://www.amazon.co.uk/Cracking-Coding-Interview-6th-Programming/dp/0984782850).
I highly recommend buying (or Google-fu-ing for that matter) this book. It contains **plenty of useful resources along with tips and tricks on how to prepare and ace the coding interview.**
I also did some preparation on [Hackerrank](https://www.hackerrank.com/) but I felt I spent more time on **fixing edge cases rather than thinking of solutions** so I quit that.

The coding interview **was not as hard as I expected**. I reckon software engineers undergo a way more difficult one. If you are preparing for such an interview, you should refresh your **data analytic skills**.
Normal every day stuff that Production engineers code - file operations, data parsing, some data analysis and what not.

During the interview, I find it is really important to **think out loud** and to say **what are the tradeoffs you make** when making a decision - eg. why use a set instead of a list? Oh you are doing multiple lookups, perhaps you should change the list to a dictionary?
Saying these things out loud makes the interviewer aware of your knowledge on data structure operations complexity.

What's more, **do ask questions!** Ask about **input data size**, ask about **error handling**, ask things you are not sure about - **don't guess!**

Finally, maintaining **good code quality is always important** so put a comment whenever you write something not quite clear and you don't have time to refactor but still **make your interviewer aware that you know what you've written could be improved** and **ask** whether you should spend time on improving it or not.

## The Systems Interview

I was way more confident for the systems interview that I was for the coding one.

Now that's a tricky one. Unless you've gone through some **system administration courses** or tinkered around with **low-level kernel-y like stuff you'll probably struggle here**.

To be successful at this interview you'll need **intermidiate understanding of linux internals and the linux philosophy** - all the way from **booting**, through **process management** and **system calls** to **shells and user management**.
There are plenty of resources online but in my opinion what was **most useful to me was my own experience** - For example some while ago I set up a [PXE](https://en.wikipedia.org/wiki/Preboot_Execution_Environment) server (I might write a post about that at some point) which thought me a lot about the **boot process** in linux.
If you do follow my blog, I did a [nice write-up](/blog/03-a-walk-down-infrastructure-lane/) on my home lab which may give you an idea of what I've been up to recently. **All the stuff I've mentioned there was helpful**.

Finally, having some knowledge about **system calls will not hurt your chances** at all - knowing the difference between `fork`, `exec` and `clone` family of system calls for instance. ;)

But, **where is the networking part?**

Well it turned out that Facebook, similarly to some other big tech companies tend to avoid asking quiestions about networking since **even experienced candidates are likely to underperform on these types of questions** even though I would have probably enjoyed that part.

# TL;DR; tips & tricks

Know your **Computer Science primitives** -

- [Big O complexity](https://en.wikipedia.org/wiki/Big_O_notation)
- [Data structures and their operations complexities](http://bigocheatsheet.com/) (more importantly - know when to pick what)
- Find a language **you love coding in** - for me this is [Python](https://www.python.org/) - and **show off some advanced knowledge** - plug in some **functional programming** - put those lambdas and high order functions where appropriate.

Go checkout [Uncle Bob's](https://www.youtube.com/watch?v=QedpQjxBPMA&list=PLlu0CT-JnSasQzGrGzddSczJQQU7295D2) presentaions on clean code and how to write high quality code - **I strongly recommend watching these and any other of Uncle Bob's presentations.**

Something I found really useful from [Cracking the Coding Interview book](https://www.amazon.co.uk/Cracking-Coding-Interview-6th-Programming/dp/0984782850) was this particular approach to solving difficult coding problems:

1. Firstly, come up with a naive, even **brute-force**, solution.
2. Try to **improve on that** - solve a couple of **more complex examples by hand** and you'll notice how your brain does optimizations for you.
3. **Reverse engineer these optimizations** and find out **why and how your brain does them**. Then turn these thoughts into code.

This strategy is described, of course way better, in the book and **I highly recommend** checking it out.

Regarding the systems part, the only way of learning these stuff is by **doing them** - pick that old PC at home your not using, **setup virtualization** on it, **run some VMs**, configure **any services that come up to your mind**, tinker with them thoroughly, **break them, fix them** - that's how you'll **understand and learn them for good**.

Doing the last one also fits _quite neatly in your CV as extracurricular projects_ as well so it's again a **win-win.**

Of course, if you are a **book-lover**, _there are tons of great books on linux/unix system administration_ but that's only **half of the story** - **none of this knowledge matters unless you can put it in practice**.

In general, if you are **curious about technology and stubborn enough - you'll succeed**.

If you do have any specific questions do feel free to reach out - I've put enough ways you can contact me on this site already :-)
