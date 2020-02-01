---
title: "12 Why I switched from LVM+EXT4 to BTRFS"
date: 2020-01-13T01:25:47Z
author: "Viktor Barzin"
description: "In this blog post I share my experience of migrating from LVM + EXT4 to BTRFS and the benefits of doing so. I also share a tool called snapper which makes snapshotting and restoring btrfs volumes even easier."
tags:
  [
    "btrfs",
    "B-TreeFS",
    "snapper",
    "snapshot",
    "lvm",
    "ext",
    "ext4",
    "backup",
    "backintime",
    "rsync",
  ]
firstImgUrl: "https://viktorbarzin.me/images/12-filesystem-snapshots-made-easy-1-01-39-44.png"
sitemap:
  priority: 0.3
draft: false
---

# Introduction

Happy 2020 chaps!

It's January again, and it's exam time for me, which means procrastination.
And what better way to procrastinate than exploring something awesome like **BTRFS snapshots**?

In this blog post I'll share why I migrated from **LVM + EXT4** to **BTRFS** and the benefits I found.
I'll go briefly through my experience with [BTRFS](https://wiki.archlinux.org/index.php/Btrfs) and I'll also share a tool I found recently - [Snapper](http://snapper.io/) - which makes snapshotting even easier so let's get started!

# My experience with EXT and LVM

Most, if not all modern linux distributions use [EXT4](https://ext4.wiki.kernel.org/index.php/Main_Page) as a **default** filesystem for their installation.

EXT4 came out in 2006 as an _upgrade_ to EXT3.
It added some optimizations and "[trim](<https://en.wikipedia.org/wiki/Trim_(computing)>)" changes but nothing sensational.
EXT3 came out in November 2001 and, similarly to EXT4, was an upgrade to the previous generation - EXT2.
EXT2 is the father of all EXT filesystems (there is just EXT but you'll probably never see one in use anymore) and it has come out in 1993!

Now, maturity is a very good thing to have when speaking about filesystems - after all, you don't want to invest millions in changing the filesystem on all of your production servers only to find out that it's unstable or its performance is not as good as you expected.
Even if you don't have millions of servers, why should you bother to change the filesystem on your laptop with a filesystem still considered "unstable" by some when EXT is working just fine?

Personally, I have been an EXT user for years.
Initially, I was using plain EXT, back when I was dual-booting Windows but then I never quite got disk partitioning right.
I always found myself with a least a dozen of partitions which was quite annoying.
What's more, EXT4 supports **only offline** shrinking which is quite annoying because even if you use LVM, you still have to unmount the EXT4 partition to reduces its size!
Here's a neat table comparing some of the features of the hottest filesystems right now:

![](/images/12-filesystem-snapshots-made-easy-0-18-29-42.png)

### Mini rant on EXT4 and LVM + EXT4

For some time I was using [LVM](https://wiki.archlinux.org/index.php/LVM) + EXT4.
This solved the many partitions problem as I could just _extend_ the volumes with the new free space that I had added and then run a simple `resize2fs` on the EXT partition.

Following that I started using [LUKS](https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system) for **full disk encryption** which is **a must have nowadays**.
Resizing partitions got even more difficult as to simply add more space to my EXT partition, I had to boot into a live environment, extend the LUKS-encrypted partition, then increase the size of the physical LVM volume, then increase the size of the logical LVM volume and finally `resize2fs` the EXT partition.
What a pain that was!

At this point doing anything on the filesystem level was an enormous pain.

The final thing the made me look for alternatives was **backups**.
I started doing regular backups of my work and I wanted to keep my backup procedure as simple as possible.
Plain `rsync`-ing was doing sort of alright.
I used a wrapper application - [backintime](https://github.com/bit-team/backintime) - as I had some permissions-related issues when `rsync`-ing only.
For most of the time this approach was doing well.
It had occasional misfortunes - _backintime_ hardlinks all files to represent a full directory tree on the backup location and only copies the changes
which works well, however, if the backup is interrupted, sometimes it cannot continue and starts copying over _all files_ from scratch.

This made backups clumsy and always made me think twice before putting my computer to sleep.
Furthermore, how do you restore restore the backups with **no** downtime?
Another feature I was missing was being able to restore from bad commands - sometimes I run commands or scripts that happen to misbehave and there was no easy way to revert their actions.
Doing a full backup just for that single script is not really worth it.
Sure, LVM supports snapshots but then again restoring snapshots can only be done when the LVM partition is not mounted and that's a pain...

# Some light in the end of the filesystems tunnel - BTRFS

After checking out a few filesystems I decided to onboard the BTRFS hype train!

**BTRFS solves all the problems I had so far**:

- supports _online_ resizing - both extending and shrinking
- has built-in support for snapshots - useful for both backups and "testing out" scripts
- removes the need for LVM and thus eliminates 1 layer for filesystem-ing (if that's a word)

On top of that, in 2008, the principal developer of EXT3 and EXT4 - [Theodore Ts'o](https://en.wikipedia.org/wiki/Theodore_Ts%27o) stated that although ext4 has improved features, it is not a major advance; it uses old technology and is a stop-gap. Ts'o said that BTRFS is the better direction because "it offers improvements in scalability, reliability, and ease of management".

On the downsides, there isn't a built-in support for encryption so LUKS has to stay for now, although that feature is planned to come at some point in the future.
Another question mark was performance - from the research I did, BTRFS was doing as good as EXT4 and ZFS, if not better on some benchmarks.
It seemed to be struggling on RAIDs and on spinning hard drives because of fragmentation.
But it's 2020 - if you're still using such a drive you have bigger issues that the performance of the filesystem...

# You said BTRFS snapshots?

Now onto the good stuff.
The [arch wiki contains some excellent documentation](https://wiki.archlinux.org/index.php/Btrfs) (as always) on BTRFS and everything that you might want to do with it.
I highly recommend going through it.
There's no point of copying the commands from there since I probably won't do better at explaining them than they have so definitely have a read.

BTRFS (B-Tree Filesystem) utilizes B-Trees and there are some interesting consequences from that.
For example, every node in the filesystem is either a _leaf_ or a _tree_.
If you are familiar with [Trees](<https://en.wikipedia.org/wiki/Tree_(data_structure)>), you have an idea about their recursive nature.
This allows BTRFS to have subtress which are also BTRFS nodes.
Surprise, surprise, these nodes are called `subvolume`s in BTRFS terminology.
Snapshots are also a type of subvolumes.
Snapshots represent the current state of the filesystem and essentially are just another node in the tree.
Since BTRFS is a [CoW](https://en.wikipedia.org/wiki/Copy-on-write) filesystem, snapshots are cheap to create and maintain and you can easily go back to a snapshot if you like.
Creating a snapshot is easy as

```bash
$ sudo btrfs subvolume snapshot /<some subvolume name> /<snapshots subvolume destination>
```

You can find what subvolumes you have by running:

```bash
$ sudo btrfs subvolume list /
```

You can **mount** and **browse** your snapshots as if it was the real subvolume!
Any changes you make on the original subvolume is not reflected on the snapshot effectively giving you a way to **go back in time for free**!
What's even more awesome is that you can `diff` two snapshots!
For instance, if you want to run some dodgy script, or install some application, you can snapshot before doing the operation, do the operation and snapshot again.
Then you can `diff` the _before_ and _after_ snapshots to see what's changed.
How awesome is that!

The CLI tool for managing BTRFS is called, logically, `btrfs` and has loads of options.
If you can't be bothered to learn all of them, there is a pretty neat tool called [snapper](http://snapper.io/) which manages snapshots for you.
I'd recommend reading the manpage for `snapper`.

I'll share the getting started part and the way I'm using it on my machine.

# Let's play with Snapper and snapshots

Firstly install snapper.
Snapper is included in dnf's repositories:

```bash
$ sudo dnf install -y snapper
```

To operate, `snapper` makes use of configs.
Each BTRFS subvolume that you want to snapshot with `snapper` must have a corresponding config.
I have my `/home` directory in a separate BTRFS subvolume.
To create config for it, you can run

```bash
$ sudo snapper create-config /home
```

(optional) Now if you want to run all the snapper commands on that config, without sudo, you'll need to add your user to the `ALLOWED_USERS` list in `/etc/snapper/configs/home` file.
Mine looks like this:

    ...
    # users and groups allowed to work with config
    ALLOW_USERS="viktor"
    ALLOW_GROUPS="viktor"
    ...

Now you can use `snapper` to manage snapshots for the `/home` config without sudo.
Every time you use `snapper` with the non-default config (root) you need to specify it with `-c` argument.
To see available snapshots on the `/home` config we just made, run

```bash
$ snapper -c home list
```

This command prints the following table:

    #  | Type   | Pre # | Date | User | Cleanup | Description | Userdata
    ---+--------+-------+------+------+---------+-------------+---------
    0  | single |       |      | root |         | current     |

When you make snapshots, more entries will appear in this table.
You can add new snapshots by running

```bash
$ snapper -c home create
```

Easy as that!
Now a _copy_ of your `/home` subvolume has appeared in `/home/.snapshots`

    $ tree /home/.snapshots -L 3

    /home/.snapshots
    └── 1
        ├── info.xml
        └── snapshot
            └── viktor

Listing available snapshots now shows the new snapshot we just added:

    #  | Type   | Pre # | Date                            | User   | Cleanup | Description | Userdata
    ---+--------+-------+---------------------------------+--------+---------+-------------+---------
    0  | single |       |                                 | root   |         | current     |
    1  | single |       | Sun 12 Jan 2020 11:23:01 PM GMT | viktor |         |             |

You can delete a snapshot with `snapper -c home delete <snapshot number>` e.g:

```bash
$ snapper -c home delete 1
```

#### Note: I don't recomment deleting the snapshot with id 0 as that's your current tree and wil result in data loss

You can use these snapshots as backups at any single point of time.
Also you can `rsync` them to a remote server if you want to be safe in case your disk fails.

I wrote the following wrapper around `snapper` to wrap a command in snapshots.
The idea being is - let me see what happens if I run this command.

    function snp(){
        # Runs a command wrapped in btrfs snapper pre-post snapshots.
        # Usage: $ snp <commands>
        # e.g.: $ snp sudo dnf install htop

        cmd="$@"

        snapshot_nbr=$(snapper -c home create --type=pre --cleanup-algorithm=number --print-number --description="${cmd}")

        eval "$cmd"

        snapshot_nbr=$(snapper -c home create --type=post --cleanup-algorithm=number --print-number --pre-number="$snapshot_nbr")
    }

This function creates a `pre` type snapshot before running the command, runs the command you give it and then does a `post` type snapshot.
Running

```bash
snp 'echo "World" >> /home/viktor/test'
```

creates the following snapshots

    #  | Type   | Pre # | Date                            | User   | Cleanup | Description                       | Userdata
    ---+--------+-------+---------------------------------+--------+---------+-----------------------------------+---------
    0  | single |       |                                 | root   |         | current                           |
    1  | pre    |       | Mon 13 Jan 2020 12:06:16 AM GMT | viktor | number  | echo "World" >> /home/viktor/test |
    2  | post   |     1 | Mon 13 Jan 2020 12:06:16 AM GMT | viktor | number  |                                   |

What's great is I can see what files have changed by running:

```bash
$ snapper -c home status 1..2

c..... /home/viktor/test
```

We can even diff the 2 snapshots!

```bash
$ snapper -c home diff 1..2
```

which literally runs `/usr/bin/diff` (or anything you tell it to) on the 2 snapshots:

    --- /home/.snapshots/1/snapshot/viktor/test     2020-01-13 00:06:03.081757300 +0000
    +++ /home/.snapshots/2/snapshot/viktor/test     2020-01-13 00:06:16.589780114 +0000
    @@ -1 +1,2 @@
    Hello
    +World

You can undo the changes made by running:

```bash
$ snapper -c home undochange 1..2

create:0 modify:1 delete:0
```

and now all the changes we made are reversed - how awesome is that!
You can even specify which files to revert if you don't want to revert all changes.

With all those features, literally the sky is the limit to what you can do!

# Useful materials

I really liked this talk on BTRFS - https://www.youtube.com/watch?v=-m01x3gHNjg&t=0s

The Arch wiki has a good guide on BTRFS - https://wiki.archlinux.org/index.php/Btrfs

The snapper docs have a decent tutorial on what you can do how - I recommend going through it - http://snapper.io/tutorial.html

Also, the arch wiki has a tutorial on `snapper` that's also worth a read - https://wiki.archlinux.org/index.php/Snapper

I'll leave it up to you to experiment with and share your experience in the comments.
Thank you for reading and till next time :)
