---
title: "21 Home Lab v3 - The Foundation"
date: 2026-03-01T00:00:00Z
author: "Viktor Barzin"
description: "My home lab has grown from ~20 services to 70+. This is part 1 of a series covering the hardware, network, and platform that runs it all. Deep dive into a Dell R730 running Proxmox, Kubernetes on bare-metal VMs, a 3-VLAN network with pfSense, and the Terragrunt-based IaC that ties it together."
tags: ["home", "lab", "proxmox", "kubernetes", "k8s", "pfsense", "network", "vlan", "metallb", "traefik", "terragrunt", "terraform", "infrastructure", "self-hosting", "dell", "r730", "tesla", "t4", "gpu", "ups", "truenas", "nfs"]
firstImgUrl: "https://viktorbarzin.me/images/21-home-lab-v3-overview.png"
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

<!-- DIAGRAM: high-level-overview
Title: "Home Lab v3 — Overview"
Show:
- Internet cloud at top
- Cloudflare (DNS + Tunnel) in front
- pfSense firewall box
- 3 VLANs branching out: Home (192.168.1.0/24), Management (10.0.10.0/24), Kubernetes (10.0.20.0/24)
- Proxmox hypervisor containing: k8s-master, k8s-node1 (GPU icon), k8s-node2, k8s-node3, k8s-node4, TrueNAS
- Docker Registry Cache box on the side
- WireGuard + Headscale VPN tunnels going out
- Arrow to "HA Sofia" remote site
-->

![High-level architecture](/images/21-home-lab-v3-overview.png)

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

The R730 runs everything — 12 VMs on a single Proxmox host. Overkill for most services, but the 44 threads and 142GB RAM mean I never have to think about resource pressure.

The Tesla T4 was a later addition for running LLMs (Ollama), photo ML (Immich), and NVR inference (Frigate). It's PCIe-passthrough to `k8s-node1` and shared via NVIDIA's time-slicing.

## UPS Monitoring

The Huawei UPS2000 is monitored via SNMP with a custom Prometheus exporter config pulling Huawei-proprietary MIB OIDs for apparent/active power.

<!-- DIAGRAM: ups-monitoring
Title: "UPS → Prometheus → Grafana"
Show:
- Huawei UPS2000 box with "SNMP v1" arrow
- SNMP Exporter pod in k8s
- Arrow to Prometheus
- Arrow to Grafana dashboard showing: battery %, runtime estimate, load %, input/output voltage
-->

![UPS monitoring pipeline](/images/21-home-lab-v3-ups.png)

# Virtualization — Proxmox

Moved from VMware ESXi to Proxmox in 2023. Main reasons: no licensing cost, better API, cloud-init support for automated VM provisioning.

<!-- DIAGRAM: proxmox-vms
Title: "Proxmox VM Layout"
Show as a grid/table layout:
- pfSense (VMID 101) — 8C/16G — Gateway
- devvm (102) — 16C/8G — Dev
- home-assistant (103) — 8C/16G — HA London
- k8s-master (200) — 8C/16G — Control plane
- k8s-node1 (201) — 16C/24G+GPU — GPU worker
- k8s-node2 (202) — 8C/16G — Worker
- k8s-node3 (203) — 8C/16G — Worker
- k8s-node4 (204) — 8C/16G — Worker
- docker-registry (220) — 4C/4G — Registry cache
- truenas (9000) — 16C/16G — NFS
- Windows10 (300) — 16C/8G — Windows
Color-code: blue=k8s, green=infrastructure, gray=other
-->

![Proxmox VM layout](/images/21-home-lab-v3-proxmox.png)

### Node Rebuild Automation

K8s nodes are cattle, not pets. The rebuild process:

1. `kubectl drain` + `kubectl delete node`
2. Destroy VM in Terraform
3. Fresh `kubeadm token create --print-join-command`
4. Create VM from cloud-init template → auto-joins cluster

The entire process is in `stacks/infra/main.tf`. Tokens expire after 24h so you generate them right before provisioning.

# Network

## Three VLANs

<!-- DIAGRAM: network-topology
Title: "Network Topology"
Show:
- ISP router at top → pfSense WAN (192.168.1.2)
- pfSense with 3 interfaces branching:
  1. Home Network (192.168.1.0/24) — labeled "Physical devices, Proxmox host .127"
  2. VLAN 10 — Management (10.0.10.0/24) — labeled "TrueNAS .15, devvm"
  3. VLAN 20 — Kubernetes (10.0.20.0/24) — labeled "k8s-master .100, DNS .101, MetalLB .200-.220"
- Proxmox bridges: vmbr0 (physical) and vmbr1 (VLAN-aware trunk)
- WireGuard tunnel (10.3.2.0/24) going out from pfSense
- Headscale mesh (100.64.x.x) overlay
-->

![Network topology](/images/21-home-lab-v3-network.png)

| Network | Subnet | Purpose |
|---------|--------|---------|
| Home | 192.168.1.0/24 | Physical devices, Proxmox host |
| Management (VLAN 10) | 10.0.10.0/24 | TrueNAS NFS, dev VM, out-of-band access |
| Kubernetes (VLAN 20) | 10.0.20.0/24 | All k8s nodes, MetalLB pool (.200-.220), DNS (.101) |
| WireGuard | 10.3.2.0/24 | Site-to-site VPN |
| Headscale | 100.64.x.x | Mesh VPN overlay |

Proxmox uses two bridges: `vmbr0` on the physical NIC for the home network, and `vmbr1` as a VLAN-aware trunk carrying VLAN 10 and 20 to the VMs.

## pfSense

pfSense CE 2.7.2 runs as a VM (VMID 101). 167 firewall rules, 154 NAT rules. Key packages:

- **FRR** — BGP/OSPF (not actively used, but ready)
- **Snort IDS** — intrusion detection on WAN
- **WireGuard** — VPN server, 10.3.2.0/24
- **Tailscale** — joins the Headscale mesh
- **FreeRADIUS** — 802.1X if I ever wire it up
- **Kea DHCP** — DHCP for all 3 networks

## DNS — Split Horizon

<!-- DIAGRAM: dns-split-horizon
Title: "Split-Horizon DNS"
Show:
- External queries → Cloudflare (viktorbarzin.me) → points to Cloudflare Tunnel or pfSense WAN
- Internal queries → Technitium DNS (10.0.20.101, viktorbarzin.lan) → resolves to internal IPs
- pfSense NAT: forwards port 53 from WAN to Technitium for external zones that need self-hosted resolution
-->

![DNS split-horizon](/images/21-home-lab-v3-dns.png)

- **External**: Cloudflare manages `viktorbarzin.me`. Services are proxied through Cloudflare Tunnel or direct WAN.
- **Internal**: Technitium DNS at `10.0.20.101` handles `viktorbarzin.lan` and overrides for internal resolution.

## Docker Registry Pull-Through Cache

Every `docker pull` on the cluster goes through a local cache at `10.0.20.10`. Five upstream registries mirrored:

| Port | Registry |
|------|----------|
| 5000 | docker.io |
| 5010 | ghcr.io |
| 5020 | quay.io |
| 5030 | registry.k8s.io |
| 5040 | reg.kyverno.io |
| 5050 | Private R/W registry |

All fronted by nginx. Containerd on every node has `hosts.toml` pointing to the cache. Benefits: faster pulls, resilience against Docker Hub rate limits and outages, works offline for cached images.

## Load Balancing — MetalLB

MetalLB runs in Layer-2 mode, advertising IPs from `10.0.20.200` to `10.0.20.220`. Services that need a dedicated IP (Traefik ingress, DNS, mail) get one from this pool.

# Storage — TrueNAS + NFS

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

Inline NFS volumes (no PV/PVC) — simpler, fewer resources, works fine for a single-node NFS server.

# Infrastructure as Code — Terragrunt

The entire cluster is managed through Terragrunt with per-service state isolation. Each of the 70+ services has its own `terraform.tfstate`.

<!-- DIAGRAM: terragrunt-structure
Title: "Terragrunt Stack Structure"
Show:
- Root: terragrunt.hcl (providers, backend, variable loading)
- stacks/ directory branching into:
  - platform/ (core infra: traefik, authentik, monitoring, crowdsec, etc.)
  - blog/, nextcloud/, immich/, servarr/, etc. (individual services)
- Each stack box shows: terragrunt.hcl + main.tf + secrets/ symlink
- Arrow from terraform.tfvars → all stacks (shared variables)
- State files: state/stacks/<service>/terraform.tfstate
-->

![Terragrunt structure](/images/21-home-lab-v3-terragrunt.png)

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

Key benefits:
- **Blast radius isolation** — a bad state in one service doesn't affect others
- **Shared variables** — `terraform.tfvars` provides NFS server, Redis host, DB hosts, mail config to all stacks
- **Secrets** — `git-crypt` encrypts `terraform.tfvars` and `secrets/` directory transparently

### The Ingress Factory

Every service uses a shared `ingress_factory` module that generates the full Traefik middleware chain:

<!-- DIAGRAM: ingress-factory
Title: "Ingress Factory — What every service gets"
Show as a pipeline/chain:
Request → Rate Limit (10 avg/50 burst) → CrowdSec WAF → Anti-AI Bot Block → Authentik Auth (if protected) → HSTS + Security Headers → Rybbit Analytics Injection → Service
Each step as a box in a horizontal chain
Label: "One Terraform module, applied to all 70+ services"
-->

![Ingress factory middleware chain](/images/21-home-lab-v3-ingress-factory.png)

```hcl
module "ingress" {
  source    = "../../modules/kubernetes/ingress_factory"
  host      = "myservice.viktorbarzin.me"
  protected = true   # Authentik forward auth
  anti_ai_scraping = true  # 5-layer defense (default: on)
}
```

One module call. Security posture changes propagate to all services.

# What's Next

In **Part 2**, I'll cover the Kubernetes platform in depth: Authentik SSO, CrowdSec WAF, the 5-layer anti-AI scraping system, GPU time-slicing with the Tesla T4, and the Kyverno tier-based resource governance.

---

*This is Part 1 of the Home Lab v3 series:*
1. **The Foundation** (this post)
2. *The Platform* (coming soon)
3. *The Services* (coming soon)
4. *Sofia & Operations* (coming soon)
