# Blog Modernization

## What This Is

Viktor Barzin's personal blog at viktorbarzin.me, built with Hugo and the hugo-theme-nix theme. It's a static site built in CI (Woodpecker), pushed as a Docker image to DockerHub, and deployed to a home Kubernetes cluster. The CI build is currently broken, preventing any new content from being published.

## Core Value

The blog builds successfully in CI so new content can be published to viktorbarzin.me.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Fix Dockerfile to use a modern Hugo version that builds the site successfully
- [ ] Remove stray files that don't belong in the repo (`__pycache__/`, `*.xml` drawio files, `ideas.txt`, `hooks/` with hardcoded password)
- [ ] Woodpecker CI pipeline passes end-to-end (build image → push to DockerHub → restart k8s deployment)
- [ ] Site loads correctly in the browser after deployment

### Out of Scope

- Theme updates or redesign — keeping hugo-theme-nix as-is
- Hugo config modernization (toml→yaml, GA4 migration, etc.) — not needed to unblock CI
- Adding new articles — separate task after CI is green
- Converting theme to git submodule — not needed now

## Context

- **Stack**: Hugo static site generator → NGINX serving in Docker → Kubernetes
- **CI**: Woodpecker CI, config in `.woodpecker.yml`
- **Deploy target**: k8s namespace `website`, deployment `blog` on cluster at 10.0.20.100:6443
- **Docker image**: `viktorbarzin/blog` on DockerHub
- **Root cause of crash**: Dockerfile uses `debian:latest` and installs Hugo via `apt-get`, which provides an outdated Hugo version incompatible with the site's config/content
- **Security issue**: `hooks/build` contains a hardcoded LetsEncrypt password that must be removed from the repo

## Constraints

- **Tech stack**: Hugo + NGINX + Docker — no framework changes
- **CI**: Woodpecker — keep existing pipeline structure
- **Deployment**: Same k8s cluster and namespace

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use official Hugo Docker image for builds | Debian apt Hugo is severely outdated; official image stays current | — Pending |
| Delete all stray files | `__pycache__`, drawio XMLs, `ideas.txt`, `hooks/` with leaked password don't belong | — Pending |

---
*Last updated: 2026-02-28 after initialization*
