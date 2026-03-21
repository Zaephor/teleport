#!/bin/bash
# build-webassets.sh — Build teleport web UI assets for full/upstream variants
# Must run before build.sh so that webassets/teleport/ exists for go:embed
# Environment variables: REF_PWD, UPSTREAM
set -eo pipefail

SOURCE_DIR="${REF_PWD}/go/src/${UPSTREAM}"

# Check if this version supports webassets embedding
# v11+ has webassets_embed.go at root with //go:embed webassets/teleport
if [[ ! -f "${SOURCE_DIR}/webassets_embed.go" ]]; then
  echo "WARNING: webassets_embed.go not found — this version doesn't support embedded web assets"
  exit 0
fi

# Detect package manager: pnpm (v15+) or yarn (v11-v14)
# The package.json is at the repo root (monorepo), not in web/
if [[ ! -f "${SOURCE_DIR}/package.json" ]]; then
  echo "WARNING: package.json not found at repo root — skipping webassets build"
  exit 0
fi

echo "=== Building web assets"

# --- Install system dependencies ---
echo "::group::Install system dependencies"
if command -v apt-get &>/dev/null; then
  apt-get update -qq 2>/dev/null || true
  apt-get install -y -qq curl ca-certificates xz-utils make git gcc g++ pkg-config libssl-dev 2>/dev/null || true
fi
echo "::endgroup::"

# --- Install Node.js ---
NODE_VERSION=""
if [[ -f "${SOURCE_DIR}/.nvmrc" ]]; then
  NODE_VERSION=$(cat "${SOURCE_DIR}/.nvmrc" | tr -d 'v \n')
  echo "Node version from .nvmrc: ${NODE_VERSION}"
fi

if ! command -v node &>/dev/null || [[ -n "${NODE_VERSION}" ]]; then
  echo "::group::Install Node.js"
  if [[ -z "${NODE_VERSION}" ]]; then
    NODE_VERSION="20"
  fi

  NODE_MAJOR="${NODE_VERSION%%.*}"

  if command -v node &>/dev/null; then
    : # already available (macOS runners have Node.js pre-installed)
  elif command -v brew &>/dev/null; then
    brew install node
  elif command -v apt-get &>/dev/null; then
    ARCH_NODE=""
    case "$(uname -m)" in
      x86_64)  ARCH_NODE="x64" ;;
      aarch64) ARCH_NODE="arm64" ;;
      armv7l)  ARCH_NODE="armv7l" ;;
      *)       ARCH_NODE="x64" ;;
    esac
    NODE_DL_VER="${NODE_VERSION}"
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

# --- Install package manager and build ---
cd "${SOURCE_DIR}"

if [[ -f "pnpm-lock.yaml" ]]; then
  # v15+: pnpm monorepo — needs Rust/WASM toolchain for ironrdp-wasm
  echo "::group::Install pnpm"
  if command -v corepack &>/dev/null; then
    corepack enable
    corepack prepare --activate 2>/dev/null || corepack prepare pnpm@latest --activate 2>/dev/null || true
  else
    npm install -g pnpm 2>/dev/null || true
  fi
  echo "pnpm: $(pnpm --version)"
  echo "::endgroup::"

  # Install Rust toolchain for wasm build (build-ironrdp-wasm)
  # Pin CARGO_HOME/RUSTUP_HOME so paths are consistent regardless of $HOME
  # (in CI docker actions, $HOME=/github/home but euid home is /root)
  export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
  export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
  echo "::group::Install Rust toolchain"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
  export PATH="${CARGO_HOME}/bin:${PATH}"
  rustup target add wasm32-unknown-unknown
  echo "Rust: $(rustc --version)"
  echo "::endgroup::"

  # Use upstream Makefile which handles wasm-bindgen, wasm-opt, pnpm deps, and build
  # CI=true is required so Makefile auto-installs wasm-bindgen-cli instead of just warning
  echo "::group::Build web UI (make ensure-webassets)"
  CI=true make ensure-webassets 2>&1 || {
    echo "WARNING: make ensure-webassets failed, falling back to pnpm build-ui-oss"
    pnpm install --frozen-lockfile 2>/dev/null || pnpm install 2>/dev/null || true
    pnpm build-ui-oss 2>/dev/null || true
  }
  echo "::endgroup::"

elif [[ -f "yarn.lock" ]]; then
  # v11-v14: yarn (predates wasm requirement)
  echo "::group::Install yarn"
  npm install -g yarn 2>/dev/null || true
  echo "yarn: $(yarn --version)"
  echo "::endgroup::"

  echo "::group::yarn install"
  yarn install --frozen-lockfile 2>/dev/null || yarn install 2>/dev/null || true
  echo "::endgroup::"

  echo "::group::Build web UI (yarn)"
  yarn build-ui-oss 2>/dev/null || true
  echo "::endgroup::"

else
  echo "WARNING: No lockfile found (pnpm-lock.yaml or yarn.lock) — trying make"
  echo "::group::Build web UI (make)"
  make -C web build 2>/dev/null || true
  echo "::endgroup::"
fi

# --- Strip source maps (save ~50MB+ in the binary) ---
echo "::group::Strip source maps"
find webassets/ -name '*.map' -delete 2>/dev/null || true
echo "::endgroup::"

# --- Report ---
if [[ -d "webassets/teleport" ]] && [[ -n "$(ls -A webassets/teleport/ 2>/dev/null)" ]]; then
  ASSETS_SIZE=$(du -sh webassets/teleport/ | cut -f1)
  ASSETS_COUNT=$(find webassets/teleport/ -type f | wc -l)
  echo "=== Web assets built successfully (${ASSETS_SIZE}, ${ASSETS_COUNT} files)"
else
  echo "ERROR: webassets/teleport/ is missing or empty after build"
  echo "The full/upstream variant will NOT include web UI."
  ls -la webassets/ 2>/dev/null || echo "  (webassets/ does not exist)"
  exit 1
fi
