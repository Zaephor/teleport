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

OVERRIDE_FILE="${CI_DIR}/golang.override"
GO_VERSION=""

# 1) Try major.minor match in golang.override
if [[ -f "${OVERRIDE_FILE}" ]]; then
  GO_VERSION=$(grep "^v${MAJOR}.${MINOR}," "${OVERRIDE_FILE}" | cut -d',' -f2 | head -1 || true)
fi

# 2) Try major-only match in golang.override
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

# darwin requires Go 1.21+ (Xcode 15+ linker compatibility, Go issue #61229)
# macos-13 is retired; macos-14 ships Xcode 15 which breaks Go < 1.21 CGO linking
if [[ "${GO_OS:-}" == "darwin" && "${GO_MINOR}" -lt 21 ]]; then
  echo "Platform minimum: darwin requires Go 1.21+ for Xcode 15 linker (resolved ${GO_VERSION}), bumping" >&2
  GO_VERSION="1.21"
fi

echo "${GO_VERSION}"
