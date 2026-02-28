# Pitfalls Research

**Domain:** Hugo blog CI/CD Docker modernization
**Researched:** 2026-02-28
**Confidence:** HIGH (findings verified against official Hugo release notes, Docker Hub, and direct codebase inspection)

---

## Critical Pitfalls

### Pitfall 1: Switching to `nginx:alpine` Breaks `more_set_headers` Directive

**What goes wrong:**
The current `nginx.conf` uses `more_set_headers 'Server: less';` at the top-level `http {}` block. This directive is provided by the `headers-more-nginx-module` (an OpenResty third-party module). Standard `nginx:alpine` does NOT include this module. The container will fail to start with an "unknown directive" error, making the site completely unavailable.

**Why it happens:**
`byjg/nginx-extras` bundles `HttpHeadersMore` among many other third-party modules. Developers assume `nginx:alpine` is a drop-in replacement, not realizing the directive dependency.

**How to avoid:**
Choose one of these options before switching nginx images:
1. Remove the `more_set_headers` line and replace with standard nginx `add_header` (cannot remove the `Server` header this way, only set it — use `server_tokens off;` which is already present)
2. Use `openresty/openresty:alpine` as the base image instead of `nginx:alpine` (OpenResty includes headers-more by default)
3. Compile a custom nginx with the module (not recommended — high maintenance cost)

The simplest correct fix: delete the `more_set_headers 'Server: less';` line. `server_tokens off;` already suppresses the version. The `Server: less` header is cosmetic security theater, not a functional requirement.

**Warning signs:**
- Container exits immediately after `docker run` with no HTTP response
- Docker logs show `nginx: [emerg] unknown directive "more_set_headers"`
- `byjg/nginx-extras` appearing in Dockerfile FROM line

**Phase to address:**
Docker image modernization phase — before any CI validation run.

---

### Pitfall 2: `taxonomyTerm` in `disableKinds` is a Breaking Config Error on Hugo >= 0.73

**What goes wrong:**
`config.toml` contains:
```toml
disableKinds = ["sitemap", "categories", "taxonomy", "taxonomyTerm"]
```
In Hugo v0.73.0, the taxonomy kind names were swapped: `taxonomy` and `taxonomyTerm` exchanged meanings. The name `taxonomyTerm` no longer exists as a valid kind. On Hugo >= 0.73, this may produce a warning or silently fail to disable the intended page type.

**Why it happens:**
Hugo v0.73.0 release notes document: "`taxonomy` → `term`" and "`taxonomyTerm` → `taxonomy`". The original config was written for Hugo < 0.73. As long as apt-installed Hugo on Debian stable stayed at 0.131 (which still emits a WARN), this was latent. On newer Hugo, `taxonomyTerm` is simply unrecognized.

**How to avoid:**
Update `disableKinds` to use current kind names:
```toml
disableKinds = ["sitemap", "categories", "taxonomy", "term"]
```
Note: verify which kinds you actually want disabled. `taxonomy` now means the taxonomy list page (e.g., `/tags/`), and `term` means individual tag pages (e.g., `/tags/docker/`).

**Warning signs:**
- Hugo build log shows `WARN ... "taxonomyTerm" is not a valid page kind`
- Site generates unexpected taxonomy pages after the Hugo upgrade
- `hugo --verbose` output lists unexpected page types being generated

**Phase to address:**
Config cleanup phase — before building with any newer Hugo version.

---

### Pitfall 3: No Official Current Hugo Docker Image Exists on Docker Hub

**What goes wrong:**
Developers assume `docker pull gohugoio/hugo:latest` gives a current Hugo version. The `gohugoio/hugo` image on Docker Hub was last updated in **2017** and only goes up to v0.31. Using it gives a Hugo that is ~7 years and ~126 minor versions behind, which will likely fail on modern config syntax and theme templates.

**Why it happens:**
The Hugo project did not maintain Docker Hub images. The official, actively maintained image is on GitHub Container Registry: `ghcr.io/gohugoio/hugo` (added recently, latest tag is v0.157.0 as of Feb 2026). The Docker Hub repository exists and looks official but is abandoned.

**How to avoid:**
Use one of these two official/community options:
- `ghcr.io/gohugoio/hugo:v0.157.0` — official image from Hugo project, GHCR, ~155k pulls, updated regularly (HIGH confidence)
- `hugomods/hugo` — community image with extended/non-extended variants and older version support (MEDIUM confidence)

Do not use `gohugoio/hugo` from Docker Hub.

**Warning signs:**
- `FROM gohugoio/hugo:latest` in Dockerfile
- Hugo build producing version 0.31 in output logs
- Build fails with "configuration key not found" for modern config options

**Phase to address:**
Dockerfile rewrite phase — the first decision to make before any other change.

---

### Pitfall 4: Hardcoded Secret in `hooks/build` Leaks via Git History

**What goes wrong:**
`hooks/build` contains a plaintext `LETSENCRYPT_PASS` value hardcoded in the docker build command:
```bash
docker build --build-arg LETSENCRYPT_PASS="MGm2Sh7FYERIbsmND5y5" -t viktorbarzin/blog .
```
This is committed to git history. Even after removing the line, the secret remains accessible via `git log -p` to anyone with repo access.

**Why it happens:**
Originally written for local convenience. The secret was intended for Docker build-time decryption of a Let's Encrypt tarball. The CI pipeline (Woodpecker) correctly uses `from_secret: dockerhub-pat` for the push credential, but the build secret was never migrated to a secret store.

**How to avoid:**
1. Delete or overwrite `hooks/build` with a version that does not contain the password
2. The password should be added to Woodpecker secrets store if still needed
3. Consider whether the Let's Encrypt tarball decryption is even needed — the nginx.conf already has SSL sections commented out, suggesting certs are now handled by the Kubernetes ingress controller rather than in-container
4. If the password is no longer needed (cert decryption removed), the `ARG LETSENCRYPT_PASS` and associated `hooks/build` file can simply be deleted

Note: git history rotation (rebase/filter-branch) is expensive. Assess whether the secret is still valid and whether the repo is public before deciding if history scrubbing is necessary.

**Warning signs:**
- `ARG LETSENCRYPT_PASS` in Dockerfile
- `docker build --build-arg` in any shell script
- CI pipeline not using `from_secret` for build args

**Phase to address:**
Security cleanup — first phase, before any other changes to avoid accidentally recommitting.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Keeping `byjg/nginx-extras` for `more_set_headers` | No nginx.conf changes needed | Unmaintained image (last push unknown), larger attack surface from bundled modules | Only if `more_set_headers` is truly required for security compliance |
| Using `apt install hugo` in Dockerfile | Simple, no registry dependency | Debian stable is 26 minor versions behind latest (v0.131 vs v0.157); unstable-only gets current | Never — use pinned official binary or official image |
| Not pinning Hugo version in Docker image | Always gets latest | Build breaks when Hugo releases a breaking change; non-reproducible builds | Never for production builds |
| Leaving `taxonomyTerm` in `disableKinds` | No config change needed | Hugo WARN log spam; may not actually disable the intended page type | Never — 5-minute fix |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Woodpecker `woodpeckerci/plugin-docker-buildx` | Passing build args as plain `environment:` vars instead of `settings.build_args` | Use `settings.build_args` list to pass non-secret args; use Woodpecker secrets for sensitive values |
| Kubernetes deployment restart via curl | Hard-coding the API server IP (10.0.20.100) in `.woodpecker.yml` | Use in-cluster service DNS (`kubernetes.default.svc`) or environment variables; the IP may change |
| Hugo extended vs standard edition | Using standard when theme needs SASS compilation | Check `theme.toml` `min_version` and inspect whether `themes/*/assets/*.scss` exist; hugo-theme-nix does not use SCSS so standard edition suffices |
| `ghcr.io/gohugoio/hugo` image | Not mounting site files correctly; image entrypoint may differ from community images | Verify entrypoint with `docker inspect ghcr.io/gohugoio/hugo:latest` before building; use multi-stage build with explicit RUN commands |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `debian:latest` as Hugo build stage | Image pulls 100MB+ on every CI build | Multi-stage: use a small Alpine-based Hugo image for build, then `nginx:alpine` for serve | Always — just slower builds |
| No `.dockerignore` | `COPY . /static-site` includes node_modules, `.git`, themes git history | Add `.dockerignore` excluding `.git`, any temp files | Slows build; no functional breakage |
| Not caching Hugo module downloads | Hugo module downloads happen on every build | This site uses git-submodule-style themes, not Hugo modules — not applicable | N/A for this project |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Hardcoded `LETSENCRYPT_PASS` in `hooks/build` | Credential exposure to anyone with git access | Move to Woodpecker secret store; remove from git-tracked file |
| `ARG LETSENCRYPT_PASS` in Dockerfile | Build arg values appear in `docker history` output | Pass secrets via environment at runtime, not build args; or remove entirely if cert handling moved to k8s ingress |
| `byjg/nginx-extras:latest` mutable tag | Image content changes without Dockerfile change; supply chain risk | Pin to a specific digest or version tag; or switch to maintained base |
| CSP headers commented out in nginx.conf | No Content-Security-Policy enforcement | Re-enable CSP with appropriate directives for the site's third-party resources |

---

## "Looks Done But Isn't" Checklist

- [ ] **Hugo build succeeds locally but not in Docker:** Verify the Docker image Hugo version matches what you tested locally. Hugo version mismatch causes silent content differences.
- [ ] **nginx starts but `more_set_headers` errors:** Run `docker run --rm <image> nginx -t` to validate nginx config before pushing to registry.
- [ ] **`disableKinds` updated but taxonomy pages still generate:** Run `hugo list all` and check for unexpected taxonomy pages in output.
- [ ] **Secret removed from `hooks/build` but still in Dockerfile:** Search both files for `LETSENCRYPT_PASS` and `ARG LETSENCRYPT` before declaring complete.
- [ ] **CI pipeline runs but deployment doesn't update:** Check that the Kubernetes PATCH curl in `update-deployment` step succeeds — it uses `| head` which swallows errors; add `-f` flag to curl or check exit codes.
- [ ] **Site renders but pygments syntax highlighting broken:** Confirm `pygmentsCodeFences = true` and `pygmentsstyle = "native"` still work with new Hugo version; these are top-level config options that may emit deprecation warnings but still function.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong nginx base image, container won't start | LOW | Change `FROM byjg/nginx-extras` to correct image, rebuild, redeploy (< 10 min) |
| `taxonomyTerm` config error | LOW | Edit one line in `config.toml`, rebuild |
| Hardcoded secret in git history | MEDIUM | Rotate the credential immediately; decide if history scrubbing is needed based on repo visibility and credential status |
| Hugo version incompatibility breaks theme templates | MEDIUM-HIGH | Identify which `.Site.Author` or `.Paginator` calls broke; patch theme layout files in `layouts/` override directory (do not modify files in `themes/hugo-theme-nix/` directly) |
| CI pipeline broken, site out of date | LOW | Manual `docker build` and `kubectl rollout restart` while fixing pipeline |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| `more_set_headers` nginx breakage | Docker image modernization (nginx base change) | `docker run --rm <image> nginx -t` passes without errors |
| `taxonomyTerm` deprecated kind | Config cleanup (pre-build) | `hugo build --verbose` produces no WARN about invalid page kinds |
| Stale Docker Hub Hugo image | Dockerfile rewrite (first phase) | Dockerfile FROM points to `ghcr.io/gohugoio/hugo` or pinned Hugo binary |
| Hardcoded secret in `hooks/build` | Security cleanup (first phase) | `grep -r LETSENCRYPT_PASS` finds nothing in git-tracked files |
| `byjg/nginx-extras` unmaintained | Docker image modernization | Image digest is pinned or replaced with maintained alternative |
| Theme `.Site.Author` deprecation (Hugo >= 0.136) | Hugo version validation | `hugo build` produces no ERROR for template rendering; RSS feed validates |
| CI `update-deployment` silent failure | CI validation phase | Add `curl -f` flag; verify pod restarts in cluster after pipeline runs |

---

## Hugo API Deprecations Affecting This Theme (Timeline)

For reference when choosing a Hugo target version:

| Hugo Version | Breaking Change | Affects This Project? |
|---|---|---|
| v0.73.0 | `taxonomyTerm` kind renamed; `taxonomy` and `term` are now the valid names | YES — `disableKinds` in config.toml |
| v0.128.0 | `.Paginator.PageSize` deprecated in favor of `.Paginator.PagerSize` | YES — theme pagination.html |
| v0.136.0 | `.Site.Author`, `.Site.Social`, `.Site.IsMultiLingual`, `paginate`, `paginatePath` deprecated | YES — theme rss.html uses `.Site.Author.email` |
| v0.156.0 | All v0.136.0 deprecated items REMOVED (hard error if used) | YES — `.Site.Author` in rss.html becomes a build failure |

**Implication:** Targeting Hugo v0.131 (current Debian stable) means zero breaking changes from this list. Targeting v0.155.x means deprecation warnings only. Targeting v0.157.0 (latest) means `.Site.Author` usage in `themes/hugo-theme-nix/layouts/_default/rss.html` will FAIL the build unless overridden in `layouts/` or the theme is patched.

The correct fix: create `layouts/_default/rss.html` that overrides the broken theme partial, replacing `.Site.Author.email` with `.Site.Params.Author.email`.

---

## Sources

- Hugo v0.73.0 release notes — taxonomyTerm → term rename: https://github.com/gohugoio/hugo/releases/tag/v0.73.0
- Hugo v0.156.0 release notes — .Site.Author removal: https://github.com/gohugoio/hugo/releases/tag/v0.156.0
- Hugo v0.128.0 release notes — Paginator.PageSize deprecation: https://github.com/gohugoio/hugo/releases/tag/v0.128.0
- Debian package versions (stable: 0.131.0, sid: 0.157.0): https://packages.debian.org/search?searchon=names&keywords=hugo
- `gohugoio/hugo` Docker Hub (last updated 2017, v0.31 only): https://hub.docker.com/r/gohugoio/hugo
- `ghcr.io/gohugoio/hugo` official GHCR image (current, v0.157.0): https://github.com/gohugoio/hugo/pkgs/container/hugo
- `hugomods/docker` community Hugo images: https://github.com/hugomods/docker
- `byjg/nginx-extras` module list (includes HttpHeadersMore): https://github.com/byjg/docker-nginx-extras
- `headers-more-nginx-module` — not in nginx:alpine, requires OpenResty or custom compile: https://github.com/openresty/headers-more-nginx-module
- Woodpecker CI secrets documentation: https://woodpecker-ci.org/docs/usage/secrets
- Direct codebase inspection: /Users/viktorbarzin/code/Website/ (Dockerfile, config.toml, hooks/build, nginx.conf, themes/hugo-theme-nix/layouts/)

---
*Pitfalls research for: Hugo blog Docker/CI modernization*
*Researched: 2026-02-28*
