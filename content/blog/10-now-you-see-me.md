---
title: "10 Now you see me..."
date: 2019-05-18T14:24:22Z
draft: false
author: "Viktor Barzin"
description: "Setting up a home face recognition using OpenCV, raspberry pi and an IP camera. Not focusing on the face recognition part but on linking the python app with the camera which proved to be way more difficult."
tags: ["OpenCV", "python", "machine learning", "raspberry pi", "RTSP", "character devices", "block devices", "kernel modules", "mknod", "virtual camera", "ffmpeg", "vlc", "IP Camera", "v4l2", "video4linux2 loopback", "dummy device"]
firstImgUrl: "https://viktorbarzin.me/images/10-preview-resized.png"
---

# Pre-Intro
It's been a long time since my last blog post.

I've been quite busy recently, playing around with [Go](https://golang.org/),
[Haskell](https://www.haskell.org/), [Alex parser](https://www.haskell.org/alex/),
[Lex lexer](http://dinosaur.compilertools.net/), [home-made Rubber Duckies](https://shop.hak5.org/products/usb-rubber-ducky-deluxe) and plenty of other interesting stuff I may blog about at some point.

# Introduction

This post is about setting up a **home face recognition system** using an [IP Camera](https://www.amazon.co.uk/VSTARCAM-C7824WIP-Wireless-Camera-Network/dp/B00W17WWWE), OpenCV and a raspberry pi.

I **won't** focus on the face recognition part that much since the code I used **was not written by me** but instead was sourced from [this](https://www.pyimagesearch.com/2018/09/24/opencv-face-recognition/) **awesome** blog post that I **highly** recommend reading if you're into ML with python.

My post will be mostly about **glueing together the [OpenCV](https://opencv.org/) with my IP Camera** and making the latter read it's input from a [RTSP source](https://en.wikipedia.org/wiki/Real_Time_Streaming_Protocol) which [apperently works](https://stackoverflow.com/questions/20891936/rtsp-stream-and-opencv-python) if you have the right OpenCV (more on this later).

# Aim of project

In my home automation journey, after [setting up an audio system](/blog/07-raspberry-bluetooth-aux-setup/) next thing on the list is to control the music played in some way that's simple (basically making a home-made alexa thingy).

We spend a lot of time in our living room listening to music. Unfortunately I didn't simplify the audio system enough so that less tech-savvy people (Windows guys) could use it so I wondered - **wouldn't it be cool if every time someone enters the room, he would be recognized by a camera a play some music based on their taste?**

Hell yeah, sounds like a fun pre-exam project to do while procrastinating revision right?

# Doing reading on ML and face detection and recognition

Image processing has become quite a trending topic recently which is probably the reason why there is such an abundance of libraries for it.

Unfortunately (for me) most are written in C++ and people who know me know that **I'm not a fan of writing excessive amounts of code** for simple tasks (such as face detection lol).

Happily, there is python for the lazy people and what's even better is that most of the C++ libraries ([dlib](http://dlib.net/), [OpenCV](https://opencv.org/), etc) have their Python implementations. Yay!

Even though, I was genuinely interested in the topic so I did some reading on [using opencv with python](https://www.datacamp.com/community/tutorials/face-detection-python-opencv). This blog post was quite useful and shows the 101 of OpenCV with Python (loading images, drawing stuff onto images etc.).

The main source for my code was mentioned previously. Here's the [link](https://www.pyimagesearch.com/2018/09/24/opencv-face-recognition/) again because it's so great - do read the blog.
They describe how the code they've posted works and how to train the support vector machine for your face from new images.
As a bonus, they even added face recognition using a video source!

![](/images/opencv_face_reco_animation.gif)

# So... if the code is online what did I do exactly?

Getting the the code to work is the easy part.

<img style="width:35%" src="/images/viktor-face-rec.gif" />

That's fair and square, however, it's using my laptop camera.

Next thing is to make it read the **RTSP stream** which shouldn't be too hard right?

<img style="width:20%" src="/images/10-home-face-recognizer-eba99d00.png" />

# The issue

[According to StackOverflow](https://stackoverflow.com/questions/20891936/rtsp-stream-and-opencv-python) OpenCV *does* support RTSP, however, this was **not the case** for my setup.

It is possible that I've done something wrong so if anyone figures out how to make it work I'll get him a beer.
Upon running `recognize_video.py` it reaches the point of reading from the camera and after a little timeout it errors out:

![](/images/10-home-face-recognizer-95fd877e.png)

Yes, I've triple-checked the URI so the issue lies somewhere else.

### My build info that DOESN'T allow OpenCV to read from a RTSP source
Here's my setup info if anyone fancies a try to debug with me:
```
fedora 30 with latest updates
python --version -> python 3.7.3
cv2.__version__ -> 4.1.0

cv2.getBuildConfiguration() (Video I/O section) ->  

    DC1394:                      NO
    FFMPEG:                      YES
      avcodec:                   YES (58.47.106)
      avformat:                  YES (58.26.101)
      avutil:                    YES (56.26.100)
      swscale:                   YES (5.4.100)
      avresample:                NO
    GStreamer:                   NO
    v4l/v4l2:                    YES (linux/videodev2.h)

```

The reason might be because of the missing `GStreamer` option, even though I tried **compiling it manually** with that option included - **still didn't work**.

# Planning a workaround

I did look into a few libraries like [this one](https://pypi.org/project/rtsp/), [this one](https://github.com/jrosebr1/imutils) and a some others but **none of them** seemed to do the trick and read from the IP Cam.
Furthermore, I had my doubts that even if I managed to read a frame from it, it **would still go wrong when passing it to OpenCV** (image format, pixel format etc, FPS, etc.).

Before jumping on me saying I'm an idiot and got the URI wrong, that's not the case - adequate **tools like VLC, FFMpeg** and similar media playing software **did read the stream correctly**.

So the 2 options were either to **keep looking for a library** that manages to read the RTSP, or **do something hacky-er** - **I could read from a local web cam, so why not make the IP camera look like a local camera?** After all if powerful tools such as FFMpeg can read from it, surely they can do other magic as well.

# Workaround sketch

![](/images/10-home-face-recognizer-2a46e123.png)

First step is to make another `/dev/video` device so that I could stream to it.

To admit, my first attempt was **waaay off target**:

```bash
$ sudo touch /dev/video5
```

Sure, I could write to it, but it was **nowhere near a capture device** that I could read from afterwards.
I did try some bash-fu to make OpenCV read from a constantly changing file but couldn't manage to trick it to.

After a bit of google-ing on [character devices and block devices](https://www.quora.com/What-is-the-difference-between-character-and-block-device-drivers-in-UNIX), soon enough I arrived at the `mknod` command.

Turns out that `/dev/videoX` devices as well as some other such as `/dev/null`, `/dev/random` etc. are all [*character devices*](https://www.win.tue.nl/~aeb/linux/lk/lk-11.html).

The command to make one and let the kernel know it should treat it as a camera device is:
```Bash
$ sudo mknod test_cam c 81 0
```

The `c` tells it's a character device, `81` and `0` tell the kernel what modules to use for that specific device ([list of all device major minor numbers](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/Documentation/admin-guide/devices.txt) - 81 is char device, the 0 is `/dev/video0`).
Now running `file` on the new *file* confirms it is a character device:

```Bash
$ file test_cam
test_cam: character special (81/0)
```

**That's cool! Now I have a virtual camera as a file on my hard disk!**

Let's see how to write to it now.

# Fighting character devices

My initial idea was to basically do something similar to `sudo cat video.mp4 > test_cam` and afterwards read from `test_cam`.

Well surprise, surprise writing to character devices isn't that straightforward.
```Bash
[root@yuhu]: cat kek.mp4 > test_cam
cat: write error: Invalid argument
[root@yuhu]: echo 1 > test_cam
-bash: echo: write error: Invalid argument
```
They expect data in *characters* as opposed to *blocks* with which we are used to.
So **outputting a file into a character devices wouldn't make much sense** the way I was trying to do it.
[This](https://unix.stackexchange.com/questions/409874/how-to-write-to-a-character-special-device#answer-409879) answer explains it in **greater detail**.

I decided bothering with kernel IO would be too much for 1am so I started **looking elsewhere**.

### v4l2loopback module
At some point it started to get a bit depressing since **forwarding a RTSP video source to a local virtual camera isn't something people do every day** and therefore not much is online about how to go about it.

On the edge of despair (opening sites that I've already gone through) I found [v4l2loopback](https://github.com/umlaeute/v4l2loopback) module.
*Lord and saviour!*

This is a kernel module that enables us to creating virtual video devices that normal [video4linux2](https://en.wikipedia.org/wiki/Video4Linux) (v4l2) applications can read as capture device, but also allows writing to it which is what I was after!

Next step was to start writing to it.
# FFMPeg magic

The tool of choice for me was the infamous [ffmpeg](https://ffmpeg.org/) which is like a Swiss knife for media.
It can do all kind of crazy stuff like streaming the active X (Desktop) via network stream, or convert input/output media's pixel formats, RGB values and many many other funky stuff.

Having hundreds of options is a two edged sword though, especially for someone who doesn't understand in great detail how media is converted and all the different types of codecs and the differences between each.
I spent the next few hours trying to figure out all the correct input/output options to stream the IP cam to my virtual one.

The main issue was that **I didn't understand much** about how moving pictures (aka videos) are seen from the computers' point of view.
There are quite a few moving parts that I had to basically brute-force to make the thing work since **it either works or you see no picture whatsoever**. There is no other state.

By the end of the night this was the best output I ever got:

![](/images/10-home-face-recognizer-4c065cf3.png)

You can see some silhouettes here and there so there was light at the end of the tunnel.

# At last

Finally, on the following day by continuing to tweak parameters of *ffmpeg* I finally had success reading the stream with the correct settings. Running the face recognition python app afterwards was as simple as changing the id it uses for the camera input.

<img style="width:40%" src="/images/10-face-recog-working-ip-cam.jpg" />

#### This is me taking a photo with my phone of my laptop screen which is showing the output of the OpenCV face recognition app which gets its input from the virtual camera device which is getting its input from the video4linux loopback module which is being written to by ffmpeg's RTSP input.

That ^^ described quite well what the goal result was.

Now **I have a programmatic way to do whatever I want once a face is detected** and even when a specific person is recognized.

The magic steps that made all this possible were:

1. Firstly, install the `v4l2loopback` module and load it - it will create the virtual camera devices.
2. Stream to the virtual camera (in my case `/dev/video2`) using ffmpeg:

```Bash
$ ffmpeg -i rtsp://USER:PASS@CAMERA_IP:10554/udp/av0_0 -f v4l2 -pix_fmt yuv420p /dev/video2
```
Finally change the source code of the application to use camera id *2* instead of *0* (default) and it magically works!

![](/images/10-home-face-recognizer-0c438cd8.png)

# Upcoming imporvements

Next step is to put all this setup on the raspberry pi and run some scripts based on who the detected person is.
Still have to gather all my housemates' consent but you know, people are easier to handle with than computers :D
