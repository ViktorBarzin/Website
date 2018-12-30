---
title: "07 From Zero to Ansible - A PXE story"
date: 2018-11-24T18:48:38Z
draft: true
---

# Introduction
As promised in my last post, this one will be more technical.
Last time round I mentioned something called a PXE server and I decided to go over it again and this time blog about it.

Last when I was tinkering with this technology (summer 2018) I found the lack of good guides online a bit disturbing
so I'll do my part of enriching the internet now.

What is our goal? Boot a freshly created (virtual) machine and have it install its operating system over the network, import some ssh keys so that it is ready for running ansible playbooks and optionally run some other scripts if needed.
So without further due let's see how this can be done.

# What is a Preboot Execution Environment (PXE) server and do I need one?

You can have a look at the [wiki page](https://en.wikipedia.org/wiki/Preboot_Execution_Environment), that might be helpful to get hold of the theory.
I really wanted to find some PXE pun on the internet but alas I could't.
Essentially a PXE server is a sort of ftp server that
allows computer to boot from the network and serves an image to boot.
How it works? Basically it is magic.

<center> ![](/images/07-magic.gif) </center>

### What is the use case?

Say you have a thousand or even a hundred servers that you want to install with same flavor of linux and have them ready to play ansible playbooks. Well doing that manually is kind of tedious not to mention that if you do it manually you're likely to misconfigure or just have different configurations on some of the servers and you don't want that.

<center> ![](/images/07-From-Zero-To-Ansible-A-Pxe-Story-c611638a.png) </center>

Do you have a thousand servers? Probably not. Nevertheless knowing how PXE works will teach you many things about computers come to life from the moment you press that power button.

Anyway, let's get started finally.

# What are we building exactly?

When a client tries to boot over the network firstly it reaches out to get an IP address.
As the DHCP server sends the response it needs set some parameters to let the client know that it can boot over the network and specify the PXE server to use and how to find it.

Once the client knows where the PXE server is, it reaches out and gets the boot process started.

![](/images/07-From-Zero-To-Ansible-A-Pxe-Story-8c4eabe2.png)

# Steps to boot over the network

Since the entire process is a bit convoluted I will describe the steps in here:

1. Client chooses boot over network option in BIOS menu.
2. Client sends a DHCP request to obtain an IP address and PXE server information.
3. DHCP server assigns an IP address to the client and also provides information about the PXE server.
4. Client contacts the PXE server and requests a

Client pulls the iso over the network and runs it.
TODO: complete steps.

# Configure that DHCP

My DHCP server lives inside a pfSense appliance. [pfSense](https://www.pfsense.org/) is a powerful router/firewall that also includes a DHCP server that is very customizable. If you do not happen to use it, find out how to set these options for your DHCP server.

The path of the DHCP config that we are interested in can be found at `Services > DHCP server > according interface > at the bottom of the Other options section`:

![](/images/07-From-Zero-To-Ansible-A-Pxe-Story-a081ecd5.png)

Obviously you need to change the `Next Server` option to point to your PXE server.

# Creating the PXE Server

Now let's get to the main part - setting up that PXE server.

I'll provide an ansible playbook at the end that you can run and have everything setup up automagically.

TODO: set link to that part

I recommend sticking through the end as I explain each of the steps and what they do.

#### NOTE: I'll set it up on a Debian system so if you're using an rpm-based system you'll need to find the appropriate package names.

The protocol that is used to download the bootloader is [TFTP](https://en.wikipedia.org/wiki/Trivial_File_Transfer_Protocol).
So let's create the root folder for our TFTP server:

`mkdir /tftpboot`

Now let's install and start the TFTP service:

`sudo apt install tftpd-hpa && sudo systemctl start tftpd-hpa`

![](/images/07-From-Zero-To-Ansible-A-Pxe-Story-6290b5f4.png)

The default TFTP directory is `/var/lib/tftpboot` but I like to keep it simple to change that to `/tftpboot`.
The config file is `/etc/default/tftpd-hpa`

This is how it should look like:

![](/images/07-From-Zero-To-Ansible-A-Pxe-Story-1916bf03.png)

Make sure you restart the service afterwards:
`systemctl restart tftpd-hpa`

Now we need to configure the bootloader that will execute on the client's system.
To do that we need to install 2 more packages - `syslinux` and `pxelinux`:

![](/images/07-From-Zero-To-Ansible-A-Pxe-Story-c71bcbd5.png)

Remember the `pxelinux.0` option we had to setup in the DHCP config?
This is the file that will be downloaded and executed by the client.
We need to have this file at the root of the TFTP server:

`cp /usr/lib/PXELINUX/pxelinux.0 /tftpboot`

![](/images/07-From-Zero-To-Ansible-A-Pxe-Story-cf2cf82d.png)

The way *pxelinux* works is the following:

The client downloads `pxelinux.0` file which acts as a bootstrapper. Then it will try to access `$PXE_SERVER_IP/tftpboot/pxelinux.cfg/default`
to get the rest of the config.

Let's create these paths then:

![](/images/07-From-Zero-To-Ansible-A-Pxe-Story-6b9a713d.png)

Now that's done for now. We'll come back filling information in the *default* file later.

So what's happened so far is the client has selected NETBOOT option from their BIOS menu, contacted the PXE server that provided a magical for now
*default* file that so the client can choose an ISO to mount over and start the installation process.

The next thing we'll install is an NFS server which will let the client mount the OS ISO.

`apt install nfs-kernel-server && systemctl start nfs-kernel-server && systemctl status nfs-kernel-server` should install the NFS server and start it:

![](/images/07-From-Zero-To-Ansible-A-Pxe-Story-3ea94caf.png)

Export `/tftpboot` directory via `/etc/exports`. It should look something similar to this:

![](/images/07-From-Zero-To-Ansible-A-Pxe-Story-2ceaec89.png)

Of-course change the allowed network range to match yours. If you'd like to allow anyone to boot from this server or you don't care about security just add a **\*** instead of the ip range.

Remember to restart the NFS server after changing its config: `systemctl restart nfs-kernel-server`
TODO: no_root_squash?

So far so good. Now comes a more magical part.

The client has no installed operating system so far. We want to load some bootstrap software that would allow them to choose what kernel they want to load and load it.
This of-course would require some precompiled binaries and libraries. Fortunately, the `syslinux` package we installed earlier has what we need.
We just need to copy all the bootstrap files to the root of our TFTP server:

![](/images/07-From-Zero-To-Ansible-A-Pxe-Story-54ce3961.png)

{{< highlight bash >}}
cp /usr/lib/syslinux/modules/bios/ldlinux.c32
    /usr/lib/syslinux/modules/bios/vesamenu.c32
    /usr/lib/syslinux/modules/bios/libcom32.c32
    /usr/lib/syslinux/modules/bios/libutil.c32 /usr/lib/syslinux/memdisk /tftpboot/
{{< / highlight >}}

#### IMPORTANT: Make sure you got this step right or stuff will not work!

Create the folder that will hold the isos clients can boot.

{{< highlight bash >}}
mkdir /tftpboot/isos
{{< / highlight >}}

Finally let's add the bulk of the configuration - the `pxelinux.cfg/default` file.

Add the following text:

    DEFAULT vesamenu.c32
    TIMEOUT 200
    ONTIMEOUT BootLocal
    PROMPT 0
    MENU INCLUDE pxelinux.cfg/pxe.conf
    NOESCAPE 1
    LABEL BootLocal
        localboot 0
        TEXT HELP
        Boot to local hard disk
        END TEXT
