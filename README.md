# teleport-builds

Automated CI pipeline that tracks upstream [Gravitational Teleport](https://github.com/gravitational/teleport) releases, builds binaries from source across multiple platforms and architectures, and publishes packages and Docker images.

> **Disclaimer:** This is purely a CI/build repository. All intellectual property, trademarks, and rights to the Teleport project and its source code belong to [Gravitational, Inc.](https://goteleport.com) This repository mirrors Teleport source code and automates building it from the official upstream repository.

## Why this exists

Gravitational's official Teleport releases target amd64 and arm64. This pipeline extends that with additional platform coverage, packaging formats, and Docker image flavors built from the same open-source code:

- Wider platform coverage (i386, armhf/ARMv7, armel/ARMv5, Windows, macOS)
- Two build variants: `upstream` (full, with web UI) and `lite` (agents-only, no web UI)
- Three Docker image flavors per release
- Historical builds back to v2.0.1

## Artifacts

Each release tag on this repository contains:

| Artifact | Description |
|---|---|
| `teleport-<ver>-linux-amd64-bin.tar.gz` | Linux amd64, full build with web UI |
| `teleport-<ver>-linux-arm64-bin.tar.gz` | Linux arm64, full build with web UI |
| `teleport-<ver>-linux-amd64-lite.tar.gz` | Linux amd64, lite (no web UI) |
| `teleport-<ver>-linux-arm64-lite.tar.gz` | Linux arm64, lite |
| `teleport-<ver>-linux-i386-lite.tar.gz` | Linux i386, lite |
| `teleport-<ver>-linux-armhf-lite.tar.gz` | Linux ARMv7 (hard-float), lite |
| `teleport-<ver>-linux-armel-lite.tar.gz` | Linux ARMv5 (soft-float), lite |
| `teleport-<ver>-darwin-amd64-{bin,lite}.tar.gz` | macOS Intel |
| `teleport-<ver>-darwin-arm64-{bin,lite}.tar.gz` | macOS Apple Silicon |
| `teleport-<ver>-windows-amd64-lite.zip` | Windows amd64, lite |
| `teleport_<ver>_*.deb` / `teleport-lite_<ver>_*.deb` | Debian/Ubuntu package |
| `teleport-<ver>-*.rpm` / `teleport-lite-<ver>-*.rpm` | RPM package |

Tarballs contain: `teleport`, `tctl`, `tsh`, `tbot`, `teleport-update`, `fdpass-teleport` (where applicable per version).

## Docker images

Three image flavors are published to [GHCR](https://github.com/Zaephor/teleport/pkgs/container/teleport) (also mirrored to Docker Hub):

| Tag suffix | Base |
|---|---|
| `-debian` (also `latest`) | `debian:bookworm-slim` |
| `-distroless` | Google distroless |
| `-lsio` | LinuxServer.io base |

Images are multi-arch: `linux/amd64`, `linux/arm64/v8`, `linux/arm/v7` (where binaries exist).

```
docker pull ghcr.io/zaephor/teleport:latest              # latest stable, debian
docker pull ghcr.io/zaephor/teleport:18-debian
docker pull ghcr.io/zaephor/teleport:18.7.2-distroless
```

## Build variants

**`upstream`** — Drop-in replacement for official Teleport builds. Includes:
- Web UI (compiled from source or fetched from submodule)
- RDP client (pre-built Rust static library, v8+)
- `fdpass-teleport` (Rust binary, v17+)
- PAM support on Linux

**`lite`** — Minimal agent/client build. Excludes web UI and RDP. Smaller binary, faster build, suitable for nodes/agents that do not serve the web console.

## Repository structure

```
.
├── LATEST                        # Current upstream latest tag (updated by CI)
├── VERSIONS                      # All tracked versions (one per line)
├── golang.override               # Manual Go version overrides per teleport version
├── nfpm.yaml                     # Template for DEB/RPM packaging
├── systemd-teleport.service      # systemd unit file included in packages
├── upstart-teleport.conf         # Upstart conf included in packages
│
├── scripts/
│   ├── detect-era.sh             # Map teleport version → build era (1–11)
│   ├── resolve-go.sh             # Determine required Go toolchain version
│   ├── prep.sh                   # Install system deps in docker build containers
│   ├── install-go.sh             # Install Go via GVM inside container
│   ├── build-webassets.sh        # Build web UI (yarn/pnpm/make + Rust WASM)
│   ├── build-rdpclient.sh        # Build RDP Rust static library
│   ├── build-fdpass.sh           # Build fdpass-teleport Rust binary
│   ├── build.sh                  # Build Go binaries (with CGO fallback logic)
│   ├── package.sh                # Create tar.gz/zip/deb/rpm artifacts
│   ├── smoke-test.sh             # Verify binary runs after build
│   └── install                   # Upstream-style install script (bundled in tarballs)
│
├── docker/
│   ├── Dockerfile.official       # debian:bookworm-slim image
│   ├── Dockerfile.distroless     # Distroless image
│   ├── Dockerfile.lsio           # LinuxServer.io image
│   └── s6/                       # s6-overlay service files for lsio image
│
└── .github/workflows/
    ├── check-for-new.yml         # Poll upstream; append new versions to VERSIONS
    ├── build-router.yml          # Route ci-branch push to correct era workflow
    ├── build-era1.yml            # v2.0–v2.2 (Linux only)
    ├── build-era2.yml            # v2.3–v2.7
    ├── build-era3.yml            # v3–v4.0
    ├── build-era4.yml            # v4.1–v4.2
    ├── build-era5.yml            # v4.3–v4 (webassets submodule)
    ├── build-era6.yml            # v5–v7
    ├── build-era7.yml            # v8–v9
    ├── build-era8.yml            # v10–v11
    ├── build-era9.yml            # v12–v15
    ├── build-era10.yml           # v16
    ├── build-era11.yml           # v17+ (current)
    ├── docker.yml                # Build and push all three Docker image flavors
    ├── rebuild-next.yml          # Rebuild next queued version
    ├── pull-upstream.yml         # Sync/mirror tasks
    ├── clear-drafts.yml          # Clean up draft releases
    ├── purge-images.yml          # Purge old container images
    └── purge-releases.yml        # Purge old releases
```

## Architecture

### Version tracking

```
[GitHub cron / dispatch]
        │
        ▼
check-for-new.yml
  - git ls-remote gravitational/teleport → latest tag → LATEST
  - diff against known VERSIONS → append newest unknown → VERSIONS
  - commit + push to ci branch
        │
        ▼ (push to ci branch triggers)
build-router.yml
  - reads tail of VERSIONS (or inputs.tp_version)
  - detect-era.sh → era number
  - dispatch build-era<N>.yml
```

### Build pipeline (era 11 example, applies broadly)

```
build-era11.yml
  │
  ├─ build-webassets (parallel)
  │     checkout teleport source at tag
  │     build-webassets.sh:
  │       pnpm/yarn install → Rust/WASM → vite → webassets/teleport/
  │     upload artifact
  │
  ├─ build-rdpclient amd64 (parallel)
  │     build-rdpclient.sh → librdp_client.a + header
  │     upload artifact
  │
  ├─ build-rdpclient arm64 (parallel)
  │
  ├─ build-fdpass amd64 (parallel)
  │     build-fdpass.sh → fdpass-teleport binary
  │     upload artifact
  │
  ├─ build-fdpass arm64 (parallel)
  │
  └─ build-core / build-extra (after above)
        matrix: [linux-amd64-upstream, linux-arm64-upstream,
                 linux-amd64-lite, linux-arm64-lite,
                 linux-i386-lite, linux-armhf-lite, linux-armel-lite,
                 darwin-amd64, darwin-arm64, windows-amd64]
        │
        ├─ resolve-go.sh → Go version (go.mod → golang.override → fallback)
        ├─ install Go toolchain (GVM on Linux, setup-go on macOS/Windows)
        ├─ download rdpclient + fdpass artifacts (if applicable)
        ├─ download webassets artifact (if upstream variant)
        ├─ build.sh → dist/teleport/{teleport,tctl,tsh,tbot,...}
        │     CGO fallback: tries multiple ldflag combos; falls back to CGO=0
        ├─ smoke-test.sh → verify binary runs
        ├─ package.sh → artifacts/{tar.gz/zip, .deb, .rpm}
        └─ upload to GitHub Release + artifacts

  └─ docker.yml (after build-core + build-extra)
        check available arches from release assets
        build Dockerfile.official / Dockerfile.distroless / Dockerfile.lsio
        push to Docker Hub + GHCR with semver tags
```

### Build era classification

Teleport's build system changed substantially across major versions. Each era corresponds to a different toolchain, dependency layout, or webasset method:

| Era | Versions | Notes |
|---|---|---|
| 1 | v2.0–v2.2 | Linux only; vendored deps lack arm64 support |
| 2 | v2.3–v2.7 | + macOS + arm64; no Windows |
| 3 | v3–v4.0 | No Windows, no webassets |
| 4 | v4.1–v4.2 | + Windows; webassets submodule added in v4.3 |
| 5 | v4.3–v4 | + webassets (zip-append method) |
| 6 | v5–v7 | |
| 7 | v8–v9 | go:embed via `lib/web/static_embed.go`; pre-built submodule |
| 8 | v10–v11 | go:embed via root `webassets_embed.go`; yarn build from source |
| 9 | v12–v15 | |
| 10 | v16 | |
| 11 | v17+ | pnpm monorepo; Rust/WASM (ironrdp); RDP + fdpass |

### Web asset eras

| Era | Lock file | Webasset method | WASM |
|---|---|---|---|
| v2–v7 | — | git submodule (pre-built), zip-appended to binary | No |
| v8–v9 | — | git submodule (pre-built), go:embed | No |
| v10–v14 | `yarn.lock` | Build from source (yarn), go:embed | No |
| v15–v16 | `yarn.lock` | Build from source (yarn + vite), go:embed | Yes (ironrdp) |
| v17+ | `pnpm-lock.yaml` | Build from source (pnpm + vite), go:embed | Yes (ironrdp) |

### Go version resolution

`resolve-go.sh` picks the Go toolchain in priority order:

1. Exact `major.minor.patch` match in `golang.override`
2. `major.minor` match in `golang.override`
3. `major` match in `golang.override`
4. `go` directive in `go.mod` of the teleport source
5. Fallback: `1.16`

Platform minimums are then enforced (darwin requires ≥1.16, Xcode 15 incompatibility forces ≥1.21 for Go 1.17–1.20, armhf cross-compile requires ≥1.10).

## Requirements / secrets

| Secret | Used for |
|---|---|
| `GH_PAT` | Checkout private/gated repos, create releases, push to ci branch |
| `DOCKER_USERNAME` / `DOCKER_PASSWORD` | Push to Docker Hub |

## Triggering a build

**Automatic:** `check-for-new.yml` runs on a schedule. Any push to the `ci` branch triggers `build-router.yml` which picks the latest unbuilt version from `VERSIONS`.

**Manual:** Dispatch `build-router.yml` (or a specific `build-era<N>.yml`) with a `tp_version` input (e.g. `v18.7.2`).

**Rebuild queue:** `rebuild-next.yml` steps through `VERSIONS` in order, dispatching one build at a time for any version that lacks a release.
