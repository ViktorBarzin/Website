---
title: "21 Home Lab v3 - The Foundation"
date: 2026-03-01T00:00:00Z
author: "Viktor Barzin"
description: "My home lab has grown from ~20 services to 70+. This is part 1 of a series covering the hardware, network, and platform that runs it all. Deep dive into a Dell R730 running Proxmox, Kubernetes on bare-metal VMs, a 3-VLAN network with pfSense, and the Terragrunt-based IaC that ties it together."
tags: ["home", "lab", "proxmox", "kubernetes", "k8s", "pfsense", "network", "vlan", "metallb", "traefik", "terragrunt", "terraform", "infrastructure", "self-hosting", "dell", "r730", "tesla", "t4", "gpu", "ups", "truenas", "nfs"]
firstImgUrl: "https://viktorbarzin.me/images/21-home-lab-v3-overview.svg"
draft: true
---

# Introduction

It's been 5 years since my [Home Lab v2](/blog/17-home-lab-v2/) post. Back then I was running ~20 services on a VMware ESXi setup. Now it's 70+ services on Proxmox, managed entirely through Terragrunt, with a Tesla T4 GPU for ML workloads, a 5-layer anti-AI scraping system, and solar panels in Sofia.

This is Part 1 of a 4-part series:
1. **The Foundation** (this post) — hardware, network, platform
2. **The Platform** — Kubernetes, auth, security, GPU
3. **The Services** — what I run and why
4. **Sofia & Operations** — smart home, solar, monitoring, CI/CD

# High-Level Architecture

![High-level architecture](/images/21-home-lab-v3-overview.svg)

Everything runs on a single Dell R730 in my flat. Internet comes in through Cloudflare (DNS + Tunnel), hits pfSense for firewall/routing, and fans out across 3 VLANs into a 5-node Kubernetes cluster. A remote Home Assistant instance in Sofia handles the solar setup and smart home there.

# Hardware

## Dell PowerEdge R730

| Component | Spec |
|-----------|------|
| CPU | Intel Xeon E5-2699 v4 — 22C/44T @ 2.2GHz |
| RAM | 142 GB DDR4 |
| GPU | NVIDIA Tesla T4 (16GB, PCIe passthrough to k8s-node1) |
| Storage | 1.1TB + 931GB local SSD, 10.7TB HDD |
| Remote Mgmt | iDRAC Enterprise (custom Redfish exporter → Prometheus) |
| UPS | Huawei UPS2000 2kVA (SNMP v1 → Prometheus) |

Why a single beefy server instead of multiple smaller nodes? Simplicity. One machine to power on, one set of disks to worry about, one iDRAC to remote into when things go sideways at 2am. The 44 threads and 142GB RAM mean I've never hit a resource ceiling — services just slot in.

The Tesla T4 was a later addition. I wanted to self-host LLMs (Ollama), run ML-based photo search (Immich), and do real-time camera inference (Frigate) without sending my data to cloud APIs. The T4's 16GB VRAM and low 70W TDP make it ideal for always-on inference in a home setting. It's PCIe-passthrough to `k8s-node1` and shared across workloads via NVIDIA's time-slicing — more on that in Part 2.

## Why iDRAC Matters

The R730 sits in a closet. When a kernel update goes wrong or a VM freezes, iDRAC gives me a remote KVM console, power control, and hardware health monitoring without physically touching the server. I built a custom Redfish exporter (the upstream image didn't exist for ARM/AMD64) that feeds iDRAC metrics into Prometheus — CPU temps, fan speeds, power draw, event log entries.

## UPS Monitoring

The Huawei UPS2000 keeps the server alive through power cuts. Without monitoring, a UPS is a black box — you don't know it's dying until it's dead.

![UPS monitoring pipeline](/images/21-home-lab-v3-ups.svg)

The UPS exposes metrics via SNMP v1. I wrote a custom SNMP exporter config that pulls Huawei-proprietary MIB OIDs (`1.3.6.1.4.1.2011.6.174`) for apparent and active power — data the standard UPS-MIB doesn't expose. Grafana shows battery charge, estimated runtime, load percentage, and input/output voltage in real-time. I get alerted if battery drops below 50% or load exceeds 80%.

# Virtualization — Proxmox

Moved from VMware ESXi to Proxmox in 2023. ESXi's free tier was getting more restrictive, and Broadcom's acquisition made the future uncertain. Proxmox gave me three things ESXi couldn't: no licensing cost, a proper REST API for Terraform automation, and first-class cloud-init support for VM templating.

![Proxmox VM layout](/images/21-home-lab-v3-proxmox.svg)

12 VMs on a single host. The k8s nodes are identical (except node1 which gets the GPU) — this makes them interchangeable and easy to rebuild.

### Node Rebuild Automation

K8s nodes are cattle, not pets. If a node misbehaves, I don't debug it — I replace it. The rebuild process takes about 5 minutes:

1. `kubectl drain` + `kubectl delete node`
2. Destroy VM in Terraform
3. Fresh `kubeadm token create --print-join-command`
4. Create VM from cloud-init template → auto-joins cluster

The entire process is in `stacks/infra/main.tf`. Cloud-init handles OS setup, package installation, and cluster join on first boot. Tokens expire after 24h, so you generate them right before provisioning.

# Network

## Why Three VLANs?

Flat networks are simple but dangerous — a compromised IoT device shouldn't be able to reach your NFS server. VLANs provide isolation without additional hardware.

![Network topology](/images/21-home-lab-v3-network.svg)

| Network | Subnet | Purpose |
|---------|--------|---------|
| Home | 192.168.1.0/24 | Physical devices, Proxmox host |
| Management (VLAN 10) | 10.0.10.0/24 | TrueNAS NFS, dev VM, out-of-band access |
| Kubernetes (VLAN 20) | 10.0.20.0/24 | All k8s nodes, MetalLB pool (.200-.220), DNS (.101) |
| WireGuard | 10.3.2.0/24 | Site-to-site VPN |
| Headscale | 100.64.x.x | Mesh VPN overlay |

The management VLAN is the key insight — it keeps storage traffic (NFS) off the Kubernetes network, and gives me out-of-band access to infrastructure VMs even if the k8s network goes down. Proxmox uses two bridges: `vmbr0` on the physical NIC for the home network, and `vmbr1` as a VLAN-aware trunk carrying VLAN 10 and 20 to the VMs.

## pfSense

pfSense CE 2.7.2 runs as a VM (VMID 101). 167 firewall rules, 154 NAT rules. Why pfSense over OPNsense or a simple iptables box? The package ecosystem — I get WireGuard, Snort IDS, DHCP, and a REST API in one appliance:

- **Snort IDS** — intrusion detection on WAN. Catches port scans and known exploit attempts.
- **WireGuard** — VPN server on 10.3.2.0/24. I can access my entire network from anywhere.
- **Tailscale** — joins the self-hosted Headscale mesh for device-to-device connectivity.
- **Kea DHCP** — serves DHCP for all 3 networks with static leases for infrastructure.
- **FRR** — BGP/OSPF, not actively used but ready if I ever need dynamic routing.

## DNS — Split Horizon

Why split-horizon? External users need Cloudflare's DDoS protection and CDN. Internal users need to resolve services to private IPs without hairpinning through the internet.

![DNS split-horizon](/images/21-home-lab-v3-dns.svg)

- **External**: Cloudflare manages `viktorbarzin.me`. Services are proxied through Cloudflare Tunnel or direct WAN NAT.
- **Internal**: Technitium DNS at `10.0.20.101` handles `viktorbarzin.lan` and overrides `viktorbarzin.me` records to point to internal IPs.

When I'm on the home network, `nextcloud.viktorbarzin.me` resolves to `10.0.20.200` (Traefik's MetalLB IP) directly — no round-trip through Cloudflare. When I'm remote, the same domain goes through Cloudflare Tunnel. Same URL, different path, zero client configuration.

## Docker Registry Pull-Through Cache

This is one of the most impactful pieces of infrastructure for a homelab running Kubernetes. Without it, every pod restart pulls images from Docker Hub over the internet. With 70+ services and rolling updates, that's a lot of bandwidth and latency — and Docker Hub's rate limit (100 pulls/6h for anonymous, 200 for authenticated) becomes a real problem during cluster-wide operations.

The cache runs on a dedicated VM (`10.0.20.10`) with 5 pull-through proxies:

| Port | Registry | Why |
|------|----------|-----|
| 5000 | docker.io | Most images. Rate limit protection. |
| 5010 | ghcr.io | GitHub-hosted images (Hugo, etc.) |
| 5020 | quay.io | Red Hat / CoreDNS images |
| 5030 | registry.k8s.io | Kubernetes system images |
| 5040 | reg.kyverno.io | Kyverno policy engine images |
| 5050 | Private R/W | My own built images |

All fronted by nginx. Containerd on every k8s node has `hosts.toml` configured to route pulls through the cache. Benefits:

- **Speed**: cached images pull in milliseconds instead of seconds
- **Rate limit immunity**: one pull from upstream, unlimited pulls from cache
- **Offline resilience**: cluster continues working even if Docker Hub is down
- **Node rebuilds**: a fresh node can pull all 70+ service images from the LAN cache in under a minute

## Load Balancing — MetalLB

Bare-metal Kubernetes doesn't have cloud load balancers. MetalLB fills that gap by advertising IPs from a local pool (`10.0.20.200`–`10.0.20.220`) via Layer-2 ARP. Services that need a stable external IP — Traefik ingress, Technitium DNS, the mail server — each get one from this pool. It's the glue that makes `Service type: LoadBalancer` work outside of AWS/GCP.

# Storage — TrueNAS + NFS

Why NFS over local storage or a distributed filesystem like Ceph? For a single-server homelab, NFS is the right trade-off: zero overhead, trivially simple, and every pod can access the same data. Ceph would add complexity (and require 3+ nodes) for redundancy I don't need — my backup strategy is NFS snapshots + off-site rsync.

TrueNAS runs as a VM (VMID 9000) with 7x 256GB + 1TB pool, serving NFS to the cluster. Every service that needs persistent storage mounts an NFS volume:

```hcl
volume {
  name = "data"
  nfs {
    server = var.nfs_server  # 10.0.10.15
    path   = "/mnt/main/<service>"
  }
}
```

I use inline NFS volumes instead of PV/PVC resources. Why? Fewer Kubernetes objects, no StorageClass to maintain, no provisioner to keep running. The `nfs_server` variable is shared across all 70+ stacks via Terragrunt — if I ever move NFS to a different IP, one variable change propagates everywhere.

# Infrastructure as Code — Terragrunt

The entire cluster is managed through Terragrunt with **per-service state isolation**. Each of the 70+ services has its own `terraform.tfstate`. This is the single most important architectural decision in the whole setup.

![Terragrunt structure](/images/21-home-lab-v3-terragrunt.svg)

```
stacks/
├── platform/          # Core infra (~22 modules)
│   └── modules/
│       ├── traefik/
│       ├── authentik/
│       ├── monitoring/
│       └── ...
├── blog/              # Individual service stacks
├── nextcloud/
├── immich/
├── servarr/
└── ... (70+ total)
```

Why per-service state? I learned this the hard way. With a monolithic state file, a single corrupted resource blocks all changes. With per-service isolation:

- **Blast radius** — a bad `terraform apply` on the blog stack can't break Nextcloud
- **Speed** — `plan` takes seconds per stack instead of minutes for a monolith
- **Parallelism** — I can apply multiple stacks simultaneously
- **Git blame** — each stack's history is clean and self-contained

Shared configuration flows through `terraform.tfvars` (encrypted via `git-crypt`), which provides NFS server IP, Redis host, DB connection strings, mail config, and Cloudflare credentials to every stack. Terragrunt's root `terragrunt.hcl` handles provider setup, backend config, and variable loading — individual stacks just define resources.

### The Ingress Factory

Every service uses a shared `ingress_factory` module that generates the full Traefik middleware chain. This is how I maintain consistent security posture across 70+ services without copy-pasting middleware config.

![Ingress factory middleware chain](/images/21-home-lab-v3-ingress-factory.svg)

```hcl
module "ingress" {
  source    = "../../modules/kubernetes/ingress_factory"
  host      = "myservice.viktorbarzin.me"
  protected = true   # Authentik forward auth
  anti_ai_scraping = true  # 5-layer defense (default: on)
}
```

One module call gives a service: rate limiting, CrowdSec WAF, anti-AI bot blocking, Authentik SSO (if protected), HSTS, security headers, and analytics injection. When I add a new middleware — like the anti-AI scraping system I built — it propagates to all services on the next `apply`. No per-service configuration drift.

# What's Next

In **Part 2**, I'll cover the Kubernetes platform in depth: Authentik SSO, CrowdSec WAF, the 5-layer anti-AI scraping system, GPU time-slicing with the Tesla T4, and the Kyverno tier-based resource governance.

---

*This is Part 1 of the Home Lab v3 series:*
1. **The Foundation** (this post)
2. *The Platform* (coming soon)
3. *The Services* (coming soon)
4. *Sofia & Operations* (coming soon)
