---
title: "11 Booting Into Trouble - Learning the differences between MBR/GPT, BIOS/UEFI the hard way"
author: "Viktor Barzin"
date: 2019-07-27T12:07:50+03:00
description: "Explaining the early phases of the boot process. Difference between BIOS booting with MBR formatted disk and UEFI booting with GPG formatted disk."
tags:
  [
    "bios",
    "uefi",
    "boot",
    "process",
    "mbr",
    "master boot record",
    "gpt table",
    "recovery",
    "luks",
    "encrypted",
    "kernel",
    "efi system partition",
    "esp",
  ]
firstImgUrl: "https://viktorbarzin.me/images/11-booting-into-trouble-6-13-50-06.png"
sitemap:
  priority: 0.3
draft: false
---

# Introduction

Recently I replaced my [ancient laptop](https://www.cnet.com/products/dell-latitude-e6420-14-core-i5-2520m-4-gb-ram-320-gb-hdd-english-4692110/specs/) with a new, _slightly better_ [one](https://www.dell.com/hr/business/p/precision-15-5530-laptop/pd).
People associate changing workstations with OS reinstall, setting up everything from scratch etc.

I'd rather put my [old disk](https://www.samsung.com/us/computing/memory-storage/solid-state-drives/ssd-860-evo-2-5--sata-iii-1tb-mz-76e1t0b-am/) in my new machine and continue as is.
However, due to the age of my old laptop, I had formatted the disk with a _Master Boot Record (MBR)_ and used _Legacy Boot_ mode, which [turned out, is not supported on new DELL laptops](https://www.dell.com/support/article/hr/en/hrbsdt1/sln309720/newer-dell-systems-unable-to-boot-to-internal-boot-device-in-legacy-boot-mode?lang=en).

Reformatting the disk without losing the data turned out to be harder that expected and was also quite interesting to explore in even greater detail the booting process on a _bare-metal_ level.

I decided to write this blogpost in a tutorial-like style since I found very few comprehensive guides online on how to do that as well as none explained well enough what the \*\*\*\* is happening. Also most tutorials were quite dated and inaccurate so I reckon this one can be used a a point of reference, both by my future self and other people stuck in this situation.

# How do computers boot?

First things first, let's do a brief overview on what happens from the moment you press the power button until a kernel is loaded and executed in memory.

I won't go into too much details here as there's plenty of good reads online. Instead I'll outline the key parts.

Once the power button is pressed on a computer, an electrical circuit is closed and the boot process is initiated.
Depending on the system, it will either have a **BIOS** or **UEFI** - this is the first software that is run, whose purpose is to initialize all the existing hardware and check for any possible errors.
Once that's finished, control is handed over to a program known as a **bootloader**.
The bootloader's main job is to find and execute the **kernel of an operating system** (Unix machines have an additional step - a ram disk (_initrd_) is loaded to memory which contains preinstalled binaries that help to **mount the root file system** where the kernel is located - think _encrypted partitions_, _network partitions_ etc.).
Once the kernel is executed, depending on its type (Windows vs Unix), it will **run all initializing processes** and in the most common case present you with a **login screen**.

## What is a BIOS?

Now, I'm sure that you have an idea of what's the BIOS.
Here's some more detail - it's a small non-volatile chip that lives on your motherboard whose purpose is to initialize system hardware, run some checks on whether everything is fine ([POST](https://whatis.techtarget.com/definition/POST-Power-On-Self-Test)) and provide some way to execute programs on your machine (in the general case a bootloader).

### Booting using BIOS/MBR

The way BIOS machines boot is very simple - once the BIOS has finished its tasks (including storage initialization) it loads the **first sector (512 bytes)** from the first storage device it finds and sets the [Instruction pointer](https://en.wikipedia.org/wiki/Program_counter) to execute whatever is there.

And that's it! Obviously, kernels are bigger than 512 bytes so some trickery is needed like bootloaders and even bootloaders are pretty chunky so they also split in 2 stages (see [detailed post on bootloaders](http://www.independent-software.com/operating-system-development-first-and-second-stage-bootloaders.html)).

P.S: When looking for BIOS booting you will surely come across the Master Boot Record (MBR).
That is just the way people call the first sector of the disk that is being executed.

Here is a summary of the whole process:

![](/images/11-booting-into-trouble-4-15-41-27.png)

If you've ever messed around with `grub2-install`, what it does is simply bootstrap the MBR of whatever disk you point it at so that the next time you boot from it with MBR and can run the GRUB boot menu.

### Setting up a disk with MBR

If you need to setup a system to boot using BIOS/MBR these are the few steps you need to do:

Firstly, Install the `grub2` package using the respective package manager.
On Fedora that'll be:

```bash
sudo dnf install grub2
```

Next, find the disk where you want to install the MBR bootstrap code.
Most of the time that would be `/dev/sda` but do check it. (GParted is handy)

Once you've got that, just run

```bash
sudo grub2-install /dev/sda
```

This _installs_ GRUB on the MBR of you disk.
Lastly, you'll need to create a GRUB config file which will be used by the bootloader to show you the boot menu, boot entries and what not.

The file the GRUB will look for is `/boot/grub2/grub.cfg`.
To create one simply run

```bash
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```

### Caveats for restoring a broken MBR from a live system

Restoring MBR GRUB from a live system is relatively simple.

Keep in mind that the more complex your system is, the harder will it be to fix issues (LUKS, LVM etc.).

Firstly, make sure your disklabel type is `msdos` with

```bash
sudo fdisk -l /dev/sda | grep Disklabel
```

If your setup happens to utilize a full disk encryption (e.g LUKS) you _MUST_ make sure that `/boot/grub2/grub.cfg` is accessible **before** decrypting the kernel.
This can be done by having `/boot` on a separate partition which is what Fedora (I presume Ubuntu as well) does for their default installation using LUKS.

`/boot` partition type can be anything GRUB can boot from (ext* works fine, so does FAT*). If for some reason that partition is missing and you are utilizing LUKS, then you have to manually create it (boot a live system and copy it's working files to the newly created `/boot` and run `grub2-mkconfig` command as shown previously). Also don't forget setting the `boot` flag on the newly created partition.

#### IMPORTANT NOTE: `grub2-mkconfig` creates a config based on the currently running system. If you are running on a live system, you MUST chroot into your system before generating the config.

Once you have checked all of the above caveats, just run the commands shown in the setting up MBR section and you should be good to go.

Fixing MBR GRUB is easier that fixing EFI GRUB as you'll see later.

## What is UEFI?

You can think of UEFI as the new kid on the block. It's supposed to be the better version of the legacy and dated BIOS.
It's written in C (as opposed to the assembly-written BIOS), way more customizable, faster etc. etc.

### Booting using UEFI/GPT

Apart from being cooler than BIOS, UEFI booting is (from my experience) completely incompatible with what we've had so far.
UEFI brings the entire boot process to an entirely new level:

> Instead of a 512-byte MBR and some boot code, the UEFI, in contrast to the legacy BIOS option, knows what a filesystem is and even has its own filesystem, with files and drivers. This filesystem is typically between 200 and 500MB and formatted as FAT32.
>
> Instead of a few bytes of assembly code for loading the operating system, each installed OS should have its own bootloader (e.g., grubx64.efi). This bootloader will have enough logic to either display some sort of boot menu or start loading an operating system. Basically, UEFI is its own mini-operating system.
>
> --[Source](http://www.linux-magazine.com/Online/Features/Coping-with-the-UEFI-Boot-Process)

![](/images/11-booting-into-trouble-5-13-56-27.png)

That's right - we need a separate system partition to store EFI bootloader files - logically called an EFI System Partition (ESP).
The ESP must be a FAT formatted physical partition on your hard disk.
It shouldn't be a LVM volume or something else.

#### Note that the ESP is not the same as the `/boot` partition you might have on your installation!

In the world of EFI, we don't manipulate bytes on our hardrive, instead we operate at the file level.
I find this as a small improvement, though I had difficulties finding the paths to various files such as _grub.cfg_, _grubenv_ etc.

#### The gist is that if you manage to put the correct files in the correct places everything will automagically work!

So in theory, the only tools you'll need when converting from the old BIOS/MBR style of booting to the new UEFI/GPT is `gdisk` (shown later) and some other tool to set disk partition flags ([parted](https://www.gnu.org/software/parted/manual/parted.html), [fdisk](http://tldp.org/HOWTO/Partition/fdisk_partitioning.html), [gparted](https://gparted.org/) etc.)

### Creating an EFI System Partition

We know that the ESP is a simple FAT32 formatted partition with the `esp` flag set.
Here is the layout on my disk. The first partition is the `/boot` partition which was created with the Fedora installation, and partition 3 was manually created by me when I converted from `MBR` to `GPT` disk partitioning.

    Model: ATA Samsung SSD 850 (scsi)
    Disk /dev/sda: 1000GB
    Sector size (logical/physical): 512B/512B
    Partition Table: gpt
    Disk Flags:

    Number  Start   End     Size    File system  Name                  Flags
    1      1049kB  1075MB  1074MB  ext4         Linux filesystem      boot, esp
    2     ********************************************************************************
    3      881GB   881GB   554MB   fat32                              boot, esp
    5     ********************************************************************************

I previously mentioned that all we are going to need for EFI booting is some files, so how do we get them?

Luckily, there are packages that provide the necessary files. When installing these packages, they will write the files to `/boot/efi/` so make sure that your ESP is mounted before you install them:

```bash
$ mount | grep /boot/efi
> /dev/sda3 on /boot/efi type vfat (rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,errors=remount-ro)
```

Then install the packages:

```bash
sudo dnf install grub2-efi grub2-efi-modules shim
```

Here is some more info on what is the purpose of each of the packages:

The `grub2-efi` package is the EFI version of GRUB and it install the bootloader in the `/boot/efi` directory:

    $ rpm -qlp ./grub2-efi-x64-2.02-84.fc31.x86_64.rpm
    /boot/efi/EFI/fedora/fonts
    /boot/efi/EFI/fedora/grubenv
    /boot/efi/EFI/fedora/grubx64.efi
    /boot/grub2/grubenv
    /boot/loader/entries
    /etc/grub2-efi.cfg

`grub2-efi-modules` contains some libraries that are installed in `/usr/lib/`.

What you need to know about the `shim` package is that it is a bit of a hack to enable [Secure Boot](https://docs.microsoft.com/en-us/windows-hardware/design/device-experiences/oem-secure-boot) on Linux systems.
You can read more about it [online](https://docs.fedoraproject.org/en-US/Fedora/18/html/UEFI_Secure_Boot_Guide/sect-UEFI_Secure_Boot_Guide-Implementation_of_UEFI_Secure_Boot-Shim.html).
The files that it provides are:

    $ rpm -qlp ~/shim-14-4.4.x86_64.rpm
    /boot/efi/EFI/BOOT/BOOTX64.EFI
    /boot/efi/EFI/BOOT/fbx64.efi
    /boot/efi/EFI/fedora/BOOTX64.CSV
    /boot/efi/EFI/fedora/mmx64.efi
    /boot/efi/EFI/fedora/shim.efi
    /boot/efi/EFI/fedora/shimx64-fedora.efi
    /boot/efi/EFI/fedora/shimx64.efi

If you have these packages installed but you have reformatted the partition, simply `reinstall` them and the files will reappear.

### So what exactly do we have inside the ESP?

<img style="float:left;margin-right:10px" src="/images/11-booting-into-trouble-4-17-56-51.png" />
In the root of our ESP, there is a single directory named `EFI` which contains information about bootable systems.

Each bootable system has its own directory where the bootloader (and its config) is located.

The `.efi` files are binaries that we won't worry too much about for now. The important ones are `grubx64.efi` and `shimx64-efi`.
The first one is - you guessed it - the grub efi binary.
The shim binary is a intended for systems that utilize _Secure boot_.
Since signing GRUB with microsoft keys it not possible, [the shim binary bridges the gap between the two](https://askubuntu.com/questions/342365/what-is-the-difference-between-grubx64-and-shimx64).

One very important file is `grub.cfg` file which - you got it again - is grub's config.
What boots and the location it boots from is written in this file.
It is the difference between a booting and a non-booting machine.
The rest of the files are mostly binary so you probably won't go tweak them, but `grub.cfg` is a text file that can be easily edited.

Tweaking it usually has the form

```bash
sudo grub2-mkconfig -o /boot/efi/EFI/<operating system>/grub.cfg
```

Now if you have a working system and you run this command while in your system, it probably won't break anything.
However, if you are in a _live system_, trying to fix your own, it might be tricky to get this right.

<p style="clear:left"></p>

# Lessons learned

> The more complex a setup, the harder it is to fix anything broken (or explain what's broken for that matter).
>
> <cite>Me spending days debugging this.</cite>

In the beginning I mentioned that I wanted to change laptops without reinstalling.
The issue was that my disk was MBR-formatted and using a BIOS (yes it was that old!) whereas my new machine does not support booting MBR-formatted disks.

This is what my disk's partitions look like - focusing on the Linux part on the left.

Going from the inside out I have a EXT4 partition where the actual operating system is installed.

Next follows the [Logical Volume Manager (LVM)](https://wiki.archlinux.org/index.php/LVM) which if you're not familiar with, is roughly like a file system the makes disk partitioning less painful by providing _virtual_ partitions which can be dynamically resized without the usual pain of partitioning.

Following that is the [Linux Unified Key Setup (or everyone know it as LUKS)](https://wiki.archlinux.org/index.php/Dm-crypt/Device_encryption) layer which provides the full disk encryption part of the installation.
Everything inside the LUKS layer is encrypted to the outside world.
The order of creating is inwards - the partition format is `lvm2`, then inside it resides the LVM volumes and finally the ext4 partition.

![](/images/11-booting-into-trouble-1-22-53-54.png)

As you can see, screwing the boot is not that hard at all and restoring it is painfully hard.

I spent a few days converting my MBR/BIOS setup to GPT/UEFI one from a live system which was quite hard to get right.

[This guide](https://askubuntu.com/questions/84501/how-can-i-change-convert-a-ubuntu-mbr-drive-to-a-gpt-and-make-ubuntu-boot-from#answer-85857) explains the gist of it.
The grub part is old and does not work anymore, so instead follow the instructions I shared above for installing an EFI bootloader.

### The caveat that is not discussed in most guides

The biggest issue I faced while understanding all the guides I read was that almost none of the emphasized that the `boot` partition and the `esp` partitions **ARE NOT THE SAME**.
If you've installed your linux distribution using defaults with LVM and disk encryption, the installer has created a separate `boot` partition that is used to boot from.
It is not encrypted in any way because the UEFI has no idea how to boot encrypted systems (That's GRUB's responsibility).

Knowing that, restoring your EFI bootloader will require you to

```bash
sudo mount /dev/<whereever your boot partition lives> /boot
```

```bash
sudo mount /dev/<whereever your ESP partition lives> /boot/efi
```

And only afterwards install the `grub2-efi` packages and create the grub config

```bash
sudo grub2-mkconfig -o /boot/efi/EFI/<operating system>/grub.cfg
```

Once you have done these steps in the _right order_, your EFI should recognize the FAT32 EFI Partition and let you boot from it, which will then load the efi GRUB bootloader which knows what modules it needs to decrypt the LUKS, mount the LVM volumes and locate the kernel inside.

# Conclusion

Hope that you've enjoyed reading this blogpost and you learned something new about how computers boot and how they used to do that.
Here is a brief list of some of the resources I found useful while poking with my system:

# References

https://docs.pagure.org/docs-fedora/the-grub2-bootloader.html

http://www.linux-magazine.com/Online/Features/Coping-with-the-UEFI-Boot-Process

https://neosmart.net/wiki/mbr-boot-process/
