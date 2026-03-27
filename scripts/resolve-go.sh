#!/bin/bash
# resolve-go.sh — Given a teleport version, resolve the required Go version
# Checks: 1) golang.override (major.minor match), 2) golang.override (major match),
#          3) go.mod from source, 4) fallback to 1.16
# Usage: resolve-go.sh v4.3.0 [source_dir] [ci_dir]
set -euo pipefail

VERSION="${1:?Usage: resolve-go.sh <version> [source_dir] [ci_dir]}"

# Validate version format (must start with v followed by digit)
if [[ ! "${VERSION}" =~ ^v[0-9] ]]; then
  echo "Warning: unusual version format '${VERSION}'" >&2
fi

SOURCE_DIR="${2:-}"
CI_DIR="${3:-.}"

# Strip leading 'v'
VER="${VERSION#v}"
MAJOR="${VER%%.*}"
if [[ "${VER}" == *.* ]]; then
  MINOR="${VER#*.}"
  MINOR="${MINOR%%.*}"
else
  MINOR="0"
fi
PATCH=""
if [[ "${VER}" == *.*.* ]]; then
  PATCH="${VER##*.}"
fi

OVERRIDE_FILE="${CI_DIR}/golang.override"
GO_VERSION=""

# 1) Try major.minor.patch match in golang.override (e.g. v3.1.16)
if [[ -n "${PATCH}" && -f "${OVERRIDE_FILE}" ]]; then
  GO_VERSION=$(grep "^v${MAJOR}.${MINOR}.${PATCH}," "${OVERRIDE_FILE}" | cut -d',' -f2 | head -1 || true)
fi

# 2) Try major.minor match in golang.override (e.g. v3.1)
if [[ -z "${GO_VERSION}" && -f "${OVERRIDE_FILE}" ]]; then
  GO_VERSION=$(grep "^v${MAJOR}.${MINOR}," "${OVERRIDE_FILE}" | cut -d',' -f2 | head -1 || true)
fi

# 3) Try major-only match in golang.override (e.g. v3)
if [[ -z "${GO_VERSION}" && -f "${OVERRIDE_FILE}" ]]; then
  GO_VERSION=$(grep "^v${MAJOR}," "${OVERRIDE_FILE}" | cut -d',' -f2 | head -1 || true)
fi

# 3) Try go.mod from source
if [[ -z "${GO_VERSION}" && -n "${SOURCE_DIR}" && -f "${SOURCE_DIR}/go.mod" ]]; then
  GO_VERSION=$(awk '/^go /{print $NF}' "${SOURCE_DIR}/go.mod")
fi

# 4) Fallback
if [[ -z "${GO_VERSION}" ]]; then
  GO_VERSION="1.16"
fi

# 5) Platform minimums — some Go versions lack support for certain OS/arch
# GO_OS and GO_ARCH are set by the workflow matrix
GO_MAJOR="${GO_VERSION%%.*}"
GO_MINOR="${GO_VERSION#*.}"
GO_MINOR="${GO_MINOR%%.*}"

# darwin/arm64 requires Go 1.16+ (Apple Silicon support added in 1.16)
if [[ "${GO_OS:-}" == "darwin" && "${GO_MINOR}" -lt 16 ]]; then
  echo "Platform minimum: darwin requires Go 1.16+ (resolved ${GO_VERSION}), bumping" >&2
  GO_VERSION="1.16"
fi

# darwin + Go 1.17-1.20: Xcode 15 linker is incompatible (Go issue #61229)
# macos-13 is retired; macos-14 ships Xcode 15 which silently crashes Go 1.17-1.20 CGO linking.
# Go 1.16 works (simpler linker integration), Go 1.21+ has the fix. Only bump the broken range.
if [[ "${GO_OS:-}" == "darwin" && "${GO_MINOR}" -ge 17 && "${GO_MINOR}" -lt 21 ]]; then
  echo "Platform minimum: darwin Go ${GO_VERSION} incompatible with Xcode 15 linker, bumping to 1.21" >&2
  GO_VERSION="1.21"
fi

# armhf (GOARM=6) cross-compile requires Go 1.10+ (Go 1.8-1.9 runtime objects
# use wrong float ABI, causing VFP register mismatch at link time)
if [[ "${GO_ARCH:-}" == "arm" && "${GO_ARM:-}" == "6" && "${GO_MINOR}" -lt 10 ]]; then
  echo "Platform minimum: armhf cross-compile requires Go 1.10+ (resolved ${GO_VERSION}), bumping" >&2
  GO_VERSION="1.10"
fi

echo "${GO_VERSION}"
