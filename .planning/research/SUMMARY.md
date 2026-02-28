# Project Research Summary

**Project:** Hugo Blog CI/CD Modernization (viktorbarzin.me)
**Domain:** Hugo static site — Docker multi-stage build + Woodpecker CI + Kubernetes deploy
**Researched:** 2026-02-28
**Confidence:** HIGH

## Executive Summary

This is a repair project, not a greenfield build. The blog exists, content exists, the Kubernetes cluster is running, and the Woodpecker CI pipeline is structurally correct. The single root cause of the broken CI build is the Dockerfile using `debian:latest` + `apt-get install hugo`, which delivers Hugo 0.111.3 (Debian bookworm) — far behind the current release (0.157.0) and incompatible with the site's templates. The fix is a targeted Dockerfile rewrite: replace the build stage with `ghcr.io/gohugoio/hugo:v0.157.0` (the official Hugo GHCR image), and replace the NGINX serving stage from `byjg/nginx-extras:latest` (unmaintained, breaks with `nginx:alpine`) to `nginx:1.28.2-alpine`. No structural changes to CI, Kubernetes, or site content are needed.

The research uncovered two compounding problems that must be addressed alongside the Hugo image fix. First, `configs/nginx.conf` uses the `more_set_headers` directive from the `headers-more-nginx-module`, which is bundled in `byjg/nginx-extras` but absent from standard `nginx:alpine`. Switching to `nginx:alpine` without removing this directive will cause the container to fail on startup with an "unknown directive" error. The correct fix is to delete the single `more_set_headers 'Server: less';` line — `server_tokens off;` already suppresses the version string, making this directive cosmetic security theater. Second, upgrading Hugo to v0.157.0 triggers a hard breaking change: `.Site.Author` was removed in Hugo v0.156.0, and the bundled `hugo-theme-nix` theme uses it in `rss.html`. This must be overridden by creating `layouts/_default/rss.html` before the build will succeed.

The security concern is independent but urgent: `hooks/build` contains a plaintext `LETSENCRYPT_PASS` credential committed to git history. This file must be deleted and the credential rotated. A secondary config issue — `taxonomyTerm` in `disableKinds` (renamed to `term` in Hugo v0.73) — produces warnings on newer Hugo. Both are trivial to fix in the same pass. The total scope of this milestone is: fix four files (Dockerfile, nginx.conf, config.toml, rss.html override), delete three artifact files/directories, and update .gitignore. Everything else is polish.

## Key Findings

### Recommended Stack

The current multi-stage Docker build pattern is correct and should be preserved. Only the base images need to change. The build stage should use `ghcr.io/gohugoio/hugo:v0.157.0` — the official Hugo project image on GHCR (not Docker Hub, which has been abandoned since 2017 at v0.31). The serve stage should use `nginx:1.28.2-alpine`. Both images must be pinned to explicit version tags for reproducible builds; `latest` tags are explicitly anti-recommended for either stage.

**Core technologies:**
- `ghcr.io/gohugoio/hugo:v0.157.0`: Hugo build stage — official image from gohugoio; Alpine-based; ships Extended edition with Dart Sass, Git, Node.js; updated on every Hugo release; no apt lag
- `nginx:1.28.2-alpine`: NGINX serve stage — official Docker Library image; ~25 MB Alpine base; stable channel; maintained by nginxinc; replaces unmaintained `byjg/nginx-extras`
- `woodpeckerci/plugin-docker-buildx`: CI build step — already in use, no changes needed; `auto_tag: true` already configured
- Kubernetes + Woodpecker: Deploy pipeline — annotation PATCH rolling restart pattern is correct; no changes needed to `.woodpecker.yml` or `kubernetes.yaml`

### Expected Features

This milestone is a CI/CD repair, not a feature build. "Features" are pipeline capabilities and repo health properties.

**Must have (P1 — CI broken without these):**
- Pin Hugo to `ghcr.io/gohugoio/hugo:v0.157.0` in Dockerfile — root cause of broken build
- Replace `more_set_headers` with `server_tokens off` in nginx.conf — required for `nginx:alpine` compatibility
- Override `rss.html` in `layouts/_default/` to fix `.Site.Author` removal — required for Hugo v0.157.0 build success
- Delete `hooks/` directory — removes plaintext `LETSENCRYPT_PASS` from git-tracked files
- Delete stray artifacts: `__pycache__/`, `08-nesting-openvpn-drawio.xml`, `11-hard-dist-layout.xml`, `ideas.txt`
- Update `.gitignore` to cover `__pycache__/`, `*.py[cod]`, `.hugo_build.lock`, `.DS_Store`
- Fix `disableKinds` in config.toml: replace `"taxonomyTerm"` with `"term"`

**Should have (P2 — polish, same pass):**
- Pin NGINX to explicit version (`nginx:1.28.2-alpine`) rather than `stable-alpine` tag
- Tighten `.dockerignore` to exclude stray file patterns
- Add `--minify` to Hugo build command in Dockerfile
- Rotate the `LETSENCRYPT_PASS` credential (infra task, independent of repo fix)

**Defer (v2+ — separate milestones):**
- Hugo config migration (TOML to YAML) — low value, introduces risk
- GA4 migration (UA-132992428-1 is dead GA3) — content concern, not CI
- Theme modernization — hugo-theme-nix is old but functional; high effort, high risk
- Multi-platform Docker builds (arm64/amd64) — cluster is x86-only, unnecessary complexity

### Architecture Approach

The architecture is a textbook Hugo static site CI/CD pipeline: source code (Markdown + theme) lives in git; a Woodpecker pipeline triggers on push; the pipeline runs a multi-stage Docker build (Hugo → NGINX), pushes the image to DockerHub, then signals Kubernetes to rolling-restart the blog deployment via an annotation PATCH to the k8s API. The Kubernetes layer (3-replica deployment, ClusterIP service, nginx-ingress, TLS at ingress level, Prometheus sidecar) is correct and requires no changes. The only component that requires modification is the Dockerfile and the files it consumes.

**Major components:**
1. Hugo build stage (Docker) — compiles Markdown + theme to static HTML/CSS/JS in `/project/public/`
2. NGINX serve stage (Docker) — copies `/project/public/` into an Alpine NGINX image; serves with security headers, HSTS, stub_status
3. Woodpecker CI pipeline — build-image step (docker-buildx plugin) + update-deployment step (curl PATCH to k8s API)
4. Kubernetes deployment — 3-replica Deployment with `imagePullPolicy: Always`; rolling restart triggered by `restartedAt` annotation
5. Kubernetes ingress — nginx-ingress class handles TLS termination at `viktorbarzin.me`; blog containers serve plain HTTP internally

### Critical Pitfalls

1. **`more_set_headers` breaks on `nginx:alpine`** — Delete the `more_set_headers 'Server: less';` line from `configs/nginx.conf` before switching nginx images. Standard `nginx:alpine` does not include `headers-more-nginx-module`. Container will fail to start with "unknown directive" error if this line remains. Validation: run `docker run --rm <image> nginx -t`.

2. **`.Site.Author` removed in Hugo v0.156.0 — hard build failure** — Create `layouts/_default/rss.html` that overrides the broken theme partial before running `hugo` with v0.157.0. The bundled `hugo-theme-nix/layouts/_default/rss.html` uses `.Site.Author.email`, which became a hard error in v0.156.0. This is not a warning; it fails the build.

3. **Docker Hub `gohugoio/hugo` image is abandoned (last updated 2017, v0.31)** — Use `ghcr.io/gohugoio/hugo:v0.157.0` from GHCR, not `gohugoio/hugo` from Docker Hub. The Docker Hub image looks official but is 9 years stale.

4. **Hardcoded `LETSENCRYPT_PASS` in git history** — Delete `hooks/build` and rotate the credential. The secret persists in `git log -p` even after deletion; assess whether history scrubbing is necessary based on repo visibility.

5. **`taxonomyTerm` kind renamed in Hugo v0.73** — In `config.toml`, `disableKinds` must use `"term"` not `"taxonomyTerm"`. The old name is unrecognized on Hugo >= 0.73, producing WARN log spam and potentially failing to disable the intended page type.

## Implications for Roadmap

Based on research, a two-phase structure is recommended: security/hygiene first (independent of the build fix), then the core build fix with its cascading config dependencies.

### Phase 1: Security and Repo Hygiene

**Rationale:** The hardcoded secret (`LETSENCRYPT_PASS`) and stray files are independent of the Dockerfile fix. Cleaning them first ensures they cannot be accidentally included in the same commit as the build fix, and provides a clean working state. The `.gitignore` update should happen in this phase to prevent recurrence.

**Delivers:** A repo with no exposed credentials in tracked files, no stray artifacts, and a `.gitignore` that prevents their return.

**Addresses:** Delete `hooks/` (P1 security), delete `__pycache__/`, `*.xml`, `ideas.txt` (P1 hygiene), update `.gitignore` (P1 prevention).

**Avoids:** Accidentally committing or re-introducing the `LETSENCRYPT_PASS` secret during the Dockerfile change phase; having stray files in the Docker build context.

### Phase 2: Dockerfile and Config Modernization

**Rationale:** This is the root cause fix. It requires four coordinated changes: Dockerfile base image swap, nginx.conf directive removal, config.toml `disableKinds` fix, and the `layouts/_default/rss.html` override for `.Site.Author`. These must be validated together because a failure in any one of them will break the build.

**Delivers:** A passing CI build, a successful Docker image push to DockerHub, a rolling restart of the k8s deployment, and a live site at viktorbarzin.me with new content.

**Uses:** `ghcr.io/gohugoio/hugo:v0.157.0` (STACK.md), `nginx:1.28.2-alpine` (STACK.md), `--minify` build flag (FEATURES.md P2).

**Implements:** Multi-stage Docker build (builder + runtime), NGINX configuration without `more_set_headers`, Hugo config with correct taxonomy kinds, theme override for deprecated `.Site.Author`.

**Avoids:**
- `more_set_headers` directive breaking nginx startup (PITFALLS Pitfall 1)
- `.Site.Author` removal causing hard build failure (PITFALLS Hugo API Deprecations)
- Stale Docker Hub `gohugoio/hugo` image (PITFALLS Pitfall 3)
- Unpinned `latest` tags breaking reproducibility

### Phase Ordering Rationale

- Security cleanup before the build fix ensures no secret leaks in transition commits
- All four build-related changes (Dockerfile, nginx.conf, config.toml, layouts override) must land together because they are interdependent — a partial application will produce a broken build
- `.dockerignore` tightening is a P2 follow-up that can be done in the same phase or immediately after validation
- No k8s manifest changes are needed, so the deploy layer is unchanged

### Research Flags

Phases with standard patterns — no additional research needed:
- **Phase 1 (Security/Hygiene):** File deletion and `.gitignore` update; no research needed; purely mechanical.
- **Phase 2 (Dockerfile/Config fix):** All patterns are well-documented and verified. The Hugo GHCR image, nginx:alpine, multi-stage Dockerfile, and the specific Hugo API deprecations are confirmed against official sources. No additional research needed before implementation.

Potential validation during implementation:
- **`ghcr.io/gohugoio/hugo:v0.157.0` entrypoint behavior:** The STACK.md notes the image runs as non-root and may need `--noBuildLock`. Validate with `docker run --rm ghcr.io/gohugoio/hugo:v0.157.0 --help` before relying on entrypoint assumptions in the Dockerfile.
- **`layouts/_default/rss.html` override scope:** Confirm that placing the override in `layouts/_default/` correctly shadows `themes/hugo-theme-nix/layouts/_default/rss.html` before assuming the fix works.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official images verified against GHCR and Docker Library; versions cross-checked against Hugo release tags and nginx stable channel; Debian apt lag confirmed against packages.debian.org |
| Features | HIGH | Project scope is concrete repair work; all "features" are observable from existing codebase; no ambiguity about what must change |
| Architecture | HIGH | Architecture observed directly from Dockerfile, .woodpecker.yml, configs/kubernetes.yaml, configs/nginx.conf; patterns verified against official Kubernetes and Woodpecker docs |
| Pitfalls | HIGH | Hugo API deprecations verified against official release notes; `more_set_headers` module dependency confirmed via nginx-extras source; Docker Hub abandonment confirmed via direct inspection |

**Overall confidence:** HIGH

### Gaps to Address

- **Hugo GHCR image non-root user behavior:** The official `ghcr.io/gohugoio/hugo` image runs as a non-root user. The `WORKDIR /project` and `COPY . .` approach may need permission adjustments. Validate with a test build before CI push.
- **`LETSENCRYPT_PASS` credential status:** Research cannot determine if the credential is still active or whether the repo is public. The team must assess whether git history scrubbing is necessary beyond deleting the file from tracked files.
- **CSP headers in nginx.conf:** Content-Security-Policy headers are commented out in the current config. Research flags this as a minor security gap but did not determine whether re-enabling them would break Disqus, Google Analytics, or other third-party embeds. Leave commented for this milestone; evaluate separately.
- **Woodpecker `update-deployment` silent failure:** The existing `curl | head` pipeline in `.woodpecker.yml` swallows curl errors. Adding `curl -f` would surface k8s API errors. This is a P2 improvement noted in PITFALLS.md but not a blocker.

## Sources

### Primary (HIGH confidence)
- `https://github.com/gohugoio/hugo/pkgs/container/hugo` — official Hugo GHCR image; v0.157.0 confirmed current (published 2026-02-25)
- `https://github.com/gohugoio/hugo/releases` — Hugo release history; v0.156.0 hard-removes `.Site.Author`; v0.73.0 renames `taxonomyTerm`
- `https://github.com/docker-library/official-images/blob/master/library/nginx` — nginx stable 1.28.2 confirmed
- `https://github.com/byjg/docker-nginx-extras` — last release 1.26 on 2024-09-09; `HttpHeadersMore` module confirmed
- `https://packages.debian.org/search?keywords=hugo` — Debian bookworm provides Hugo 0.111.3; trixie provides 0.131.0
- Direct codebase inspection: `Dockerfile`, `.woodpecker.yml`, `configs/nginx.conf`, `configs/kubernetes.yaml`, `config.toml`, `hooks/build`, `themes/hugo-theme-nix/layouts/_default/rss.html`

### Secondary (MEDIUM confidence)
- `https://docker.hugomods.com/docs/tags/` — hugomods tag naming; CI image variants
- `https://hugomods.com/docs/docker/` — multi-stage build patterns with hugomods images
- `https://woodpecker-ci.org/docs/usage/secrets` — Woodpecker secrets syntax (verified, matches existing .woodpecker.yml)
- `https://github.com/openresty/headers-more-nginx-module` — `more_set_headers` directive; absent from standard nginx builds

### Tertiary (LOW confidence)
- None identified — all findings supported by at least MEDIUM confidence sources

---
*Research completed: 2026-02-28*
*Ready for roadmap: yes*
