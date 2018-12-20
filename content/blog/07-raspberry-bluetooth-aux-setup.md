---
title: "07 Going musical - Setting up an improvised home audio system"
date: 2018-12-20T13:01:54Z
draft: false
---

# Introduction

Some time ago myself and a [friend of mine](https://www.facebook.com/atanunq/) won these awesome bluetooth [Logitech speakers](https://www.logitech.com/en-us/product/z537-bluetooth-speaker-system)

![](/images/07-raspberry-bluetooth-aux-setup-6c366282.png)

The sound is quite decent, unfortunately connecting to both at the same time is a bit tricky and
without having an external bluetooth adapter one could not easily play the same music on both.

In this blog post I'll show you how with a raspberry pi, some clever thinking and a fair amount of patience I managed to stream music simultaneously onto both.

# What's the issue?
The thing with bluetooth is that if you have 1 adapter - you can connect to 1 receiver and that's it.
There isn't much room for doing hacky stuff like connecting to multiple receivers with 1 adapter.

As you can imagine, playing music on 2 speakers is always better than playing it on 1 only so measures had to be taken.

# What options are there?
The speakers also have an AUX input. Add a [simple aux splitter](https://www.amazon.com/s/ref=nb_sb_noss_2?url=search-alias%3Daps&field-keywords=aux+splitter) and it's problem solved at that point.
However, it is quite inconvenient to walk around the room with an aux cable hanging from whatever device I'm using to stream music from so I had to come up with something cleverer.

# Perhaps make use of the raspberry pi?
The next thing that came to my mind was to use my flatmate's raspberry pi for a media server to which I could stream music.
There's plenty of media server software out there for raspberries so not after long I had a [Volumio](https://volumio.org/) instance up and running.

It was somewhat ok - the web interface is a misbehaves rather often (perhaps because of the angular frontend) but once you get it running its alright.
There are plugins available for Youtube, Spotify and what not so you can listen music from a variety of sources.

# Raspberry + Volumio + AUX splitter - the solution?
Unfortunately the implementation is quite hacky so it is not as usable as I want it to be.
Say I wanted to play some online radio that wasn't in Volumio's list or perhaps play a youtube playlist (yes Volumio allows playing videos 1 by 1 only) - with Volumio I am somewhat limited.

#### What I'd like is to be able to play media from whatever source to the raspberry and it would then forward it to its aux output.
Simple right?

Volumio was not the solution for me. I tried other media servers such as [Kodi](https://kodi.tv/) but it wasn't what I wanted either.

# Meh, let's replace the Volumio part
So I had to go closer to the metal. I opened the specs of the raspberry and it turned out that it has a bluetooth adapter as well!

![](/images/07-raspberry-bluetooth-aux-setup-3ecd27a1.png)

Perhaps I could set it up as a bluetooth speaker that I would pair with, stream music to it and then it would forward the music to its aux output.
This would work regardless of the media source I use!

# Raspberry pi as a bluetooth speaker

I came across this promising [guide](https://www.raspberrypi.org/forums/viewtopic.php?t=68779
) that began with the words:

*"I spent a lot of time to get information from different sources and use a part of each to make my raspberry doing what I wanted. I didn't find any complete tutorial to do it and I think it can be interesting for people who want to have the same use of their raspberry PIs."*

This was exactly what I needed. At that point I had my fingers crossed that it's descriptive enough and fairly recent.

I started following the guide, however, with each and every step the instructions started mismatching reality more and more - some config files were located elsewhere, some values varied, others were completely missing...

Some of the configs were changed quite some time ago so I wasn't quite surprised when I saw the date when the article was published:

![](/images/07-raspberry-bluetooth-aux-setup-0b969532.png)

While troubleshooting issue after issue I came across this [useful topic](https://www.raspberrypi.org/forums/viewtopic.php?t=133961) that had some pretty useful commands on how to pair with a device from the `bluetoothctl` cli:

    power on
    discoverable on
    agent on
    default-agent

These commands enable the bluetooth on the raspberry and make it discoverable by other devices.
Basically the 101 on linux cli bluetooth :D
Once my device tries to pair with the raspberry, the casual bluetooth pairing process occurs so nothing unusual there.

## Pi would not find its bluetooth adapter
However, I had some issues starting the bluetooth - the raspberry kept denying it had a bluetooth adapter. I restarted the *bluetooth systemd service*, restarted the pi several times and what not and it just kept refusing to admit it has a bluetooth adapter available.

Since it didn't have any important data on it and because it had some nasty dependency issues with apt I decided to reflash it a brand new [raspbian](https://www.raspberrypi.org/downloads/raspbian/) image.
If you know me personally, you know that I'm not much of a GUI user so I just installed the plain terminal version of raspbian without a desktop environment.

What was quite weird was even though I flashed the most recent raspbian image, the raspberry continued to refuse it had a bluetooth adapter... WTF? I double checked the model and surely it had one.

There was something more to this...

I went deeper to figure out what's going on. After a few hours of debugging I finally found the root cause - it turned out that the [D-BUS message bus daemon](https://dbus.freedesktop.org/doc/dbus-daemon.1.html) would not autostart without having a `$DISPLAY` set for X11:

 ![](/images/07-raspberry-bluetooth-aux-setup-5bf6ecb0.png)

#### TL;DR - bluetooth daemon does not start because it cannot communicate to dbus daemon which does not start because it is missing a desktop environment...

 ![](/images/07-raspberry-bluetooth-aux-setup-53ee2e8e.png)

Next thing I do:

{{< highlight bash >}}
    sudo apt install lxde
{{< / highlight >}}

Having a desktop environment fixed all the dbus issues.
Suddenly `hciconfig -a` started showing the bluetooth adapter as expected!

# Back to the plan
While debugging bluetooth issues, I came across this lovely [gist](https://gist.github.com/oleq/24e09112b07464acbda1) that described the entire process and summarised it neatly:

    Audio source (i.e. smartphone)
                 |
                 v
    (((  Bluetooth Channel  )))
                 |
                 v
            Raspberry PI
                 |
                 v
        USB Audio Interface
                 |
                 v
              Speakers

Too bad I saw it when I had done most of it.

I did some little tweaks to the quality of the sound in the pulseaudio config which I may upload at some point.
Once everything was working, pulseaudio started seeing the bluez (bluetooth) audio source:

![](/images/07-raspberry-bluetooth-aux-setup-8cdd5278.png)

#### After pairing, the pulseaudio client on my machine managed to see the pulseaudio on the raspberry and voala - the speakers started playing music in sync!

![](/images/07-raspberry-bluetooth-aux-setup-18ce4bce.png)

# Automate the world
There are 2 things to automate before calling it a day.
Firstly, I had to make sure it is persistent - rebooting the raspberry is not uncommon at all and I want to make sure I'll skip the struggle of pairing again.

Secondly, the pairing process is a quite inconvenient - to pair, one has to ssh into the pi, start bluetoothctl, run the commands I mentioned above (of course find them from somewhere) and keep fingers crossed that it'll work - exactly the opposite as how I imagine it.
My flatmates that are studying computer science are afraid to do these steps to connect let alone anyone else...

# Let's see if it's persistent - reboot the pi
As expected, it is not :/ - after the pi booted, I could not connect back to it to start playing music.
For some odd reason pulseaudio would not load its bluetooth module, hence I could not pair to it.

After some googling, I found that I could specify which modules are loaded when pulseaudio starts. So the magic edit lives in `/etc/pulse/default.pa`:

![](/images/07-raspberry-bluetooth-aux-setup-2f2fa9a2.png)

The `load-module` line has to be uncommented.

This sort of fixed the issue, but it still would make trouble.
I still haven't figured out why, but when I list the media sources with `pactl list sources short`, pulseaudio does something and initializes the bluetooth module. Success!

Now let's add this command to run on startup. One way of doing it is to create a [systemd service](https://www.freedesktop.org/software/systemd/man/systemd.service.html) and run it once on `graphical.target` and/or `reboot.target`.

But me, being lazy, I know that I can run scripts by dropping a line in `/etc/rc.local`.
Now this may not be the best way of doing it, but if it works - it ain't stupid.

I popped that in, rebooted the pi but alas it failed to initialize the module... The most annoying part is that when I ssh into it and manually run the command, it works and now I can connect to the pi.

It took me a while to figure out that apparently pulseaudio does not start as root but as the user 'pi':

![](/images/07-raspberry-bluetooth-aux-setup-1704d2ca.png)

The 'aha' moment is that rc.local runs, but once it tries to execute `pactl` as root but it failes and because of the `#/bin/sh -e` at the beginning (the '-e') it exits once that command fails and doesn't run anything else.
So what I had to do in rc.local was run this command as 'pi' and it would all work!

`su pi -c 'pactl list sources short`

Bam!

Unfortunately, while debugging this, I made a little mess by creating a few `.service` files to run rc.local. Now the odd part is that if I delete them, rc.local does not get executed anymore but w/e :D
It doesn't hurt to have a service running rc.local for you (this might be how it is run anyway).

Here is how a service file looks like:
{{< highlight bash >}}
    # rc-local.service
    [Unit]
    Description=Start rc.local

    [Service]
    ExecStart=/etc/rc.local

    [Install]
    WantedBy=multi-user.target reboot.target

{{< / highlight >}}

At last I got pulseaudio to initialize the bluetooth module properly so even if the pi gets rebooted, I would still be able to connect to it afterwards!

# The pairing part

Now the seemingly easier part. You know when you have a bluetooth device you would normally have a 'pairing button' which you would press when you want to pair to the device.
Well the pi does not have one so I had to come up with some sort of replacement for it.

The first thing that came to my mind was - well let's put a web endpoint that when accessed would run a pairing script that would take care of the pairing process. That shouldn't be that hard right?

Wrong! Let me show you what went wrong.

I started with the easiest part - the web endpoint:

{{< highlight bash >}}
sudo apt install python3-pip && pip3 install flask
{{< / highlight>}}

This is what my python web server looks like:

{{< highlight python >}}
# webserver.py
import os

from flask import Flask
app = Flask(__name__)

@app.route("/")
def index():
        # Pait with device
        os.system("/home/pi/start_pairing.sh")
        # Add device to trusted devices
        cmd = "echo 'trust '$(echo 'paired-devices' | bluetoothctl 2>/dev/null | grep paired-devices -A 1 | awk '{print $2}'| tail -n 1) | bluetoothctl"
        os.system(cmd)
        return "Started pairing"
{{< / highlight >}}

The aim of this server is to run the pairing script upon receiving a request.
It is the "button" you would normally press on a regular bluetooth device.

# You didn't *expect* that
The pairing script is a simple [expect](https://linux.die.net/man/1/expect) script that handles the pairing procedure within the [bluetoothctl](http://www.linux-magazine.com/Issues/2017/197/Command-Line-bluetoothctl) cli.
That's what it's like:

{{< highlight bash >}}
#!/usr/bin/expect -f
# start_pairing.sh

set prompt "#"
set timeout 120

spawn bluetoothctl
expect -re "$prompt"
send "discoverable on\r"
sleep 1
send "agent on\r"
sleep 1
send "default-agent\r"
sleep 1
expect "Default agent request successful*"
#expect -re "$prompt"
expect "Request confirmation\r"
expect "*Confirm passkey*"
sleep 5
send "yes\r"
sleep 3
#expect "Authorize service\r\n"
expect "yes/no*"
sleep 5
send "yes\r"
sleep 1
send "quit\r"

{{< / highlight >}}

The script is quite hacky with all the *sleeps* and what not but I reckon that's how expect scripts look like anyway and, oh well, *it works on my machine ™*.
If you've written similar scripts you know what a pain they are, and the bluetoothctl cli doesn't make it any easier with all the color encodings as well...

One thing I found very useful while writing the script is the debug option - run your script with `expect -d script.sh`.
The good thing is there is plenty of resources online for writing expect scripts so I won't go into details in here.
Most issues I had were using the '\*' in inappropriate places and that caused me some headaches, but apart from that it's quite straightforward.

# Trust issues...
A fun thing I learned at this point was that *pairing* with a device does not mean that you *trust* this device.
So once you pair, you need to add yourself to the trusted devices list on both sides.
Otherwise each time you connect to the pi, you would need to open bluetoothctl and confirm the identity of the device.

Now this part is make it or break it kind of thing - I just got that hacky expect script working and now I had to change it to automatically trust the last device that paired with it.

![](/images/07-raspberry-bluetooth-aux-setup-c7b7560b.png)

That was definitely a no-no so I had to find another way.
Wouldn't it be cool if I could get the mac address of your bluetooth adapter when you connect to the flask server, and then pass it on as an argument to some script that would add it to the trusted devices list?

I was really surprised when I found out that it is not possible to get that mac address via javascript :O
Then I had a little 'is-this-even-possible' moment in my head but after some more brainstorming I noticed that the `paired-devices` command in the bluetoothctl cli had a rather predictable behavior - the last paired device would always appear on top of the list - bingo!

The bash one-liner below (and in `webserver.py`) gets the last paired device and adds it to the trusted devices list with the `trust AA:BB:CC:DD:EE:FF` command.  
{{< highlight bash >}}
echo 'trust '$(echo 'paired-devices' | bluetoothctl 2>/dev/null | grep paired-devices -A 1 | awk '{print $2}'| tail -n 1) | bluetoothctl
{{< / highlight >}}

Currently, the entire thing works alright-ish. The main issue is that it is quite inconsistent meaning that if it doesn't work the first time, you should retry and it might work the second time.
Unfortunately, I couldn't spend more time fixing this because of coursework due dates and being sick of bluetooth and expect and mostly because it works on my machine therefore it works :D

# Conclusion

Overall, it was quite a fun experience and I learned a lot about bluetooth and gained some valuable *expect* experience.

Making a raspberry pi act as a bluetooth speaker is a good way to practice your linux skills and also it is quite satisfying once you get it working. Here are some of the resources I found most useful while setting the raspberry up:

[Guide describing the same thing but from 2014](https://www.raspberrypi.org/forums/viewtopic.php?t=68779)

[bluetoothctl 101](https://www.raspberrypi.org/forums/viewtopic.php?t=133961)

[Project with similar aim](https://gist.github.com/oleq/24e09112b07464acbda1)

[TCL scripting basics](https://gist.github.com/Fluidbyte/6294378)

[Storing output into tcl variables](http://code.activestate.com/lists/expect/187/)
