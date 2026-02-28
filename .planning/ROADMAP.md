# Roadmap: Blog Modernization

## Overview

This is a targeted repair project. The blog's CI build is broken because the Dockerfile uses an outdated Hugo version. The fix proceeds in three phases: clean the repo of stray files and exposed credentials, rewrite the Dockerfile and fix cascading config compatibility issues, then validate that the full CI pipeline produces a live site at viktorbarzin.me.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Security and Repo Hygiene** - Remove exposed credentials and stray artifacts, add .gitignore
- [ ] **Phase 2: Dockerfile and Config Modernization** - Rewrite Dockerfile with modern Hugo image, fix config compatibility
- [ ] **Phase 3: CI Validation** - Confirm pipeline passes end-to-end and site loads in browser

## Phase Details

### Phase 1: Security and Repo Hygiene
**Goal**: The repo contains no exposed credentials in tracked files, no stray artifacts, and a .gitignore that prevents their return
**Depends on**: Nothing (first phase)
**Requirements**: SEC-01, SEC-02, SEC-03, SEC-04, SEC-05
**Success Criteria** (what must be TRUE):
  1. `hooks/` directory no longer exists in the repo (hardcoded LETSENCRYPT_PASS is gone from tracked files)
  2. `__pycache__/`, `08-nesting-openvpn-drawio.xml`, `11-hard-dist-layout.xml`, and `ideas.txt` are all deleted
  3. `.gitignore` exists and covers `__pycache__/`, `*.py[cod]`, `.hugo_build.lock`, `.DS_Store`
  4. `git status` shows a clean working tree with no stray artifacts present
**Plans**: TBD

### Phase 2: Dockerfile and Config Modernization
**Goal**: The Dockerfile builds the site using Hugo v0.157.0 with NGINX alpine, and all config compatibility issues are resolved so the build succeeds locally
**Depends on**: Phase 1
**Requirements**: DOCK-01, DOCK-02, DOCK-03, DOCK-04, CONF-01, CONF-02, CONF-03
**Success Criteria** (what must be TRUE):
  1. `docker build .` completes without errors, producing a valid image
  2. `docker run` of the built image starts NGINX without "unknown directive" errors (`nginx -t` passes)
  3. The Hugo build step inside Docker does not fail on `.Site.Author` or `taxonomyTerm` errors
  4. The built site is served correctly when the container is run locally (`curl localhost` returns HTML)
**Plans**: TBD

### Phase 3: CI Validation
**Goal**: Woodpecker CI runs the full pipeline successfully and the live site at viktorbarzin.me reflects the current content
**Depends on**: Phase 2
**Requirements**: CI-01, CI-02
**Success Criteria** (what must be TRUE):
  1. Woodpecker pipeline completes all steps (build-image + update-deployment) with green status
  2. Docker image `viktorbarzin/blog` is pushed to DockerHub with a new tag
  3. Kubernetes deployment in namespace `website` restarts and reaches Running state
  4. Opening `https://viktorbarzin.me` in a browser loads the blog without errors
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Security and Repo Hygiene | 0/? | Not started | - |
| 2. Dockerfile and Config Modernization | 0/? | Not started | - |
| 3. CI Validation | 0/? | Not started | - |
