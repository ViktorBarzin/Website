---
title: "17 Cloud Seeding (Part 1) - Bootstrapping The Network"
date: 2020-05-25T16:21:28+01:00
author: "Viktor Barzin"
description: ""
sitemap:
  priority: 0.3
tags: []
firstImgUrl: "https://viktorbarzin.me/"
draft: true
---

# Introduction

In this series of blog posts I'll share my experience of setting up a small, highly available on-premise cloud similar to AWS, GCP and Azure but on a much smaller scale solely for learning purposes.

I'll go through technologies such a [PXE booting](https://www.redhat.com/sysadmin/pxe-boot-uefi), [network load balancing](https://metallb.universe.tf/), [container orchestration](http://kubernetes.io/), [distributed filesystems](https://ceph.io/), [infrastructure-as-code](https://www.terraform.io/), [configuration management](https://www.ansible.com/) and metrics monitoring/exporting such as [Prometheus](https://prometheus.io/) and [Grafana](https://grafana.com/).
I spent the last few weeks of migrating my home lab to the setup I'll be describing so these posts will also act as a showcase.

I've paid extra attention to making the whole thing infrastructure-as-code so most services are provisioned and configured via terraform and ansible without any manual interventions.

I would like to go into as much detail as possible but I don't want to make this a super lengthy blog post so I'll split it into multiple parts.
In this part I'll talk about provisioning the network and computing nodes of the cloud - in short, how to get from nothing to a production-ready kubernetes cluster.

# Prerequisites

Setting up a cloud normally requires having multiple physical machines, however, in my case I only have 2 hosts so I make use of virtualization to simulate higher number of nodes (everything is for learning purposes so it doesn't matter that much).

My 2 hosts are part of a VMWare vSphere cluster and virtual machine management is done via vCenter.
Given the hardware that I have, it is much easier to work with the VMWare SDK to provision new VMs that it would have been to work with the bare-metal hosts instead.

Another hardware limitation that I'm working with is my SOHO router which does not support VLANs not PXE booting settings so I have setup a pfSense VM to act as a gateway to the VMs network.
This makes my infrastructure less dependent on the hardware I'm using and thus allows me to upgrade/replace it at any time should I need to do so.

The aforementioned services are not part of the infrastructure-as-code mission (yet) so I won't go into details of how to setup them up as that's trivial.

# Node Network

The first thing to setup is the network where the cluster nodes will reside.
Because the vSphere and pfSense appliances are not yet managed by automation scripts I'll just the plain settings that need to be done to setup a designated VLAN to use for the cluster.

[The first time I setup my home lab](/blog/03-a-walk-down-infrastructure-lane/) I didn't setup any distributed networking whatsoever.
This meant that every time I wanted to move a VM between the ESXi hosts I had to do a bunch of manual operations.
Furthermore, preserving the IP address of the VM was practically impossible without some nasty hacks (such as adding static /32 routes)...

It was a mess so this time round I invested more time in getting the VMWare distributed switch (VDS) to work.
The VDS provides the opportunity of roaming VMs between any of the EXSi hosts without the need of changing any IP configuration.

TODO: finish this section

# Provisioning the PXE Server

The goal here is to automatically create, install and provision one or more hosts that will be part of the cluster.
We will do this with a PXE server.

In rough terms, PXE booting is a mechanism where a client machine can boot over a network, contact a TFTP server to retrieve a bootloader and finally download a kernel to boot from somewhere (might be useful to familiarize yourself on the topic before moving on).

I happen to have a fresh install of Ubuntu 20.04.
I would like to to turn it into a PXE server and add a base image of the OS that we will use for the cluster nodes' OS.

The PXE server will act as both a TFTP server to retrieve the `pxelinux.0` which is the bootloader and as an NFS server which will be contacted to retrieve the kernel, initial ramdisk and installation files.
The following diagram explains how the PXE server will be used by net-booting clients:

![](/images/17-pxe-boot.svg)

Firstly, the client trying to boot over the network will initialize its network configuration by issuing a DHCP request.
During the DHCP negotiation, the DHCP server [sets options 66 and 67](https://www.experts-exchange.com/articles/2978/PXEClient-dhcp-options-60-66-and-67-what-are-they-for-Can-I-use-PXE-without-it.html)
which instruct the client _where_ the TFTP server is and _what_ is the name of the bootloader file.
Next, the client connects to the TFTP server and requests the bootloader.
The TFTP server serves the file and the client executes it.
The `pxelinux.0` bootloader has one or more boot entries.
In out case, we would want to mount the kernel from an NFS server.
Since the bootloader has built-in NFS modules so it can mount the exported directory from the NFS server and retrieve the kernel and initial ramdisk.

As I said previously, I am using pfSense as my router and DHCP.
Setting up network booting in its DHCP service is very simple and the settings look like this:

![](/images/17-cloud-seeding-part-1-5-14-36-55.png)

_10.0.10.20_ is the address of the PXE server.
Both the TFTP and NFS servers reside on this address for simplicity - there isn't a need to split them up into different machines.

Now that we have the DHCP options all setup it's time to see how to setup the PXE server and how to add a distribution to it.
I've setup an Ansible role to do that for me and you can see it below (at some point I'll open source my automation repo, right now it's now very user friendly...).

tl;dr it installs and configures the TFTP daemon, installs pxelinux to use its pre-compiled `pxelinux.0` bootloader, installs and configures the NFS daemon and sets up the config file for the PXE service.

```yaml
---
- name: Create tftp boot dir
  file:
    path: "{{ tftp_dir }}"
    owner: "{{ remote_user }}"
    group: "{{ remote_group }}"
    mode: 0755
    state: directory
  become: true

- name: Install TFTP server
  apt:
    name: "tftpd-hpa"
    state: present
  become: true

- name: Start TFTP service
  service:
    name: "tftpd-hpa"
    state: "started"
    enabled: "yes"
  become: true

- name: Set tftp directory in config
  lineinfile:
    path: "/etc/default/tftpd-hpa"
    regexp: "^TFTP_DIRECTORY="
    line: "TFTP_DIRECTORY={{ tftp_dir }}"
  notify:
    - restart tftpd
  become: true

# Make sure dhcp server is configured

- name: Install pxelinux and syslinux
  apt:
    name: ["pxelinux", "syslinux"]
    state: present
  become: true

- name: Copy pxelinux.0 file to TFTP dir
  copy:
    remote_src: True
    src: "/usr/lib/PXELINUX/pxelinux.0"
    dest: "{{ tftp_dir }}"

- name: Create pxelinux config dir
  file:
    path: "{{ tftp_dir }}/pxelinux.cfg"
    state: directory
    mode: 0755
    owner: "{{ remote_user }}"
    group: "{{ remote_group }}"

- name: Create default pxelinux config file
  file:
    path: "{{ tftp_dir }}/pxelinux.cfg/default"
    state: touch
    mode: 0644
    owner: "{{ remote_user }}"
    group: "{{ remote_group }}"

- name: Install NFS server
  apt:
    name: "nfs-kernel-server"
    state: present
  become: true

- name: Add install folder to /etc/exports
  lineinfile:
    path: "/etc/exports"
    line: "{{ tftp_dir }} {{ nfs_allowed_net }}(ro,async,no_subtree_check)"
  notify:
    - restart nfs
  become: true

- name: Copy bootstrap files to "{{ tftp_dir }}"
  synchronize:
    src: "{{ item }}"
    dest: "{{ tftp_dir }}/{{ item | basename }}"
    recursive: yes
  with_items:
    - "/usr/lib/syslinux/modules/bios/ldlinux.c32"
    - "/usr/lib/syslinux/modules/bios/vesamenu.c32"
    - "/usr/lib/syslinux/modules/bios/libcom32.c32"
    - "/usr/lib/syslinux/modules/bios/libutil.c32"
    - "/usr/lib/syslinux/memdisk"
  delegate_to: "{{ inventory_hostname }}"

# Perhaps add background image?

- name: Add pxe.conf file
  file:
    path: "{{ tftp_dir }}/pxelinux.cfg/pxe.conf"
    state: touch
    mode: 0644
    owner: "{{ remote_user }}"
    group: "{{ remote_group }}"

- name: Create ISOs dir
  file:
    path: "{{ isos_dir }}"
    state: directory
    mode: 0755
    owner: "{{ remote_user }}"
    group: "{{ remote_group }}"

- name: Add pxelinux.conf/default file locally
  copy:
    content: ""
    dest: "{{ role_path }}/files/pxelinux-cfg-default"
    force: yes
    mode: "644"
    owner: "{{ lookup('env','USER') }}"
    group: "{{ lookup('env','USER') }}"
  delegate_to: localhost

- name: Add bootstrap options in pxelinux-cfg-default
  delegate_to: localhost
  blockinfile:
    dest: "{{ role_path }}/files/pxelinux-cfg-default"
    marker: "# --- {mark} bootstrap settings ---"
    block: |
      DEFAULT vesamenu.c32
      TIMEOUT 100
      PROMPT 0
      MENU INCLUDE pxelinux.cfg/pxe.conf
      NOESCAPE 1

      LABEL BootLocal
          localboot 0
          TEXT HELP
          Boot to local hard disk
          ENDTEXT

- name: Copy pxelinux.cfg/default to remote
  copy:
    src: "{{ role_path }}/files/pxelinux-cfg-default"
    dest: "{{ tftp_dir }}/pxelinux.cfg/default"
    mode: "644"
    owner: "{{ remote_user }}"
    group: "{{ remote_group }}"

- name: Copy ks.cfg to remote
  copy:
    src: "{{ role_path }}/files/ks.cfg"
    dest: "{{ tftp_dir }}/ks.cfg"
    mode: "644"
    owner: "{{ remote_user }}"
    group: "{{ remote_group }}"
```

There are a few variables you need to set in your setup and once that's done it should configure a working PXE server.
However, the server does not serve any distributions so it's pretty useless.
So I'll show you how to add a distribution now.
Also, note the final step in the playbook above - where `ks.cfg` is being copied to the remote.
I'll explain it after we have added a distro to boot.

What this role does is it downloads a distro iso (does not check whether it's valid!), creates a subdirectory (within the NFS export) with the distro name, mounts the downloaded iso file and copies the required installation files over to the distro directory.
Finally, adds an entry in the PXE config to reflect the newly added option.
Make sure you use a netboot image and not a normal iso otherwise the vm will fail to boot!

```yaml
---
# Always use NETBOOT images for your distro
# NO spaces in menu_entry please
# extra-vars to pass in cli:
#   iso_url(required) - the location of the netboot iso to download (get_url module format)
#   menu_entry(optional) - the name of the distro. this will be used as distro folder name
#

- name: Fail when iso_url is not passed
  fail:
    msg: Required argument 'iso_url' is missing
  when: iso_url is not defined

- name: Get distro file name
  shell: "echo {{ iso_url | basename }}"
  register: "distro_name"

- name: Create distro menu entry string
  shell: "echo {{ menu_entry | default(distro_name.stdout | basename | splitext | first) }}"
  register: distro_menu_entry

- name: Download distro iso
  get_url:
    url: "{{ iso_url }}"
    dest: "{{ isos_dir }}/{{ distro_menu_entry.stdout }}.iso"
    mode: 0644
    owner: "{{ remote_user }}"
    group: "{{ remote_group }}"

- name: Get distro dir name
  shell: "echo {{ iso_url | basename | splitext | first }}"
  register: "distro_dir"

- name: Mount "{{ distro_menu_entry.stdout }}.iso" to "{{ mnt_dir }}"
  mount:
    path: "{{ mnt_dir }}"
    src: "{{ isos_dir }}/{{ distro_menu_entry.stdout }}.iso"
    fstype: iso9660
    opts: ro,noauto
    state: mounted
  become: yes

- name: Create distro folder
  file:
    path: "{{ tftp_dir }}/{{ distro_menu_entry.stdout }}"
    state: directory
    mode: 0755
    owner: "{{ remote_user }}"
    group: "{{ remote_group }}"

- name: Copy "{{ distro_menu_entry.stdout }}.iso" contents to "{{ tftp_dir }}/{{ distro_menu_entry.stdout }}"
  synchronize:
    src: "{{ mnt_dir }}/"
    dest: "{{ tftp_dir }}/{{ distro_menu_entry.stdout }}"
    recursive: yes
  delegate_to: "{{ inventory_hostname }}"

- name: Unmount "{{ mnt_dir }}"
  mount:
    path: "{{ mnt_dir }}"
    state: unmounted
  become: yes

# When kernel and initramfs are found, use them as entries in the menu
- name: Add distro menu entry in local file - kernel and initrd found
  blockinfile:
    dest: "{{ role_path }}/../files/pxelinux-cfg-default"
    marker: "# --- {mark} {{ distro_menu_entry.stdout }} ---"
    # Adding kickstart file as well - if you are going to automate, automate it all
    block: |
      MENU TITLE {{ distro_menu_entry.stdout }}
        LABEL "{{ distro_menu_entry.stdout }}"
                MENU DEFAULT # Set as default option. Last one is applied
                MENU LABEL {{ distro_menu_entry.stdout }}
                KERNEL {{ (kernel_search_results.files | first).path | relpath(tftp_dir)}}
                APPEND method=nfs://{{ tftpd_server }}{{ tftp_dir }}/{{ distro_menu_entry.stdout }} initrd={{ (initrd_search_results.files | first).path | relpath(tftp_dir) }} ks=nfs:{{ tftpd_server }}:/tftpboot/ks.cfg hostname={{ distro_menu_entry.stdout | lower | regex_replace('\.') }}
      MENU END
  delegate_to: localhost

- name: Copy pxelinux.cfg/default to remote
  copy:
    src: "{{ role_path }}/../files/pxelinux-cfg-default"
    dest: "{{ tftp_dir }}/pxelinux.cfg/default"
    mode: 0644
    owner: "{{ remote_user }}"
    group: "{{ remote_group }}"
```

I have setup the pxe-server role as a dependency to the add distro one so calling it from the entry point of my playbook looks like this:

```yaml
- {
    role: linux/pxe-server/add-distro,
    tags: ["linux/pxe-server/add-distro", "never"],
    vars: {
        # iso_url: "http://archive.ubuntu.com/ubuntu/dists/bionic-updates/main/installer-amd64/current/images/netboot/mini.iso",
        # menu_entry: "Ubuntu18.04",
        iso_url: "http://archive.ubuntu.com/ubuntu/dists/eoan/main/installer-amd64/current/images/netboot/mini.iso",
        menu_entry: "Ubuntu19.10",
      },
  }
```

and the actual command:

```bash
$ ansible-playbook -i hosts.yaml linux.yml -t linux/pxe-server/add-distro
```

Now we have a working PXE server that serves, in this case, Ubuntu 19.10
The next step is to create virtual machines that will serve as nodes in our cluster.

Before doing that I want to mention the _kickstart_ file which you can see in the `APPEND` line in the pxe config.
Booting from the network is good, however, we would like an automatic install of the machine as well.
This is where the kickstart file comes into play.

> Kickstart provides a way for users to automate a Red Hat Enterprise Linux installation. Using kickstart, a system administrator can create a single file containing the answers to all the questions that would normally be asked during a typical installation. Once a kickstart file has been generated it can either be included with boot media or made available on the network for easy and consistent configuration of new systems.
>
> -- <cite>https://access.redhat.com/labsinfo/kickstartconfig</cite>

Kickstart files were developed by RedHat for RHEL-based distros.
Ubuntu has their own way of doing kickstart installations - via [preseed](https://help.ubuntu.com/lts/installation-guide/s390x/apb.html).
Happily, Ubuntu supports kickstart installations so we can use that to install both Ubuntu and RHEL distros.

[Here](/misc/ks.cfg) you can find the `ks.cfg` file I'm referring to in the `APPEND` line in the bootloader.
You would want to create an ansible role to copy this file over.
I'm not pasting both for brevity.
Spend some time to investigate the kickstart file if you've never seen how one looks like.

You might want to change the password of the initial user that I create as well as the public key that's imported.
It is important to put your public key there otherwise the end-to-end automation would break since ansible would not be able to automatically ssh into the machine later on.

### Create and provision nodes

Now to the fun part.
After we have the network booting and automatic installation, it's time to _code_ the infrastructure for the cluster.

The objective is to provision a 4 node kubernetes cluster with a single master.

I'm using [Terraform](https://www.terraform.io/) to do that.
I hadn't used it before but I found it quite intuitive and easy to work with.

My infrastructure uses VMWare and Terraform has a provider to work with the VMWare SDK.
The layout includes 2 modules - 1 to create a virtual machine (specify RAM, CPUs, Disk, Network, vSphere cluster etc.) and 1 to declare the infrastructure.
Here is the tree of the terraform directory:

```bash
.
├── main.tf
├── modules
│   └── create-vm
│       ├── main.tf
├── playbook -> ../playbook
└── terraform.tfvars
```

I'll start from the `main.tf` in the root of the terraform project and its contents:

```terraform
variable "vsphere_password" {}
variable "vsphere_user" {}
variable "vsphere_server" {}

variable "ansible_prefix" {
  default     = "ANSIBLE_VAULT_PASSWORD_FILE=~/.ansible/vault_pass.txt ansible-playbook -i playbook/hosts.yaml playbook/linux.yml -t linux/initial_setup"
  description = "Provisioner command"
}

# Main module to init infra from

module "k8s_master" {
  source              = "./modules/create-vm"
  vm_name             = "k8s-master"
  network             = "dKubernetes"
  provisioner_command = "${var.ansible_prefix} -t linux/k8s/master -e hostname=k8s-master"

  vsphere_password = var.vsphere_password
  vsphere_user     = var.vsphere_user
  vsphere_server   = var.vsphere_server

}
module "k8s_node1" {
  source              = "./modules/create-vm"
  vm_name             = "k8s-node1"
  network             = "dKubernetes"
  provisioner_command = "${var.ansible_prefix} -t linux/k8s/node -e hostname=k8s-node1 -e k8s_master='wizard@${module.k8s_master.guest_ip}'"

  vsphere_password = var.vsphere_password
  vsphere_user     = var.vsphere_user
  vsphere_server   = var.vsphere_server
}
module "k8s_node2" {
  source              = "./modules/create-vm"
  vm_name             = "k8s-node2"
  network             = "dKubernetes"
  provisioner_command = "${var.ansible_prefix} -t linux/k8s/node -e hostname=k8s-node2 -e k8s_master='wizard@${module.k8s_master.guest_ip}'"

  vsphere_password = var.vsphere_password
  vsphere_user     = var.vsphere_user
  vsphere_server   = var.vsphere_server
}
module "k8s_node3" {
  source              = "./modules/create-vm"
  vm_name             = "k8s-node3"
  network             = "dKubernetes"
  provisioner_command = "${var.ansible_prefix} -t linux/k8s/node -e hostname=k8s-node3 -e k8s_master='wizard@${module.k8s_master.guest_ip}'"

  vsphere_password = var.vsphere_password
  vsphere_user     = var.vsphere_user
  vsphere_server   = var.vsphere_server
}
```

Starting from the top, 3 variables are defined and initialized in `terraform.tfvars` - `vsphere_password`, `vsphere_user` and `vsphere_server`.
They are then passed to the `./modules/create-vm` module that as we'll see in a bit will be used to authenticate to the VMWare API.

Each _module_ represents a virtual machine that will be created.
The `provisioner_command` is the ansible playbook that is run to provision the nodes.
Role selection is done using [ansible tags](https://docs.ansible.com/ansible/latest/user_guide/playbooks_tags.html).
This allows for choosing the role to be run at **runtime**.

The `./modules/create-vm` module is a bit bloated but I'll put it here for future reference:

```terraform
variable "vsphere_user" {
  default = "Administrator@vsphere.local"
}
variable "vsphere_password" {}
variable "vsphere_server" {
  default = "vcenter"
}
variable "vm_name" {
  default = "terraform-test"
}
variable "vm_cpus" {
  type    = number
  default = 4
}

variable "vm_mem" {
  type    = number
  default = 4096
}

variable "vm_guest_id" {
  default = "ubuntu64Guest"
}

variable "vm_disk_size" {
  type    = number
  default = 20
}

variable "provisioner_command" {
  description = "Additional provisioning commands to run"
}

variable "network" {
  description = "Network to attach the vm guest to"
}

provider "vsphere" {
  user           = var.vsphere_user
  password       = var.vsphere_password
  vsphere_server = var.vsphere_server

  # If you have a self-signed cert
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = "Samitor"
}

data "vsphere_datastore" "datastore" {
  name          = "T610-datastore"
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = "T610"
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_virtual_machine" "vm" {
  name             = var.vm_name
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus = var.vm_cpus
  memory   = var.vm_mem
  guest_id = var.vm_guest_id

  network_interface {
    network_id = data.vsphere_network.network.id
  }

  disk {
    label = "disk0"
    size  = var.vm_disk_size
  }

  disk {
    label       = "ceph-disk0"
    size        = 16
    unit_number = 1
  }
  wait_for_guest_net_timeout = 600

  provisioner "local-exec" {
    command = "${var.provisioner_command} -e 'host=${vsphere_virtual_machine.vm.default_ip_address}'"
  }
}

output "guest_ip" {
  value = vsphere_virtual_machine.vm.default_ip_address
}
```

This module creates the VM, specifies number of virtual CPUs, RAM, storage, network, computing resource pool and how to connect to the vSphere API.
Note the `dKubernetes` network that I'm using - this is a distirbuted portgroup in the distributed vSwitch to which all Kubernetes nodes will be connected to.
The PXE server should also be connected to the same network, as otherwise VMs will not be able to receive the boot image.

Now if everything is setup correctly, running `tf apply` should initiate the bootstrapping process.
On my hardware, installing a node takes around 12 minutes and then a few more to run the ansible playbook.

Finally, I will show you what playbooks are run once the node is installed and has my SSH key installed.
If you looked carefully at the terraform files, you will have noticed the `provisioner_command` is running ansible-playbook with some tags.

All nodes run the `linux/initial_setup` role.
This role prepares the nodes for further exploitation by installing some packages.
I'll post each task and explain why it is needed.

```yaml
- name: "Set '{{ hostname }}' as hostname"
  hostname:
    name: "{{ hostname }}"
  become: yes
  when: hostname is defined

- name: "Put hostname '{{ hostname }}' in /etc/hosts"
  lineinfile:
    path: /etc/hosts
    state: present
    line: "127.0.0.1 {{ hostname }}"
  become: yes
  when: hostname is defined
```

Firstly set the hostname if the variable is defined.
By default, all VMs have the same hostname.
Kubernetes gets very angry if we try to join multiple nodes which have the same hostname.
That's why when we run this run the first time, we want to set the hostname to something unique - in my case I am setting the hostname to match the virtual machine name (e.g. `-e hostname=k8s-master`).

```yaml
- name: Install packages
  apt:
    name:
      [
        "aptitude",
        "python3-pip",
        "htop",
        "nmap",
        "gdisk",
        "ntp",
        "ntpdate",
        "lvm2",
        "curl",
        "wget",
        "wireguard",
        "net-tools",
        "iotop",
        "tree",
      ]
    state: present
    update_cache: yes
  become: true

- name: Install python packages
  pip:
    name: ["pexpect", "docker-py"]
    state: present
```

Next, install some useful packages on the node.

#### Important: `lvm2`, `ntp` and `ntpdate` are **required** for the distributed filesystem we will setup later on. Make sure they are installed, I'll explain later on what the issues are.

The other packages are pretty much optional and useful-to-have.
The `wireguard` package is installed only because Ubuntu 19.10 which I'm using as base image, uses kernel 5.3 which does not have the wireguard modules built-in and I need them for my wireguard deployment later on.

```yaml
- name: Make sure ntp is running
  systemd:
    enabled: yes
    state: started
    name: ntp
  become: true
```

Finally, ensure that the ntp service is running.
This is **very important**.
If for some reason VMs' clocks differentiate by more then 50ms, the distributed filesystem that we will use - [Ceph](https://ceph.io/) - get's quite angry and hell opens.
Using the NTP service ensures that clocks are regularly synchronized and timing issues to not happen.

## Kubernetes roles

Now we need to initialize the kubernetes cluster and join nodes.
Before that we need to install some more stuff such as docker.

Installing docker is as easy as running this playbook:

```yaml
- name: Add Docker gpg key
  apt_key:
    url: https://download.docker.com/linux/ubuntu/gpg
    state: present
  become: true

- name: Add Docker repo
  apt_repository:
    repo: deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ ansible_lsb['codename']}} stable
    state: present
  become: true

- name: Install Docker package
  apt:
    name: "docker-ce"
    update_cache: true
  become: true

- name: Enable docker service
  service:
    name: docker
    enabled: yes
    state: restarted
  become: true

- name: "Add {{ remote_user }} to docker group"
  user:
    name: "{{ remote_user }}"
    groups: docker
    append: yes
  become: yes
```

To setup kubernetes, I've followed the official guide.
Coded in the following playbook:

```yaml
# Playbook tailored for Debian-like sytems.
# RHEL has kubernetes in repos, for the moment ubuntu does not. Fix when package is available

- name: Add Kubernetes gpg key
  apt_key:
    url: https://packages.cloud.google.com/apt/doc/apt-key.gpg
    state: present
  become: yes

- name: Add Kubernetes repo
  apt_repository:
    repo: deb [arch=amd64] http://apt.kubernetes.io/ kubernetes-xenial main
    state: present
  become: yes

# Disable swap otherwise Kubelet will not start
- name: Remove swapfile from /etc/fstab
  become: yes
  mount:
    name: "{{ item }}"
    fstype: swap
    state: absent
  with_items:
    - swap
    - none

- name: Disable swap
  become: yes
  command: swapoff -a

- name: Install kubernetes packages
  package:
    name: ["kubelet", "kubeadm", "kubectl"]
    state: present
  become: yes

- name: Install PIP dependencies for ansible
  pip:
    name:
      - kubernetes
      - openshift
```

Finally, we are ready to initiate the cluster.

If you look at the Terraform module for the master, it has the `-t linux/k8s/master` tag set.
This is what this role looks like:

```yaml
- name: Initialize the Kubernetes cluster using kubeadm
  become: yes
  command: kubeadm init --node-name "{{ node_name }}"

- name: Create $HOME/.kube dir
  file:
    path: "{{ ansible_env.HOME }}/.kube"
    state: directory
    mode: "0755"

- name: Copy kuberenetes admin.conf
  become: yes
  copy:
    src: /etc/kubernetes/admin.conf
    dest: "{{ ansible_env.HOME }}/.kube/config"
    owner: "{{ remote_user }}"
    group: "{{ remote_user }}"
    remote_src: yes

- name: Create local kube dir
  file:
    path: "{{ lookup('env','HOME') }}/.kube"
    state: directory
    mode: "0700"
  delegate_to: localhost

- name: Copy kubeconfig to local
  fetch:
    src: "{{ ansible_env.HOME }}/.kube/config"
    dest: "{{ lookup('env','HOME') }}/.kube/config"
    flat: yes

- name: Init network plugin
  command: "kubectl apply -f 'https://cloud.weave.works/k8s/net'"
  delegate_to: localhost
```

This role initializes the kubernetes cluster using `kubeadm`.
It then copies the _kubeconfig_ to the home directory of the remote user on the node as well as locally, on your development machine, so that you can start managing your cluster with `kubectl` immediately!

The last task that is run is to initialize a network plugin.
I chose weave without a good enough reason but it seems to be doing quite well so far - I haven't had any issues with it.

Worker nodes need a join token to join the cluster.
That's why the playbook for joining nodes first SSHes to the cluster master, gets the join command with a unique token and then uses it on the worker node to join it in the cluster.
It is as simple as

```yaml
# SSH to the k8s master, get a join token and use it
- name: "Get join command from Kubernetes master at '{{ k8s_master | mandatory }}'"
  command: kubeadm token create --print-join-command
  register: kubeadm_token_create
  delegate_to: "{{ k8s_master }}"

- name: Join the node to cluster
  become: yes
  command: "{{ kubeadm_token_create.stdout }}"
```

If everything went well, you should be able to see all your nodes in the _Ready_ state:

```bash
╰─$ kubectl get nodes
NAME         STATUS   ROLES    AGE   VERSION
k8s-master   Ready    master   21d   v1.18.2
k8s-node1    Ready    <none>   21d   v1.18.2
k8s-node2    Ready    <none>   21d   v1.18.2
k8s-node3    Ready    <none>   21d   v1.18.2

```
