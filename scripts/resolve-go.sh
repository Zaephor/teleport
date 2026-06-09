#!/bin/bash
# resolve-go.sh — Resolve the Go toolchain to build a given teleport version,
# matching the version upstream actually shipped with as closely as the build
# tooling allows.
#
# Resolution order:
#   1. golang.override — EXPLICIT EXCEPTIONS ONLY (a teleport+go pairing that is no
#      longer reproducible / needs a deliberate substitute). Most-specific first:
#      vX.Y.Z, then vX.Y, then vX. Normally empty; add an entry only when extraction
#      yields a version that cannot be built.
#   2. Upstream's pinned toolchain, read from the tag's own source (authoritative):
#        build.assets/versions.mk  GOLANG_VERSION   (v12+)
#        build.assets/Makefile     GOLANG_VERSION   (v8-v11)
#        build.assets/Makefile     RUNTIME          (v3-v7)
#        build.assets/images.mk    GOLANG_VERSION   (variant)
#        build.assets/Dockerfile   hardcoded go1.x  (v2)
#   3. go.mod 'go' directive — language floor, last resort (understates the real
#      toolchain, e.g. go.mod 1.20 vs versions.mk go1.21.9, so only used if 2 fails).
#   4. Hard fallback (1.16).
#
# Ceiling: the GVM bootstrap chain in install-go.sh (... -> go1.20.14) can source-compile
# up to Go 1.23. Go 1.24+ need a go1.22.6 bootstrap we do not carry, so when extraction
# yields 1.24+ we install 1.23 and let GOTOOLCHAIN=auto fetch the exact prebuilt
# toolchain at build time (modern go.mod pins the full patch, so the match stays exact).
# If install-go.sh gains a newer bootstrap, raise GVM_COMPILE_CEILING_MINOR.
#
# Usage: resolve-go.sh <version> [source_dir] [ci_dir]
set -euo pipefail

GVM_COMPILE_CEILING_MINOR=23

VERSION="${1:?Usage: resolve-go.sh <version> [source_dir] [ci_dir]}"
if [[ ! "${VERSION}" =~ ^v[0-9] ]]; then
  echo "Warning: unusual version format '${VERSION}'" >&2
fi

SOURCE_DIR="${2:-}"
CI_DIR="${3:-.}"

# Decompose vMAJOR.MINOR.PATCH
VER="${VERSION#v}"
MAJOR="${VER%%.*}"
if [[ "${VER}" == *.* ]]; then
  MINOR="${VER#*.}"; MINOR="${MINOR%%.*}"
else
  MINOR="0"
fi
PATCH=""
[[ "${VER}" == *.*.* ]] && PATCH="${VER##*.}"

OVERRIDE_FILE="${CI_DIR}/golang.override"
GO_VERSION=""

# --- 1. Explicit overrides (exceptions) -------------------------------------
override_lookup() {  # $1 = key, e.g. v3.1.18
  grep "^$1," "${OVERRIDE_FILE}" 2>/dev/null | cut -d',' -f2 | head -1 || true
}
if [[ -f "${OVERRIDE_FILE}" ]]; then
  [[ -n "${PATCH}" ]] && GO_VERSION=$(override_lookup "v${MAJOR}.${MINOR}.${PATCH}")
  [[ -z "${GO_VERSION}" ]] && GO_VERSION=$(override_lookup "v${MAJOR}.${MINOR}")
  [[ -z "${GO_VERSION}" ]] && GO_VERSION=$(override_lookup "v${MAJOR}")
fi

# --- 2. Upstream toolchain pinned in source ---------------------------------
extract_pin() {  # $1 = source dir; echoes X.Y.Z from the first matching pin
  local dir="$1" file var val spec
  for spec in \
      "build.assets/versions.mk:GOLANG_VERSION" \
      "build.assets/Makefile:GOLANG_VERSION" \
      "build.assets/Makefile:RUNTIME" \
      "build.assets/images.mk:GOLANG_VERSION"; do
    file="${dir}/${spec%%:*}"; var="${spec##*:}"
    [[ -f "${file}" ]] || continue
    val=$(grep -E "^[[:space:]]*${var}[[:space:]]*[:?]?=" "${file}" 2>/dev/null \
          | grep -oE 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
    [[ -n "${val}" ]] && { echo "${val#go}"; return 0; }
  done
  # v2 era: Go version is hardcoded in the build Dockerfile (no RUNTIME/GOLANG_VERSION var)
  if [[ -f "${dir}/build.assets/Dockerfile" ]]; then
    val=$(grep -oE 'go[0-9]+\.[0-9]+(\.[0-9]+)?' "${dir}/build.assets/Dockerfile" 2>/dev/null | sort -V | tail -1 || true)
    [[ -n "${val}" ]] && { echo "${val#go}"; return 0; }
  fi
  return 1
}
if [[ -z "${GO_VERSION}" && -n "${SOURCE_DIR}" ]]; then
  GO_VERSION=$(extract_pin "${SOURCE_DIR}" || true)
fi

# --- 3. go.mod language floor (last resort) ---------------------------------
if [[ -z "${GO_VERSION}" && -n "${SOURCE_DIR}" && -f "${SOURCE_DIR}/go.mod" ]]; then
  GO_VERSION=$(awk '/^go /{print $2; exit}' "${SOURCE_DIR}/go.mod")
fi

# --- 4. Fallback ------------------------------------------------------------
[[ -z "${GO_VERSION}" ]] && GO_VERSION="1.16"

GO_MAJOR="${GO_VERSION%%.*}"
GO_MINOR="${GO_VERSION#*.}"; GO_MINOR="${GO_MINOR%%.*}"

# --- 5. Cap to GVM source-compile ceiling; toolchain auto-download fetches exact ---
if [[ "${GO_MAJOR}" == "1" && "${GO_MINOR}" -gt "${GVM_COMPILE_CEILING_MINOR}" ]]; then
  echo "go${GO_VERSION} exceeds GVM compile ceiling 1.${GVM_COMPILE_CEILING_MINOR}; installing ceiling, GOTOOLCHAIN=auto will fetch the exact toolchain" >&2
  GO_VERSION="1.${GVM_COMPILE_CEILING_MINOR}"
  GO_MINOR="${GVM_COMPILE_CEILING_MINOR}"
fi

# --- 6. Platform minimums - some Go versions lack support for certain OS/arch ---
# GO_OS, GO_ARCH, GO_ARM are set by the workflow matrix.

# darwin/arm64 requires Go 1.16+ (Apple Silicon support added in 1.16)
if [[ "${GO_OS:-}" == "darwin" && "${GO_MINOR}" -lt 16 ]]; then
  echo "Platform minimum: darwin requires Go 1.16+ (resolved ${GO_VERSION}), bumping" >&2
  GO_VERSION="1.16"; GO_MINOR="16"
fi

# darwin + Go <1.21: the macos runner linker is incompatible (Go issue #61229).
# Originally only Go 1.17-1.20 broke on Xcode 15 (1.16 still linked via -ld_classic).
# Xcode 16.3 then REMOVED the classic linker, so the -ld_classic workaround in build.sh
# is now inert and Go 1.16 CGO linking silently crashes too (compiles all deps, then the
# final link exits 1 with no output). Go 1.21+ has the real fix and needs no classic ld.
# So bump the entire broken range — anything below 1.21 — up to 1.21.
if [[ "${GO_OS:-}" == "darwin" && "${GO_MINOR}" -lt 21 ]]; then
  echo "Platform minimum: darwin Go ${GO_VERSION} incompatible with modern Xcode linker, bumping to 1.21" >&2
  GO_VERSION="1.21"; GO_MINOR="21"
fi

# armhf (GOARM=6) cross-compile requires Go 1.10+ (Go 1.8-1.9 runtime objects use the
# wrong float ABI, causing a VFP register mismatch at link time)
if [[ "${GO_ARCH:-}" == "arm" && "${GO_ARM:-}" == "6" && "${GO_MINOR}" -lt 10 ]]; then
  echo "Platform minimum: armhf cross-compile requires Go 1.10+ (resolved ${GO_VERSION}), bumping" >&2
  GO_VERSION="1.10"; GO_MINOR="10"
fi

echo "${GO_VERSION}"
