# Stack Research

**Domain:** Hugo static site CI/CD (Docker build + NGINX serve)
**Researched:** 2026-02-28
**Confidence:** HIGH

## Problem Statement

The current Dockerfile uses `debian:latest` + `apt-get install hugo`, which gives Hugo
0.111.3 on Debian bookworm (2023 vintage). This is the root cause of the broken CI build.
The fix: replace the build stage with a purpose-built Hugo Docker image that ships a
current, pinned version.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `ghcr.io/gohugoio/hugo` | `v0.157.0` | Build stage (Hugo binary) | Official Hugo project image; builds extended edition with Go 1.26, Alpine 3.22, Dart Sass 1.79.3, git, Node.js, npm. Updated with every Hugo release. No dependency on OS package manager lag. |
| `nginx:stable-alpine` | `1.28.2-alpine` | Serve stage (static files) | Official Docker Library image; Alpine base minimises image size (~25 MB); stable channel is production-tested; maintained by nginxinc. |

### Supporting Tools (pre-installed in `ghcr.io/gohugoio/hugo`)

| Tool | Version (bundled) | Purpose | When Needed |
|------|-------------------|---------|-------------|
| Go | 1.26 | Hugo Modules | Only if site uses `go.sum` modules; not needed here |
| Dart Sass | 1.79.3 | SCSS compilation | Only if theme uses `.scss` source; hugo-theme-nix uses plain CSS |
| Git | latest Alpine | `--enableGitInfo` / submodule fetch | Not needed here (theme is vendored, no git metadata in posts) |
| Node.js + npm | LTS | PostCSS / asset pipelines | Not needed here |

Note: the `ghcr.io/gohugoio/hugo` image is intentionally full-featured. All tools are
present but unused tools add zero runtime cost because only the `public/` directory is
copied to the serve stage.

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `woodpeckerci/plugin-docker-buildx` | Multi-arch Docker image builds | Already in use; no change needed |
| `woodpeckerci/plugin-git` | Repository clone before build | Already in use; use `submodules: false` since theme is vendored |

## Installation / Dockerfile Pattern

The recommended multi-stage Dockerfile:

```dockerfile
# Stage 1: Build
# Pin to a specific version to ensure reproducible builds.
# Update this tag intentionally when upgrading Hugo.
FROM ghcr.io/gohugoio/hugo:v0.157.0 AS builder

WORKDIR /project
COPY . .

# The official image expects the project in /project and runs as non-root.
# Use --noBuildLock to avoid lock file issues in read-only filesystems.
RUN hugo --minify --source /project --destination /project/public

# Stage 2: Serve
FROM nginx:1.28.2-alpine

# Remove default nginx content
RUN rm -rf /usr/share/nginx/html/*

COPY --from=builder /project/public /usr/share/nginx/html
COPY configs/nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
```

Key decisions:
- Pin `ghcr.io/gohugoio/hugo` to an explicit version tag (`v0.157.0`), not `latest`.
  This makes CI builds reproducible and controlled upgrades intentional.
- Pin `nginx` to `1.28.2-alpine`, not `stable-alpine`, for the same reason.
- Drop `byjg/nginx-extras` — see "What NOT to Use" section.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `ghcr.io/gohugoio/hugo:v0.157.0` | `hugomods/hugo:ci` | Use hugomods if you need PostCSS, PurgeCSS, AsciiDoc, or Pandoc processing at build time. The hugomods image is actively maintained with 140+ variants covering Dart Sass, Node.js LTS, and non-root configurations. For this blog none of those are needed. |
| `ghcr.io/gohugoio/hugo:v0.157.0` | `debian:latest` + `apt-get install hugo` | Never for CI/CD. Apt gives 0.111.3 on Debian bookworm — three years behind current. |
| `nginx:1.28.2-alpine` | `nginx:1.29.5-alpine` (mainline) | Use mainline only when you specifically need a feature added after 1.28. For a static blog the stable channel is sufficient and preferred. |
| `nginx:1.28.2-alpine` | `byjg/nginx-extras:latest` | Use nginx-extras only if you need HttpHeadersMore, embedded Lua, or XSLT. See below. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `debian:latest` + `apt-get install hugo` | Provides Hugo 0.111.3 (2023) on Debian bookworm. Blocks on package cache age, not Hugo release schedule. `latest` tag itself is a moving target. | `ghcr.io/gohugoio/hugo:v0.157.0` |
| `byjg/nginx-extras:latest` | Last release (1.26) was September 2024. Uses an unofficial build of nginx compiled from source with many modules not needed for a static site. Larger attack surface, slower base updates. The only feature it provides that this site uses is `more_set_headers` (for `Server: less` header) — this can be replaced with a standard `add_header` directive. | `nginx:1.28.2-alpine` |
| `hugomods/hugo:latest` (unpinned) | `latest` resolves to the full-fat image with Extended + Go + Node.js + Git. Larger than needed for this site, and unpinned tags break reproducibility. | `hugomods/hugo:ci` (if using hugomods) or pinned `ghcr.io/gohugoio/hugo:v0.157.0` |
| Hugo Extended requirement | hugo-theme-nix requires only Hugo >= 0.20 and uses no SCSS; the standard build is sufficient. Extended edition is fine (the official image builds extended by default) but Extended is not a hard requirement. | Either works; official image always builds extended |

## Stack Patterns by Variant

**If theme uses SCSS (not applicable here, but for future themes):**
- Use `ghcr.io/gohugoio/hugo` (already extended by default)
- Or `hugomods/hugo:base` (Alpine, Extended, minimal)
- Because Extended edition includes LibSass and WebP conversion

**If site uses Hugo Modules (`go.sum` present):**
- Use `ghcr.io/gohugoio/hugo` (includes Go 1.26)
- Or `hugomods/hugo` with Go variant
- Because module downloads require the Go toolchain

**If build pipeline needs PostCSS / PurgeCSS:**
- Use `hugomods/hugo:node-lts` or `hugomods/hugo:ci`
- Because official gohugoio image includes Node.js/npm for this case too

**Current blog (hugo-theme-nix, vendored, plain CSS):**
- `ghcr.io/gohugoio/hugo:v0.157.0` is the correct and sufficient choice

## Version Compatibility

| Component | Version | Compatibility Notes |
|-----------|---------|---------------------|
| `ghcr.io/gohugoio/hugo:v0.157.0` | Hugo 0.157.0 | Requires hugo-theme-nix >= 0.20 (theme minimum is 0.20, so fully compatible) |
| `ghcr.io/gohugoio/hugo:v0.157.0` | Alpine 3.22 | Base OS; no conflicts for build-only stage |
| `nginx:1.28.2-alpine` | Alpine 3.20.x | Serve-only stage; no Hugo dependency |
| Woodpecker `docker-buildx` plugin | any | Handles multi-arch; no version constraint from Hugo image |

## nginx.conf Compatibility Note

The existing `nginx.conf` uses `more_set_headers 'Server: less'` — a directive from the
`headers-more-nginx-module` that ships in `byjg/nginx-extras` but not in `nginx:alpine`.

**Fix:** Replace with the standard directive:
```nginx
add_header Server "less" always;
```
Or remove the custom server header entirely (it provides minimal security value while
requiring a non-standard nginx build).

## Sources

- `https://github.com/gohugoio/hugo/pkgs/container/hugo` — official Hugo GHCR image; confirmed v0.157.0 is latest (published 2026-02-25); HIGH confidence
- `https://raw.githubusercontent.com/gohugoio/hugo/master/Dockerfile` — official Dockerfile; confirmed Extended edition, Alpine 3.22, Go 1.26, Dart Sass 1.79.3, git, Node.js; HIGH confidence
- `https://github.com/gohugoio/hugo/releases` — latest release v0.157.0 (2026-02-25); HIGH confidence
- `https://github.com/docker-library/official-images/blob/master/library/nginx` — nginx stable 1.28.2, mainline 1.29.5, alpine variants confirmed; HIGH confidence
- `https://docker.hugomods.com/docs/tags/` — hugomods tag naming convention and CI/CD image variants; MEDIUM confidence (authoritative project docs)
- `https://github.com/byjg/docker-nginx-extras` — last release 1.26 on 2024-09-09; HttpHeadersMore module confirmed; HIGH confidence
- `https://packages.debian.org/search?keywords=hugo` — debian bookworm (latest) provides Hugo 0.111.3; trixie provides 0.131.0; HIGH confidence
- `https://github.com/LordMathis/hugo-theme-nix/blob/master/theme.toml` — minimum Hugo version 0.20; no Extended requirement; HIGH confidence

---
*Stack research for: Hugo blog CI/CD modernization (Docker build + NGINX serve)*
*Researched: 2026-02-28*
