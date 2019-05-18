---
title: "10 Quack like a keyoard"
date: 2019-04-21T14:24:22Z
draft: true
author: "Viktor Barzin"
description: ""
tags: []
firstImgUrl: "https://viktorbarzin.me/"
draft: true
---

# Pre-Intro

Woah, it's been a long time since my last blog post.

I've been quite busy recently, playing around with [Go](https://golang.org/),
[Haskell](https://www.haskell.org/), [Alex parser](https://www.haskell.org/alex/),
[Lex lexer](http://dinosaur.compilertools.net/) and plenty of other interesting stuff I may blog about at some point.

# Introduction

This blog post is about my latest (ongoing) project.

I utilized my Atmel (**AT90USB1286**) microcontroller to create my own [Rubber Ducky](https://shop.hak5.org/products/usb-rubber-ducky-deluxe).

This journey included understanding lots of C code, modifying it writing some Python to parse the DuckyScript language
and finally producing a *hex* file ready to be flashed on the microcontroller.
You can find the project [here](https://github.com/ViktorBarzin/LaFortunaRubberDucky)

# Available hardware

So the hardware I have at my disposal is the LaFortuna board ([schematics](https://github.com/ViktorBarzin/LaFortunaRubberDucky/blob/master/lafortuna-schem.pdf)) that is equipped with an [Atmel AT90USB1286](https://www.microchip.com/wwwproducts/en/AT90USB1286) microcontroller.

The board has plenty of neat stuff, one of which is a USB controller that I utilized thoroughly.

# First steps

First thing to do was to look at the data sheet to get an idea of how the USB controller works (p. 241).

Though it was useful to learn how the USB controller works, I wouldn't say it was particularly useful to the project.
The main point I got was not to implement all the USB protocol manually as it seems way too overkill.

Manually setting all the bits and registers to implement the USB protocol seemed unfeasible so I looked for alternatives.
That's when I found some [demo C code for implementing a USB keyboard](https://www.microchip.com/wwwAppNotes/AppNotes.aspx?appnote=en591888) - Perfect! That's exactly what I needed.

# However

I had high hopes for the demo code, however, it turned out to be way more complicated than what I expected -
it implements not only the USB protocol and the keyboard interface, but also a [real-time scheduler](http://www.cs.ucr.edu/~vahid/rios/) that does way more than what I needed.

# Understanding the demo code

I have to admit, it took me longer that I expected to understand the demo code.
Deep down in the zip hierarchy, there is a file called `keyboard_task.c`

Well, you can tell that that file contains the keyboard task run by the scheduler.
I recommend reading through to get an idea of what's doing what.
