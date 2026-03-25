#!/bin/bash
# build.sh — Build teleport binaries
# Refactored from root build.sh with darwin/windows and PAM support
# Environment variables:
#   GO_VERSION, GO_OS, GO_ARCH, GO_ARM, GO_EXPERIMENT
#   CC, REF_PWD, REF_VER, UPSTREAM, PAM (true/false)
#   BUILD_METHOD (go-build|make-release, default: go-build)
#   BUILD_VARIANT (upstream/lite)
set -eo pipefail

IFS=$'\n'

# Source GVM if available
# GVM scripts reference unbound variables; disable strict modes for sourcing
_SAVED_GOPATH="${GOPATH:-}"
if [[ -f "${REF_PWD}/gvm/scripts/gvm" ]]; then
  set +eo pipefail 2>/dev/null || true
  source "${REF_PWD}/gvm/scripts/gvm" 2>/dev/null || true
  gvm use "go${GO_VERSION}" --default 2>/dev/null || true
  set -eo pipefail
  # GVM installs a 'cd' wrapper that can interfere with navigation;
  # remove it so the shell builtin is used directly
  unset -f cd 2>/dev/null || true
fi
# Restore GOPATH if it was set (GVM overrides it)
if [[ -n "${_SAVED_GOPATH}" ]]; then
  export GOPATH="${_SAVED_GOPATH}"
fi

echo "=== Build: ${GO_OS}/${GO_ARCH} (version ${REF_VER})"

# Add binutils-2.26 to PATH if available (ubuntu:14.04)
if [[ -d "/usr/lib/binutils-2.26/bin" ]]; then
  export PATH="/usr/lib/binutils-2.26/bin:$PATH"
fi

export GOOS="${GO_OS}"
export GOARCH="${GO_ARCH}"
if [[ -n "${GO_ARM:-}" ]]; then export GOARM="${GO_ARM}"; fi
if [[ -n "${GO_EXPERIMENT:-}" && "${GO_VERSION:-}" == 1.20* ]]; then
  export GOEXPERIMENT="${GO_EXPERIMENT}"
fi

# --- CGO settings (match upstream common.mk) ---
if [[ "${GO_OS}" == "darwin" ]]; then
  export CGO_ENABLED=1
  # Don't set CGO_CFLAGS — it overrides per-file #cgo CFLAGS directives in the
  # source (e.g. -xobjective-c -fobjc-arc in oslog_darwin.go).
  # MACOSX_DEPLOYMENT_TARGET achieves the same min-version targeting without
  # clobbering source-level flags.
  export MACOSX_DEPLOYMENT_TARGET="12.0"
  # Use the full Xcode SDK, not CommandLineTools — the CLT SDK has incomplete
  # ObjC headers (NSUInteger/NSInteger undefined in Foundation.h)
  if command -v xcrun &>/dev/null; then
    XCODE_SDK="$(xcrun --show-sdk-path 2>/dev/null || true)"
    if [[ -n "${XCODE_SDK}" && -d "${XCODE_SDK}" ]]; then
      export SDKROOT="${XCODE_SDK}"
    fi
  fi
elif [[ "${GOHOSTARCH:-$(go env GOHOSTARCH)}" != "${GO_ARCH}" ]]; then
  export CGO_ENABLED=1
fi
if [[ -n "${CC:-}" ]]; then
  export CC="${CC}"
  export CGO_ENABLED=1
fi

# --- Go version detection for conditional flags ---
# Parse major.minor from GO_VERSION (e.g. "1.23" or "1.17.13")
GO_MINOR=$(echo "${GO_VERSION:-0.0}" | cut -d. -f2)

# -trimpath: Go 1.13+;  -buildvcs=false: Go 1.18+
GO_BUILD_FLAGS=(-v)
if [[ "${GO_MINOR}" -ge 13 ]]; then
  GO_BUILD_FLAGS+=(-trimpath)
fi
if [[ "${GO_MINOR}" -ge 18 ]]; then
  GO_BUILD_FLAGS+=(-buildvcs=false)
fi

# --- Build tags (match upstream Makefile per-binary tag sets) ---
# kustomize_disable_go_plugin_support: harmless on old versions (no matching files)
BASE_TAGS="kustomize_disable_go_plugin_support"
PAM_TAG=""
if [[ "${PAM:-true}" == "true" && "${GO_OS}" == "linux" ]]; then
  PAM_TAG="pam"
fi

# --- Build variant (upstream/lite) ---
BUILD_VARIANT="${BUILD_VARIANT:-}"
WEBASSETS_TAG=""

case "${BUILD_VARIANT}" in
  upstream)
    # webassets resolved after cd to SOURCE_DIR
    ;;
  lite)
    # PAM + no webassets, no RDP — lighter binaries for agents
    ;;
esac

# --- Version injection ldflags (match upstream -X flags) ---
# Silently ignored by older Go/teleport versions if the symbol path doesn't exist
VERSION_LDFLAGS="-X github.com/gravitational/teleport/lib/modules.teleportBuildType=community"

# --- Platform-specific linker flags (match upstream common.mk) ---
PLATFORM_LDFLAGS=""
if [[ "${GO_OS}" == "darwin" && "${GO_ARCH}" == "arm64" ]]; then
  # Apple's new linker in Xcode 15+ breaks Go builds (Go issue #67854)
  PLATFORM_LDFLAGS="-extldflags=-ld_classic"
fi

# ARM-specific: -debugtramp=2 works around 24-bit call offset limits (matches upstream)
# Available in Go 1.17+ linker
DEBUGTRAMP=""
if [[ ( "${GO_ARCH}" == "arm" || "${GO_ARCH}" == "arm64" ) && "${GO_MINOR}" -ge 17 ]]; then
  DEBUGTRAMP="-debugtramp=2"
fi

# --- Build a single binary with flag fallback ---
# Usage: build_binary <name> <cgo_enabled> <tags>
build_binary() {
  local x="$1"
  local use_cgo="$2"
  local tags="$3"

  local TAG_ARGS=()
  # shellcheck disable=SC2086
  if [[ -n "${tags}" ]]; then
    TAG_ARGS=(-tags "${tags}")
  fi

  # Build flags array depends on CGO mode
  local FLAGS=()
  if [[ "${use_cgo}" == "0" ]]; then
    # CGO_ENABLED=0: internal linker, no extldflags needed
    FLAGS=(
      "-s -w ${VERSION_LDFLAGS} ${DEBUGTRAMP}"
      "-s -w ${VERSION_LDFLAGS}"
      "-s ${VERSION_LDFLAGS}"
      "-w ${VERSION_LDFLAGS}"
      "${VERSION_LDFLAGS}"
    )
  elif [[ "${GO_OS}" == "darwin" ]]; then
    # CGO_ENABLED=1 on Darwin: Apple linker, no ELF-specific flags
    FLAGS=(
      "-s -w ${VERSION_LDFLAGS} ${DEBUGTRAMP} ${PLATFORM_LDFLAGS}"
      "-s -w ${VERSION_LDFLAGS} ${DEBUGTRAMP}"
      "-s -w ${VERSION_LDFLAGS}"
      "-s ${VERSION_LDFLAGS}"
      "-w ${VERSION_LDFLAGS}"
      "${VERSION_LDFLAGS}"
    )
  else
    # CGO_ENABLED=1 on Linux: try various external linker flag combos
    # Note: --long-plt and --no-plt are LINKER flags, passed via -Wl, through gcc
    FLAGS=(
      "-s -w ${VERSION_LDFLAGS} ${DEBUGTRAMP} ${PLATFORM_LDFLAGS}"
      "-s -w ${VERSION_LDFLAGS} ${DEBUGTRAMP} ${PLATFORM_LDFLAGS} -extldflags \"-fuse-ld=lld\""
      "-s -w ${VERSION_LDFLAGS} ${DEBUGTRAMP} ${PLATFORM_LDFLAGS} -extldflags \"-fuse-ld=lld -Wl,--long-plt\""
      "-s -w ${VERSION_LDFLAGS} ${DEBUGTRAMP} ${PLATFORM_LDFLAGS} -extldflags \"-Wl,--long-plt\""
      "-s -w ${VERSION_LDFLAGS} ${DEBUGTRAMP} -extldflags \"-fuse-ld=gold -Wl,--long-plt\""
      "-s -w ${VERSION_LDFLAGS} ${DEBUGTRAMP} -extldflags \"-fuse-ld=gold\""
      "-s -w ${VERSION_LDFLAGS} ${DEBUGTRAMP} -extldflags \"-Wl,--no-plt\""
      "-s ${VERSION_LDFLAGS}"
      "-w ${VERSION_LDFLAGS}"
      "${VERSION_LDFLAGS}"
    )
  fi

  for ldflag in "${FLAGS[@]}"; do
    # Trim whitespace from ldflag (empty DEBUGTRAMP/PLATFORM_LDFLAGS leave gaps)
    ldflag="$(echo "${ldflag}" | tr -s ' ')"
    echo "::group::Trying to build ${x} with CGO_ENABLED=${use_cgo} '${ldflag}'"
    if CGO_ENABLED="${use_cgo}" go build "${GO_BUILD_FLAGS[@]}" \
        "${TAG_ARGS[@]}" -ldflags "${ldflag}" \
        -o "${REF_PWD}/dist/teleport/${x}" "./tool/${x}" 2>&1; then
      echo "::endgroup::"
      local SIZE
      SIZE=$(stat -c%s "${REF_PWD}/dist/teleport/${x}" 2>/dev/null || stat -f%z "${REF_PWD}/dist/teleport/${x}" 2>/dev/null || echo "?")
      echo "== ${x} - Success (${SIZE} bytes, CGO_ENABLED=${use_cgo})"
      return 0
    fi
    echo "::endgroup::"
    go clean -cache 2>/dev/null || true
  done
  return 1
}

SOURCE_DIR="${REF_PWD}/go/src/${UPSTREAM}"
mkdir -p "${REF_PWD}/dist/teleport"

git config --global --add safe.directory "${SOURCE_DIR}"
cd "${SOURCE_DIR}"

# Compute git ref for version stamp
GITREF=""
if command -v git &>/dev/null; then
  GITREF=$(git describe --tags --always 2>/dev/null || echo "${REF_VER}")
fi
if [[ -n "${GITREF}" ]]; then
  VERSION_LDFLAGS="${VERSION_LDFLAGS} -X github.com/gravitational/teleport/api/types.gitref=${GITREF}"
fi

# Resolve webassets_embed tag now that SOURCE_DIR is available
# Three eras: v10+ (root webassets_embed.go), v8-v9 (lib/web/static_embed.go), v2-v7 (zip-append)
if [[ "${BUILD_VARIANT}" == "upstream" ]]; then
  if [[ -f "webassets_embed.go" || -f "lib/web/static_embed.go" ]]; then
    # go:embed era (v8+): enable tag if assets exist
    if [[ -d "webassets/teleport" ]] && [[ -n "$(ls -A webassets/teleport/ 2>/dev/null)" ]]; then
      WEBASSETS_TAG="webassets_embed"
      echo "=== upstream variant: webassets_embed tag enabled"
      # v8-v9: static_embed.go embeds from lib/web/build/webassets/ — copy assets there
      if [[ -f "lib/web/static_embed.go" && ! -d "lib/web/build/webassets" ]]; then
        mkdir -p lib/web/build/webassets
        cp -r webassets/teleport/* lib/web/build/webassets/ 2>/dev/null || true
        echo "=== copied webassets → lib/web/build/webassets/ (v8-v9 embed path)"
      fi
    else
      echo "ERROR: upstream variant requires webassets but webassets/teleport/ is missing or empty"
      exit 1
    fi
  elif [[ -d "webassets/teleport" ]] && [[ -n "$(ls -A webassets/teleport/ 2>/dev/null)" ]]; then
    # Pre-go:embed era (v2-v7): zip-append after build
    echo "=== upstream variant: legacy zip-append mode (webassets found, no embed file)"
  elif [[ -f ".gitmodules" ]] && grep -q "webassets" ".gitmodules" 2>/dev/null; then
    # This version has a webassets submodule but assets are missing
    echo "ERROR: upstream variant requires webassets but submodule assets are missing"
    exit 1
  fi
fi

# --- RDP client (pre-built by build-rdpclient job, Linux only) ---
RDPCLIENT_TAG=""
if [[ "${BUILD_VARIANT}" == "upstream" && "${GO_OS}" == "linux" && ("${GO_ARCH}" == "amd64" || "${GO_ARCH}" == "arm64") ]]; then
  # Determine Rust target to place the library where CGO expects it
  case "${GO_ARCH}" in
    amd64) RUST_TARGET="x86_64-unknown-linux-gnu" ;;
    arm64) RUST_TARGET="aarch64-unknown-linux-gnu" ;;
  esac

  RDPCLIENT_LIB="target/${RUST_TARGET}/release/librdp_client.a"

  # Check for pre-built library + header (downloaded from build-rdpclient artifact)
  # Header name varies across versions: librdpclient.h (v18+) or librdprs.h (v10-v17)
  RDPCLIENT_HEADER_SRC=""
  for candidate in "${REF_PWD}/rdpclient/librdpclient.h" "${REF_PWD}/rdpclient/librdprs.h"; do
    if [[ -f "${candidate}" ]]; then
      RDPCLIENT_HEADER_SRC="${candidate}"
      break
    fi
  done

  if [[ -f "${REF_PWD}/rdpclient/librdp_client.a" && -n "${RDPCLIENT_HEADER_SRC}" ]]; then
    mkdir -p "target/${RUST_TARGET}/release"
    cp "${REF_PWD}/rdpclient/librdp_client.a" "${RDPCLIENT_LIB}"
    # Place header where CGO expects it (same directory as client.go)
    HEADER_NAME="$(basename "${RDPCLIENT_HEADER_SRC}")"
    cp "${RDPCLIENT_HEADER_SRC}" "lib/srv/desktop/rdp/rdpclient/${HEADER_NAME}"
    RDPCLIENT_TAG="desktop_access_rdp"
    echo "=== RDP client ready: ${RUST_TARGET} (pre-built, header: ${HEADER_NAME})"
  else
    # desktop_access_rdp exists in v8+; required from v10+
    MAJOR=$(echo "${REF_VER#v}" | cut -d. -f1)
    if [[ "${MAJOR}" -ge 10 ]]; then
      echo "ERROR: upstream variant requires rdp-client for v${MAJOR} but rdpclient artifact not found"
      echo "  Expected: ${REF_PWD}/rdpclient/librdp_client.a and header (.h)"
      ls -la "${REF_PWD}/rdpclient/" 2>/dev/null || echo "  (rdpclient/ directory does not exist)"
      exit 1
    elif [[ "${MAJOR}" -ge 8 ]]; then
      echo "WARNING: rdp-client not found for v${MAJOR}, upstream build will lack RDP support"
    fi
  fi
fi

echo "::group::go env"
go env
echo "::endgroup::"

# Build method
BUILD_METHOD="${BUILD_METHOD:-go-build}"

if [[ "${BUILD_METHOD}" == "make-release" ]]; then
  echo "::group::make release"
  make release
  echo "::endgroup::"

  # Find and extract the release bundle
  BUNDLE=""
  for f in teleport-*.tar.gz teleport-*.zip; do
    if [[ -f "$f" ]]; then
      BUNDLE="$f"
      break
    fi
  done
  if [[ -n "${BUNDLE}" ]]; then
    tar -xf "${BUNDLE}" -C "${REF_PWD}/dist/" 2>/dev/null || \
      unzip -o "${BUNDLE}" -d "${REF_PWD}/dist/" 2>/dev/null || true
  fi
else
  # Direct go build for each binary
  echo "::group::go mod download"
  go mod download 2>/dev/null || go get 2>/dev/null || true
  echo "::endgroup::"

  # fdpass-teleport is Rust — built separately, not part of the Go build loop
  # Build order: core binaries first, optional ones last
  # tbot and teleport-update are optional — they don't exist in older versions
  # and may fail to compile with newer toolchains on old source
  for x in 'teleport' 'tctl' 'tsh' 'tbot' 'teleport-update'; do
    if [[ ! -d "./tool/${x}" ]]; then
      # tbot and teleport-update don't exist in older versions — that's fine
      continue
    fi

    # Windows platform exclusions (match upstream Makefile BINS_windows)
    # Upstream ships: tsh (always), tctl (v16+). Never: teleport, tbot, teleport-update.
    if [[ "${GO_OS}" == "windows" ]]; then
      case "${x}" in
        teleport)
          echo "== ${x} - SKIPPED (server binary is Linux/macOS only)"
          continue ;;
        tbot)
          echo "== ${x} - SKIPPED (not supported on Windows)"
          continue ;;
        teleport-update)
          echo "== ${x} - SKIPPED (not supported on Windows)"
          continue ;;
      esac
    fi

    # Per-binary tags and CGO (match upstream Makefile)
    #   tbot:            CGO_ENABLED=0 (non-Windows), base tags only
    #   tctl:            CGO_ENABLED=1, pam + base tags
    #   tsh:             CGO_ENABLED=1, base tags (no pam)
    #   teleport:        CGO_ENABLED=1, pam + base tags
    #   teleport-update: CGO_ENABLED=0, no tags
    BINARY_CGO="${CGO_ENABLED:-1}"
    BINARY_TAGS="${BASE_TAGS}"
    case "${x}" in
      tbot)
        # Upstream v15+: CGO_ENABLED=0 for tbot on non-Windows.
        # Older versions (v10-v14) need CGO_ENABLED=1 (imports BPF, PKCS11).
        MAJOR=$(echo "${REF_VER#v}" | cut -d. -f1)
        if [[ "${MAJOR}" -ge 15 && "${GO_OS}" != "windows" ]]; then
          BINARY_CGO=0
        fi
        ;;
      teleport-update)
        # Upstream: always CGO_ENABLED=0, no feature tags
        BINARY_CGO=0
        BINARY_TAGS=""
        ;;
      tctl)
        BINARY_TAGS="${PAM_TAG} ${BASE_TAGS}"
        ;;
      teleport)
        BINARY_TAGS="${PAM_TAG} ${WEBASSETS_TAG} ${RDPCLIENT_TAG} ${BASE_TAGS}"
        ;;
      tsh)
        # Upstream: tsh doesn't use pam tag
        ;;
    esac
    # Trim whitespace
    BINARY_TAGS="$(echo "${BINARY_TAGS}" | xargs)"

    BUILT=false

    # Attempt 1: build with configured CGO setting
    if build_binary "${x}" "${BINARY_CGO}" "${BINARY_TAGS}"; then
      BUILT=true
    fi

    # Attempt 2: CGO_ENABLED=0 fallback (if we were using CGO=1)
    # External linkers can fail on large binaries (ARM32 PLT overflow, etc.)
    # Go's internal linker has no such limits. Trade-off: loses PAM.
    if [[ "${BUILT}" != "true" && "${BINARY_CGO}" != "0" ]]; then
      echo ":: Retrying ${x} with CGO_ENABLED=0 (internal linker fallback)"
      # Drop pam tag — requires CGO
      FALLBACK_TAGS="${BINARY_TAGS//pam/}"
      FALLBACK_TAGS="$(echo "${FALLBACK_TAGS}" | xargs)"
      if build_binary "${x}" "0" "${FALLBACK_TAGS}"; then
        BUILT=true
      fi
    fi

    if [[ "${BUILT}" != "true" ]]; then
      MAJOR=$(echo "${REF_VER#v}" | cut -d. -f1)

      # Determine if this failure is fatal or can be skipped
      SKIP_REASON=""

      # tbot/teleport-update: source may not exist in older versions
      if [[ "${x}" == "tbot" || "${x}" == "teleport-update" ]]; then
        SKIP_REASON="optional binary, not present in all versions"
      fi

      # tctl on Windows pre-v16: upstream never shipped it, compilation is best-effort
      if [[ "${x}" == "tctl" && "${GO_OS}" == "windows" && "${MAJOR}" -lt 16 ]]; then
        SKIP_REASON="tctl not officially supported on Windows before v16"
      fi

      if [[ -n "${SKIP_REASON}" ]]; then
        echo "== ${x} - SKIPPED (${SKIP_REASON})"
      else
        echo "== ${x} - FAILED (all linker flag combos exhausted)"
        exit 1
      fi
    fi
  done
fi

# --- fdpass-teleport (pre-built Rust binary, Linux amd64/arm64 only) ---
if [[ "${GO_OS}" == "linux" && -f "${REF_PWD}/fdpass/fdpass-teleport" ]]; then
  cp "${REF_PWD}/fdpass/fdpass-teleport" "${REF_PWD}/dist/teleport/fdpass-teleport"
  chmod +x "${REF_PWD}/dist/teleport/fdpass-teleport"
  echo "=== fdpass-teleport copied from pre-built artifact"
fi

# Write VERSION file and copy examples
echo "${REF_VER}" > "${REF_PWD}/dist/teleport/VERSION"
if [[ -d "${SOURCE_DIR}/examples" ]]; then
  cp -r "${SOURCE_DIR}/examples" "${REF_PWD}/dist/teleport/" 2>/dev/null || true
fi

# Legacy zip-append for v2-v7 upstream variant
# Pre-go:embed versions bundled web assets by appending a zip to the teleport binary
if [[ "${BUILD_VARIANT:-}" == "upstream" && -z "${WEBASSETS_TAG}" ]]; then
  if [[ -d "${SOURCE_DIR}/webassets/teleport" ]] && [[ -n "$(ls -A "${SOURCE_DIR}/webassets/teleport/" 2>/dev/null)" ]]; then
    if [[ -f "${REF_PWD}/dist/teleport/teleport" ]]; then
      echo "::group::Zip-append webassets (legacy v2-v7)"
      WEBASSETS_ZIP=$(mktemp /tmp/webassets-XXXXXX.zip)
      rm -f "${WEBASSETS_ZIP}"
      (cd "${SOURCE_DIR}/webassets/teleport" && zip -qr "${WEBASSETS_ZIP}" .) 2>&1
      if [[ -s "${WEBASSETS_ZIP}" ]]; then
        BEFORE_SIZE=$(stat -c%s "${REF_PWD}/dist/teleport/teleport" 2>/dev/null || stat -f%z "${REF_PWD}/dist/teleport/teleport")
        cat "${WEBASSETS_ZIP}" >> "${REF_PWD}/dist/teleport/teleport"
        zip -A "${REF_PWD}/dist/teleport/teleport" 2>&1 || true
        AFTER_SIZE=$(stat -c%s "${REF_PWD}/dist/teleport/teleport" 2>/dev/null || stat -f%z "${REF_PWD}/dist/teleport/teleport")
        echo "Appended webassets zip: ${BEFORE_SIZE} → ${AFTER_SIZE} bytes"
      else
        echo "ERROR: Failed to create webassets zip for upstream variant"
        rm -f "${WEBASSETS_ZIP}"
        exit 1
      fi
      rm -f "${WEBASSETS_ZIP}"
      echo "::endgroup::"
    fi
  fi
fi

echo "=== Build complete"
ls -la "${REF_PWD}/dist/teleport/"
