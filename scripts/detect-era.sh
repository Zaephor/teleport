#!/bin/bash
# detect-era.sh — Given a teleport version tag, output the era (1-9)
# Usage: detect-era.sh v3.2.1 → outputs "3"
set -euo pipefail

VERSION="${1:?Usage: detect-era.sh <version>}"

# Strip leading 'v'
VER="${VERSION#v}"

# Extract major and minor version
MAJOR="${VER%%.*}"
MINOR="${VER#*.}"
MINOR="${MINOR%%.*}"

# Validate MAJOR is numeric
if [[ ! "${MAJOR}" =~ ^[0-9]+$ ]]; then
  echo "Error: invalid version format '${VERSION}' (major='${MAJOR}')" >&2
  exit 1
fi

# Era 1: v2.0-v2.2 (linux-only — vendored deps lack arm64/darwin/windows support)
if [[ "${MAJOR}" -eq 2 && "${MINOR}" -lt 3 ]]; then
  echo "1"
# Era 2: v2.3 (linux + darwin + arm64, no Windows — logrus case collision)
elif [[ "${MAJOR}" -eq 2 && "${MINOR}" -eq 3 ]]; then
  echo "2"
# Era 3: v2.4-v4 (full platform matrix, GOPATH builds)
elif [[ "${MAJOR}" -le 4 ]]; then
  echo "3"
elif [[ "${MAJOR}" -le 7 ]]; then
  echo "4"
elif [[ "${MAJOR}" -le 9 ]]; then
  echo "5"
elif [[ "${MAJOR}" -le 11 ]]; then
  echo "6"
elif [[ "${MAJOR}" -le 15 ]]; then
  echo "7"
elif [[ "${MAJOR}" -eq 16 ]]; then
  echo "8"
else
  echo "9"
fi
