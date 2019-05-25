---
title: "Projects"
date: 2018-09-19T01:33:52+03:00
draft: false
---

This page is a brief showcase of some of the projects I've done myself.
Feel free to comment or contact me with any questions you have regarding any of them.

# Home Lab
That's one of my biggest ongoing solo projects.

My "home" lab is a bit unusual - comprises of 2 servers, linked with s simple SOHO router/switch.

Here's the in-s and out-s of the R310 machine:

<img style="height:500px" src="/images/projects-e95ca33a.png" />
<img style="width:74%" src="/images/projects-5b561189.png" />

And the T610 one:

<img style="width:50%" src="/images/projects-2f875e9d.png" />
<img style="width:100%" src="/images/projects-0446bfc5.png" />

You can see that the T610 machine has 2 CPUs - adding the 2nd one required adding thermal paste and hoping it will work since the entire setup isn't quite new and stuff could have broken down in various ways.

I have setup a virtual environment on both using [VMWare vSphere](https://www.vmware.com/products/vsphere.html) products which I use for educational purposes. For more info about the stuff I run on them check out my blogpost on that [here](/blog/03-a-walk-down-infrastructure-lane/).

# This website

Another interesting project was the creating of this website.
And I don't mean only writing the web stuff, because that's boring, I mean setting up a pseudo CI/CD to enhance my update experience and making changes to eat painless.

Read more about that endeavour [here](/blog/02-blog-a-blog/)

# Home made rubber ducky

I haven't blogged about it yet (though I'm in the middle of the post) but I made my own implementation of the infamous [Hak5's Rubber Ducky devices](https://shop.hak5.org/products/usb-rubber-ducky-deluxe).

For those who don't know what that is, that's a bad USB devices that behaves like a keyboard and sends arbitrary keystrokes to the machine it's plugged into.
[Southampton Uni](https://www.southampton.ac.uk/) gave me a programmable microprocessor for one of the modules so I utilized it in a Bad USB devices.

Here is a demo of the board being plugged into a Windows machine, opening a notepad and writing some text into it:

<img style="width:65%" src="/images/projects-lafortuna-rubber-ducky-demo.gif" />

If you are interested about the project, read more in the [github page](https://github.com/ViktorBarzin/LaFortunaRubberDucky).

# Lansync

This project is about making file sharing a bit easier when clients are connected to the same network.

Windows' SMB is sort of okay, for Windows-to-Windows file sharing, but sharing files between linux and windows boxes, or even between linux only boxes is a bit of a pain with NFS being such a mess.

Lansync is a wrapper around `rsync` and `ssh`.
It utilizes restrictions in *authorized_keys* file to allow peers to ssh only to receive files.
I've also included some easy ways to import the other party's public keys.

Here is a little sneak-peak of how syncing files is done:

<img src="/images/projects-lansync-demo.gif" />

It is published in the official Python packages repository ([PyPi](https://pypi.org)) so you could `pip install` it and test it out.

Read more about the project [here](https://pypi.org/project/lansync/).

# School website

Lastly, I decided to include that I rebuilt my high school website.
It's not much of a big deal but I'm proud to contribute to my schools IT department.

Considering the fact that the previous site was made in the early 2000s, I reckon this refurbishment was quite good to have.

You can have a look at the [new site here](https://spge-bg.com/) and compare it with what's left of the [old, flash-based one here](http://old.spge-bg.com/index.php).


# Appendix

I've got some other interesting projects that are worth checking out if you're into Python, web and automation, but I decided not to put them in here because they were mostly test projects of me poking around with technologies and frameworks.

If you are interested, do check [my github profile](https://github.com/ViktorBarzin) where you can find some other interesting stuff (including [my dotfiles](https://github.com/ViktorBarzin/dot_files)).
