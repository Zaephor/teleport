#!/bin/bash
# build-webassets.sh — Build teleport web UI assets for the "full" build variant
# Must run inside the build container before build.sh
# Environment variables: REF_PWD, UPSTREAM
set -eo pipefail

SOURCE_DIR="${REF_PWD}/go/src/${UPSTREAM}"

# Check if web/ directory exists (older versions don't have it)
if [[ ! -f "${SOURCE_DIR}/web/package.json" ]]; then
  echo "WARNING: web/package.json not found — skipping webassets build (old teleport version?)"
  echo "The webassets_embed tag will be harmless on versions without embed files."
  exit 0
fi

echo "=== Building web assets"

# --- Install Node.js ---
# Check for .nvmrc or package.json engines field
NODE_VERSION=""
if [[ -f "${SOURCE_DIR}/.nvmrc" ]]; then
  NODE_VERSION=$(cat "${SOURCE_DIR}/.nvmrc" | tr -d 'v \n')
  echo "Node version from .nvmrc: ${NODE_VERSION}"
fi

# Install Node.js via NodeSource or pre-built binaries
if ! command -v node &>/dev/null || [[ -n "${NODE_VERSION}" ]]; then
  echo "::group::Install Node.js"
  if [[ -z "${NODE_VERSION}" ]]; then
    NODE_VERSION="20"
  fi

  # Use major version for NodeSource setup
  NODE_MAJOR="${NODE_VERSION%%.*}"

  # Try multiple installation methods
  if command -v node &>/dev/null; then
    : # already available (macOS runners have Node.js pre-installed)
  elif command -v brew &>/dev/null; then
    brew install node
  elif command -v apt-get &>/dev/null; then
    # Debian/Ubuntu: install from NodeSource or download binary
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq curl ca-certificates 2>/dev/null || true

    # Download pre-built Node.js binary
    ARCH_NODE=""
    case "$(uname -m)" in
      x86_64)  ARCH_NODE="x64" ;;
      aarch64) ARCH_NODE="arm64" ;;
      armv7l)  ARCH_NODE="armv7l" ;;
      *)       ARCH_NODE="x64" ;;
    esac
    NODE_DL_VER="${NODE_VERSION}"
    # If only major version, resolve to latest LTS
    if [[ ! "${NODE_DL_VER}" =~ \. ]]; then
      NODE_DL_VER=$(curl -fsSL "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/" 2>/dev/null | grep -oP 'node-v\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
      if [[ -z "${NODE_DL_VER}" ]]; then
        NODE_DL_VER="20.11.0"
      fi
    fi
    curl -fsSL "https://nodejs.org/dist/v${NODE_DL_VER}/node-v${NODE_DL_VER}-linux-${ARCH_NODE}.tar.xz" -o /tmp/node.tar.xz
    tar -xf /tmp/node.tar.xz -C /usr/local --strip-components=1
    rm -f /tmp/node.tar.xz
  fi
  echo "::endgroup::"
fi

echo "Node.js: $(node --version)"
echo "npm: $(npm --version)"

# --- Install pnpm via corepack ---
echo "::group::Install pnpm"
if command -v corepack &>/dev/null; then
  corepack enable
  corepack prepare --activate 2>/dev/null || corepack prepare pnpm@latest --activate 2>/dev/null || true
else
  npm install -g pnpm 2>/dev/null || true
fi
echo "pnpm: $(pnpm --version)"
echo "::endgroup::"

# --- Install web dependencies ---
echo "::group::pnpm install"
cd "${SOURCE_DIR}"

# Some versions use yarn instead of pnpm
if [[ -f "yarn.lock" && ! -f "pnpm-lock.yaml" ]]; then
  echo "Detected yarn.lock (no pnpm-lock.yaml) — using yarn"
  npm install -g yarn 2>/dev/null || true
  yarn install --frozen-lockfile 2>/dev/null || yarn install 2>/dev/null || true
  echo "::endgroup::"

  echo "::group::Build web UI (yarn)"
  yarn build-ui-oss 2>/dev/null || make -C web build 2>/dev/null || true
  echo "::endgroup::"
else
  pnpm install --frozen-lockfile 2>/dev/null || pnpm install 2>/dev/null || true
  echo "::endgroup::"

  echo "::group::Build web UI (pnpm)"
  pnpm build-ui-oss 2>/dev/null || make -C web build 2>/dev/null || true
  echo "::endgroup::"
fi

# --- Strip source maps ---
echo "::group::Strip source maps"
find webassets/ -name '*.map' -delete 2>/dev/null || true
echo "::endgroup::"

# --- Report ---
if [[ -d "webassets/teleport" ]]; then
  echo "=== Web assets built successfully"
  du -sh webassets/teleport/
else
  echo "WARNING: webassets/teleport/ directory not found after build"
  echo "The full variant may not include web UI. Listing webassets/:"
  ls -la webassets/ 2>/dev/null || echo "  (webassets/ does not exist)"
fi
