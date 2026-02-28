# Requirements: Blog Modernization

**Defined:** 2026-02-28
**Core Value:** The blog builds successfully in CI so new content can be published to viktorbarzin.me.

## v1 Requirements

Requirements for CI green. Each maps to roadmap phases.

### Security & Hygiene

- [ ] **SEC-01**: Delete `hooks/` directory (contains hardcoded LetsEncrypt password in plaintext)
- [ ] **SEC-02**: Delete `__pycache__/` directory (Python build artifact)
- [ ] **SEC-03**: Delete `08-nesting-openvpn-drawio.xml` and `11-hard-dist-layout.xml` (stray drawio files)
- [ ] **SEC-04**: Delete `ideas.txt` (not part of site source)
- [ ] **SEC-05**: Add `.gitignore` to prevent future artifact accumulation

### Dockerfile

- [ ] **DOCK-01**: Replace `debian:latest` build stage with `ghcr.io/gohugoio/hugo:v0.157.0`
- [ ] **DOCK-02**: Replace `byjg/nginx-extras` serve stage with `nginx:1.28.2-alpine`
- [ ] **DOCK-03**: Remove `LETSENCRYPT_PASS` build arg (no longer used)
- [ ] **DOCK-04**: Add `--minify` flag to Hugo build command

### Config Compatibility

- [ ] **CONF-01**: Fix `disableKinds` — replace `taxonomyTerm` with `term` in config.toml
- [ ] **CONF-02**: Replace `more_set_headers 'Server: less'` in nginx.conf (not available in standard nginx:alpine)
- [ ] **CONF-03**: Add `layouts/_default/rss.xml` override to fix `.Site.Author` removal in Hugo v0.157

### CI Validation

- [ ] **CI-01**: Woodpecker CI pipeline builds successfully (image pushed to DockerHub)
- [ ] **CI-02**: K8s deployment restarts and site loads at viktorbarzin.me

## v2 Requirements

### Modernization

- **MOD-01**: Migrate Google Analytics from UA to GA4
- **MOD-02**: Convert hugo-theme-nix to git submodule for easier updates
- **MOD-03**: Update config.toml to hugo.toml (TOML → YAML optional)
- **MOD-04**: Add `.dockerignore` for faster builds

## Out of Scope

| Feature | Reason |
|---------|--------|
| Theme redesign | Working theme, just fixing the build |
| Hugo config format migration | config.toml works fine, cosmetic change |
| Multi-platform Docker builds | Single arch sufficient for home k8s |
| Git history scrubbing for leaked password | Rotation is simpler; private repo reduces risk |
| Adding new articles | Separate task after CI is green |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SEC-01 | Phase 1 | Pending |
| SEC-02 | Phase 1 | Pending |
| SEC-03 | Phase 1 | Pending |
| SEC-04 | Phase 1 | Pending |
| SEC-05 | Phase 1 | Pending |
| DOCK-01 | Phase 2 | Pending |
| DOCK-02 | Phase 2 | Pending |
| DOCK-03 | Phase 2 | Pending |
| DOCK-04 | Phase 2 | Pending |
| CONF-01 | Phase 2 | Pending |
| CONF-02 | Phase 2 | Pending |
| CONF-03 | Phase 2 | Pending |
| CI-01 | Phase 3 | Pending |
| CI-02 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-02-28*
*Last updated: 2026-02-28 after roadmap creation*
