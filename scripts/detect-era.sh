#!/bin/bash
# detect-era.sh — Given a teleport version tag, output the era (1-5)
# Usage: detect-era.sh v3.2.1 → outputs "1"
set -euo pipefail

VERSION="${1:?Usage: detect-era.sh <version>}"

# Strip leading 'v'
VER="${VERSION#v}"

# Extract major version
MAJOR="${VER%%.*}"

# Validate MAJOR is numeric
if [[ ! "${MAJOR}" =~ ^[0-9]+$ ]]; then
  echo "Error: invalid version format '${VERSION}' (major='${MAJOR}')" >&2
  exit 1
fi

if [[ "${MAJOR}" -le 4 ]]; then
  echo "1"
elif [[ "${MAJOR}" -le 9 ]]; then
  echo "2"
elif [[ "${MAJOR}" -le 11 ]]; then
  echo "3"
elif [[ "${MAJOR}" -le 14 ]]; then
  echo "4"
else
  echo "5"
fi
