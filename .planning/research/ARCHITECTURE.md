# Architecture Research

**Domain:** Hugo static site blog — Docker multi-stage build + CI/CD to Kubernetes
**Researched:** 2026-02-28
**Confidence:** HIGH (current architecture is observable from repo; patterns verified via official sources)

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        SOURCE LAYER                              │
│  ┌─────────────┐  ┌───────────────┐  ┌────────────────────┐     │
│  │ content/    │  │ themes/       │  │ config.toml        │     │
│  │ *.md files  │  │ hugo-theme-nix│  │ (site config)      │     │
│  └──────┬──────┘  └───────┬───────┘  └─────────┬──────────┘     │
│         └─────────────────┴───────────────────── ┘              │
└──────────────────────────────────────────────────────────────────┘
                              │
                              │ git push
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                        CI LAYER (Woodpecker)                     │
│                                                                  │
│  Step 1: build-image                                             │
│  ┌────────────────────────────────────────────────────────┐      │
│  │ woodpeckerci/plugin-docker-buildx                      │      │
│  │                                                        │      │
│  │  Stage 1 (builder):                                    │      │
│  │  FROM hugomods/hugo:exts                               │      │
│  │  RUN hugo --minify --gc                                │      │
│  │  → produces /src/public/                               │      │
│  │                                                        │      │
│  │  Stage 2 (runtime):                                    │      │
│  │  FROM byjg/nginx-extras:latest (or nginx:alpine)       │      │
│  │  COPY --from=builder /src/public /var/www/html/        │      │
│  │  COPY configs/nginx.conf /etc/nginx/                   │      │
│  │  → produces final image (~20MB vs ~300MB)              │      │
│  └───────────────────────┬────────────────────────────────┘      │
│                          │                                       │
│  Step 2: push to DockerHub                                       │
│  viktor barzin/blog:latest + :sha-<commit>                       │
│                          │                                       │
│  Step 3: update-deployment                                       │
│  ┌───────────────────────────────────────────────────────┐       │
│  │ alpine + curl → PATCH k8s API rolling-restart         │       │
│  │ PATCH /apis/apps/v1/namespaces/website/               │       │
│  │        deployments/blog                               │       │
│  │ annotation: kubectl.kubernetes.io/restartedAt         │       │
│  └───────────────────────┬───────────────────────────────┘       │
└──────────────────────────┼───────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                        KUBERNETES LAYER                          │
│  namespace: website                                              │
│                                                                  │
│  ┌──────────────────────────────────────────────────────┐        │
│  │ Deployment: blog (3 replicas)                        │        │
│  │  Container: blog (NGINX serving static HTML)         │        │
│  │  Container: nginx-exporter (Prometheus metrics :9113)│        │
│  └──────────────────────┬───────────────────────────────┘        │
│                         │                                        │
│  ┌──────────────────────▼───────────────────────────────┐        │
│  │ Service: blog                                        │        │
│  │  :80 (http), :443 (https), :9113 (metrics)           │        │
│  └──────────────────────┬───────────────────────────────┘        │
│                         │                                        │
│  ┌──────────────────────▼───────────────────────────────┐        │
│  │ Ingress: blog-ingress                                │        │
│  │  host: viktorbarzin.me → Service:80                  │        │
│  │  TLS: tls-viktorbarzin-secret                        │        │
│  └──────────────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| Hugo build stage | Compile Markdown + theme → static HTML/CSS/JS | `hugomods/hugo:exts` image, `hugo --minify --gc` |
| NGINX runtime stage | Serve static files, security headers, Prometheus stub | `byjg/nginx-extras` (custom server header via `more_set_headers`) |
| `configs/nginx.conf` | NGINX configuration — security headers, HSTS, 301 redirects, stub_status | Baked into image at build time |
| Woodpecker `build-image` step | Run multi-stage Docker build, tag + push to DockerHub | `woodpeckerci/plugin-docker-buildx` |
| Woodpecker `update-deployment` step | Signal k8s to rolling-restart pods with new image | `alpine + curl` PATCH to k8s API |
| Kubernetes Deployment | Run N replicas (currently 3), manage pod lifecycle | Deployment with `imagePullPolicy: Always` |
| Kubernetes Service | Route traffic to pods | ClusterIP Service, ports 80/443/9113 |
| Kubernetes Ingress | TLS termination, route external traffic to Service | nginx-ingress class, TLS secret |
| nginx-prometheus-exporter | Expose NGINX metrics for Prometheus scraping | Sidecar container reading `127.0.0.1:8080/nginx_status` |

## Recommended Project Structure

```
Website/
├── content/                  # Hugo content (Markdown posts)
│   ├── blog/                 # Blog posts
│   └── about-me.md
├── themes/
│   └── hugo-theme-nix/       # Theme (files, not submodule)
├── layouts/
│   └── shortcodes/           # Custom shortcodes
├── static/                   # Static assets (images, diagrams, favicons)
├── archetypes/               # Hugo archetypes
├── configs/
│   ├── nginx.conf            # NGINX config baked into image
│   └── kubernetes.yaml       # k8s manifests (reference copy)
├── config.toml               # Hugo site config
├── Dockerfile                # Multi-stage build (builder + runtime)
├── .woodpecker.yml           # CI pipeline (build → push → restart)
└── .dockerignore             # Exclude dev artifacts from build context
```

### Structure Rationale

- **configs/**: Groups deployment-related files (nginx.conf, k8s yaml) separately from content; both are consumed at build time not runtime
- **themes/**: Inlined because hugo-theme-nix is not a published module; keeping it in-repo avoids submodule complexity while accepting that theme updates are manual
- **Dockerfile at root**: Required by Woodpecker plugin-docker-buildx which defaults to root Dockerfile

## Architectural Patterns

### Pattern 1: Multi-Stage Docker Build (Builder + Runtime)

**What:** Two Docker stages — first stage runs Hugo to produce `public/`, second stage copies only the built artifacts into a minimal NGINX image. Build tools (Hugo binary, Go) do not appear in the final image.

**When to use:** Always for static site builds. The build stage needs Hugo; the runtime stage only needs a web server.

**Trade-offs:** Final image is small (~20-30MB vs 300MB+ if Hugo stays in); build context transfers to CI must include all source files. The `--minify --gc` flags reduce HTML/CSS output size further.

**Correct pattern:**
```dockerfile
# Stage 1: Build
FROM hugomods/hugo:exts AS builder
COPY . /src
WORKDIR /src
RUN hugo --minify --gc

# Stage 2: Runtime
FROM byjg/nginx-extras:latest
COPY --from=builder /src/public/ /var/www/html/
COPY configs/nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
```

**Why `hugomods/hugo:exts` over `debian:latest + apt install hugo`:**
- `hugomods/hugo:exts` ships the current Hugo Extended release (updated every 30 minutes from Hugo releases)
- `debian:latest` apt installs a severely outdated Hugo (often 2+ major versions behind) — this is the root cause of the current build failure
- `hugomods/hugo:exts` includes Dart Sass, Node.js, npm, git — everything extended Hugo needs

### Pattern 2: Rolling Restart via Annotation PATCH

**What:** Instead of running `kubectl rollout restart`, the CI step PATCHes the pod template annotation `kubectl.kubernetes.io/restartedAt` with the current timestamp. Kubernetes detects the template change and rolls out new pods using the current `imagePullPolicy: Always` to pull the freshly pushed image.

**When to use:** When CI has k8s API access via ServiceAccount token but no kubectl binary.

**Trade-offs:** Correct and idiomatic — this is how `kubectl rollout restart` works internally. Requires the ServiceAccount to have `patch` permission on the deployment in the `website` namespace.

**Current pattern (works correctly):**
```bash
curl -X PATCH \
  https://10.0.20.100:6443/apis/apps/v1/namespaces/website/deployments/blog \
  -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  -H "Content-Type: application/strategic-merge-patch+json" \
  -k \
  -d '{"spec":{"template":{"metadata":{"annotations":{"kubectl.kubernetes.io/restartedAt":"'$(date +%Y-%m-%dT%TZ)'"}}}}}'
```

**Note:** `-k` skips TLS verification because CI accesses the k8s API at an internal IP without a trusted cert. This is acceptable for an internal home cluster but is worth noting.

### Pattern 3: `imagePullPolicy: Always` for Latest-Tag Deployments

**What:** The k8s deployment uses `image: viktorbarzin/blog:latest` with `imagePullPolicy: Always`. Each rolling restart pulls the newest `:latest` from DockerHub.

**When to use:** When CI pushes to `:latest` tag and you want every restart to pick up the new image without changing the manifest.

**Trade-offs:** No image digest pinning means rollback requires re-tagging. For a personal blog this is acceptable. For a production service you'd use immutable SHA tags.

**`auto_tag: true` in plugin-docker-buildx:** This also tags with the git commit SHA (`:sha-<short>`) in addition to `:latest`, giving a retrospective audit trail without needing to change the deployment manifest.

## Data Flow

### Build-to-Deploy Flow

```
Developer writes content (Markdown)
    │
    │ git push → Woodpecker CI triggered
    ▼
[CI: Step 1 — build-image]
    Docker build context sent to buildx
    │
    ▼  Stage 1 (hugomods/hugo:exts)
    COPY . /src
    RUN hugo --minify --gc
    → /src/public/ (HTML, CSS, JS, images)
    │
    ▼  Stage 2 (byjg/nginx-extras)
    COPY /src/public/ → /var/www/html/
    COPY configs/nginx.conf → /etc/nginx/nginx.conf
    → Final image (NGINX + static files only)
    │
    │ docker push → DockerHub
    │ tags: :latest, :sha-<commit>
    │
    ▼
[CI: Step 2 — update-deployment]
    curl PATCH → k8s API 10.0.20.100:6443
    annotation restartedAt = now()
    │
    ▼
[Kubernetes rolling restart]
    Pull new :latest from DockerHub (imagePullPolicy: Always)
    Old pods terminated, new pods started (3 replicas, one at a time)
    │
    ▼
[Ingress: viktorbarzin.me]
    nginx-ingress routes traffic → Service → new pods
    Site live with new content
```

### Request Serving Flow

```
Browser → viktorbarzin.me
    │
    ▼ DNS
[k8s Ingress: nginx-ingress]
    TLS termination (tls-viktorbarzin-secret)
    Route to Service:80
    │
    ▼
[k8s Service: blog :80]
    Load balance across 3 pods
    │
    ▼
[Pod: blog container (NGINX)]
    Serve /var/www/html/ (static files)
    Security headers (HSTS, X-Frame-Options)
    Static asset caching (365d for images/css/js)
    Custom server header via more_set_headers
    │
    ▼
[Pod: nginx-exporter sidecar]
    Read 127.0.0.1:8080/nginx_status
    Expose :9113/metrics (Prometheus format)
```

## Anti-Patterns

### Anti-Pattern 1: Installing Hugo via OS Package Manager in Dockerfile

**What people do:** `FROM debian:latest` then `apt-get install hugo` — this is the current Dockerfile.

**Why it's wrong:** Debian stable ships Hugo that is many major versions behind the current release. Hugo 0.x from Debian repos cannot build sites that use features from Hugo 0.9x+ (template changes, new functions, updated config schema). Build breaks silently or with cryptic template errors.

**Do this instead:** Use the official `hugomods/hugo` Docker image as the builder stage. It tracks Hugo Extended releases and is updated automatically. Pin to a specific version tag (e.g. `hugomods/hugo:exts-0.140.2`) for reproducibility, or use `hugomods/hugo:exts` for always-current.

### Anti-Pattern 2: Hardcoding Secrets in Version-Controlled Scripts

**What people do:** `hooks/build` contains `--build-arg LETSENCRYPT_PASS="MGm2Sh7FYERIbsmND5y5"` committed to the repo.

**Why it's wrong:** The secret is visible in git history to anyone with repo access. It cannot be rotated without rewriting git history. The `LETSENCRYPT_PASS` build arg is not even used in the Dockerfile (the COPY is commented out), so the file serves no purpose.

**Do this instead:** Delete `hooks/` entirely. Secrets used in CI go in Woodpecker secrets (already done correctly for `dockerhub-pat`). Rewrite git history or rotate the credential if the repo is public.

### Anti-Pattern 3: Stray Dev Artifacts in the Build Context

**What people do:** `__pycache__/`, `*.xml` drawio files, `ideas.txt` accumulate in the repo root and get sent in the Docker build context.

**Why it's wrong:** Build context size bloat slows CI. More critically, these files could be accidentally SERVEd if NGINX is misconfigured or if someone adds a catch-all COPY. `.dockerignore` partially mitigates this but the files should not be in the repo at all.

**Do this instead:** Delete non-source files from the repo. Drawio diagrams belong in static/ if they need to be accessible, or out of the repo entirely if they are local tools.

### Anti-Pattern 4: Using `byjg/nginx-extras:latest` Without Pinning

**What people do:** Pull `byjg/nginx-extras:latest` as the runtime image — the current Dockerfile.

**Why it's wrong (LOW confidence — flagged for validation):** `latest` is a moving target. A byjg/nginx-extras update could break the `more_set_headers` directive or change config file paths. Image is built from source (not official nginx), meaning the compilation and module set can change between tags.

**Do this instead:** Pin to a specific NGINX version tag, e.g. `byjg/nginx-extras:1.26`. Validate that `more_set_headers` (from headers-more-nginx-module / OpenResty) is still included. Alternatively migrate to `nginx:1.26-alpine` + a separate nginx-extras module if `more_set_headers` is the only non-standard directive needed. Assessment: `more_set_headers` is used for one line (`Server: less`) — low value for the complexity.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| DockerHub (`viktorbarzin/blog`) | Push from CI via plugin-docker-buildx | Auth via `dockerhub-pat` Woodpecker secret |
| k8s API (10.0.20.100:6443) | PATCH via curl from CI step | Auth via in-pod ServiceAccount token; `-k` skips TLS |
| Disqus | JS embed via Hugo config (`disqusShortname`) | No server-side integration; loaded client-side |
| Google Analytics | GA4 tracking code in theme | `googleAnalytics = "UA-132992428-1"` (UA = legacy GA3, needs migration eventually) |
| Prometheus | nginx-exporter sidecar exposes `:9113/metrics` | Service annotations enable Prometheus scraping |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Hugo build stage → NGINX stage | `COPY --from=builder` in Dockerfile | One-way; build artifacts only |
| CI → DockerHub | docker push via buildx plugin | Credential from Woodpecker secret |
| CI → k8s API | HTTPS + Bearer token | API at private IP; TLS unverified |
| k8s Ingress → Service | ClusterIP routing | nginx-ingress class handles TLS |
| blog pod → nginx-exporter sidecar | `127.0.0.1:8080/nginx_status` loopback | NGINX stub_status endpoint |

## Build Order for Milestone

The components have strict sequencing dependencies:

```
1. Dockerfile fix (builder stage: hugomods/hugo:exts)
       ↓ required for
2. Local docker build test (validate Hugo can build the site)
       ↓ required for
3. Clean up stray files + secrets (hooks/build, __pycache__, *.xml, ideas.txt)
       ↓ required for (clean build context)
4. .woodpecker.yml CI pipeline execution
       ↓ required for
5. DockerHub image push (viktorbarzin/blog:latest)
       ↓ required for
6. k8s rolling restart + site validation at viktorbarzin.me
```

**Why this order:**
- Hugo version fix must come first — everything else depends on a successful build
- File cleanup should happen before CI (smaller context, no secret in git)
- Cannot validate k8s deploy without a successful push first
- Cannot validate the site without k8s deploying the correct image

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Personal blog (current) | Current architecture is correct — static files, 3 replicas, NGINX. No changes needed. |
| 100K monthly visits | Add CDN (Cloudflare) in front of ingress for edge caching; static content serves identically. |
| 1M monthly visits | CDN essential; consider moving off home cluster to managed hosting (Cloudflare Pages, Netlify) — Hugo generates pure static HTML which deploys to any CDN natively. |

**First bottleneck:** Home cluster upstream bandwidth, not application logic. Static sites scale horizontally with zero code changes.

## Sources

- Current Dockerfile: `/Users/viktorbarzin/code/Website/Dockerfile` — observed directly (HIGH confidence)
- `.woodpecker.yml`: `/Users/viktorbarzin/code/Website/.woodpecker.yml` — observed directly (HIGH confidence)
- `configs/kubernetes.yaml`: observed directly (HIGH confidence)
- `configs/nginx.conf`: observed directly (HIGH confidence)
- hugomods/hugo Docker images: https://hugomods.com/docs/docker/ (MEDIUM confidence — current docs)
- hugomods/hugo multi-stage pattern: https://hugomods.com/docs/docker/ — `FROM hugomods/hugo:exts as builder` + `FROM hugomods/hugo:nginx` (MEDIUM confidence)
- byjg/nginx-extras modules: https://github.com/byjg/docker-nginx-extras — Alpine-based, compiled from source, includes headers-more module (MEDIUM confidence)
- Woodpecker docker-buildx plugin settings: https://codeberg.org/woodpecker-plugins/plugin-docker-buildx (MEDIUM confidence)
- k8s rolling restart via annotation PATCH: https://kubernetes.io/docs/reference/using-api/api-concepts/ (HIGH confidence — matches kubectl rollout restart internals)
- headers-more-nginx-module (`more_set_headers`): https://github.com/openresty/headers-more-nginx-module (HIGH confidence)

---
*Architecture research for: Hugo blog CI/CD modernization*
*Researched: 2026-02-28*
