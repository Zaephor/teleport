#!/bin/bash
# build-webassets.sh — Prepare teleport web UI assets for upstream variant
# Handles three eras of web asset bundling:
#   v10+:  Build from source (yarn/pnpm monorepo) → go:embed via root webassets_embed.go
#   v8-v9: Fetch from git submodule (pre-built) → go:embed via lib/web/static_embed.go
#   v2-v7: Fetch from git submodule (pre-built) → zip-append in build.sh
# Environment variables: REF_PWD, UPSTREAM
set -eo pipefail

SOURCE_DIR="${REF_PWD}/go/src/${UPSTREAM}"

# ===================================================================
# Detect which webassets era we're in
# ===================================================================
WEBASSETS_ERA=""

if [[ -f "${SOURCE_DIR}/webassets_embed.go" ]]; then
  # v10+: root-level go:embed, build from source
  WEBASSETS_ERA="modern"
  echo "=== Detected modern webassets (root webassets_embed.go)"
elif [[ -f "${SOURCE_DIR}/lib/web/static_embed.go" ]]; then
  # v8-v9: lib/web go:embed, pre-built from submodule
  WEBASSETS_ERA="embed-submodule"
  echo "=== Detected v8-v9 webassets (lib/web/static_embed.go, submodule)"
elif [[ -f "${SOURCE_DIR}/.gitmodules" ]] && grep -q "webassets" "${SOURCE_DIR}/.gitmodules" 2>/dev/null; then
  # v2-v7: zip-append method, pre-built from submodule
  WEBASSETS_ERA="zip-submodule"
  echo "=== Detected legacy webassets (zip-append, submodule)"
else
  echo "WARNING: No webassets support detected — this version has no web console"
  exit 0
fi

# ===================================================================
# Submodule-based eras (v2-v9): init submodule to get pre-built assets
# ===================================================================
if [[ "${WEBASSETS_ERA}" == "embed-submodule" || "${WEBASSETS_ERA}" == "zip-submodule" ]]; then
  echo "::group::Init webassets submodule"

  # Install git + zip if not available (docker containers)
  if ! command -v git &>/dev/null || ! command -v zip &>/dev/null; then
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq git ca-certificates zip 2>/dev/null || true
  fi

  cd "${SOURCE_DIR}"
  git config --global --add safe.directory "${SOURCE_DIR}"

  # Init ONLY the webassets submodule (not 'e' which is gravitational's private enterprise repo)
  git submodule init -- webassets 2>&1 || true

  # Convert SSH URLs to HTTPS for CI (submodule may use git@github.com: syntax)
  SUBMOD_URL=$(git config --file .gitmodules submodule.webassets.url 2>/dev/null || echo "")
  if [[ "${SUBMOD_URL}" == git@github.com:* ]]; then
    HTTPS_URL="https://github.com/${SUBMOD_URL#git@github.com:}"
    git config submodule.webassets.url "${HTTPS_URL}"
  fi

  git submodule update --depth 1 -- webassets 2>&1 || {
    echo "Submodule update failed, trying manual clone"
    SUBMOD_PATH=$(git config --file .gitmodules submodule.webassets.path 2>/dev/null || echo "webassets")
    SUBMOD_REF=$(git ls-tree HEAD "${SUBMOD_PATH}" 2>/dev/null | awk '{print $3}' || echo "")
    # Build HTTPS clone URL
    CLONE_URL="${SUBMOD_URL}"
    if [[ "${CLONE_URL}" == git@github.com:* ]]; then
      CLONE_URL="https://github.com/${CLONE_URL#git@github.com:}"
    fi
    rm -rf "${SUBMOD_PATH}"
    if [[ -n "${CLONE_URL}" ]]; then
      git clone --depth 1 "${CLONE_URL}" "${SUBMOD_PATH}" 2>&1 || true
      if [[ -n "${SUBMOD_REF}" && -d "${SUBMOD_PATH}" ]]; then
        cd "${SUBMOD_PATH}"
        git fetch origin "${SUBMOD_REF}" --depth 1 2>/dev/null || true
        git checkout "${SUBMOD_REF}" 2>/dev/null || true
        cd "${SOURCE_DIR}"
      fi
    fi
  }
  echo "::endgroup::"

  # For v8-v9 embed-submodule: copy assets to where go:embed expects them
  if [[ "${WEBASSETS_ERA}" == "embed-submodule" ]]; then
    echo "::group::Copy assets for lib/web go:embed"
    # The embed directive in lib/web/static_embed.go typically references build/webassets
    if [[ -d "webassets/teleport" ]]; then
      mkdir -p lib/web/build/webassets
      cp -r webassets/teleport/* lib/web/build/webassets/ 2>/dev/null || true
      echo "Copied webassets/teleport/ → lib/web/build/webassets/"
    fi
    echo "::endgroup::"
  fi

  # Report
  if [[ -d "webassets/teleport" ]] && [[ -n "$(ls -A webassets/teleport/ 2>/dev/null)" ]]; then
    ASSETS_SIZE=$(du -sh webassets/teleport/ | cut -f1)
    ASSETS_COUNT=$(find webassets/teleport/ -type f | wc -l)
    echo "=== Web assets from submodule (${ASSETS_SIZE}, ${ASSETS_COUNT} files)"
  else
    echo "ERROR: webassets/teleport/ missing after submodule init"
    echo "  The upstream variant requires web assets to be a 1:1 drop-in replacement."
    ls -la webassets/ 2>/dev/null || echo "  (webassets/ does not exist)"
    exit 1
  fi
  exit 0
fi

# ===================================================================
# Modern era (v10+): build from source
# ===================================================================
if [[ ! -f "${SOURCE_DIR}/package.json" ]]; then
  echo "WARNING: package.json not found at repo root — skipping webassets build"
  exit 0
fi

echo "=== Building web assets from source"

# --- Detect pinned Rust version from source ---
# v18.7.5+ moved the pin from build.assets/versions.mk to the canonical
# rust-toolchain.toml at repo root. Check both so we stay compatible across
# upstream versions. Use `grep ... || true` so a missing line does not trip
# pipefail and silently exit the script.
RUST_TOOLCHAIN="stable"
if [[ -f "${SOURCE_DIR}/rust-toolchain.toml" ]]; then
  PINNED_RUST=$(grep -E '^\s*channel\s*=' "${SOURCE_DIR}/rust-toolchain.toml" | head -1 | sed -E 's/.*=\s*"?([^"[:space:]]+)"?.*/\1/' || true)
  if [[ -n "${PINNED_RUST}" ]]; then
    RUST_TOOLCHAIN="${PINNED_RUST}"
    echo "=== Detected pinned Rust version from rust-toolchain.toml: ${RUST_TOOLCHAIN}"
  fi
fi
if [[ "${RUST_TOOLCHAIN}" == "stable" && -f "${SOURCE_DIR}/build.assets/versions.mk" ]]; then
  PINNED_RUST=$(grep "^RUST_VERSION" "${SOURCE_DIR}/build.assets/versions.mk" | head -1 | sed 's/.*?= *//;s/ .*//' || true)
  if [[ -n "${PINNED_RUST}" ]]; then
    RUST_TOOLCHAIN="${PINNED_RUST}"
    echo "=== Detected pinned Rust version from versions.mk: ${RUST_TOOLCHAIN}"
  fi
fi

# --- Install system dependencies ---
echo "::group::Install system dependencies"
if command -v apt-get &>/dev/null; then
  apt-get update -qq 2>/dev/null || true
  apt-get install -y -qq curl ca-certificates xz-utils make git gcc g++ pkg-config libssl-dev python3 2>/dev/null || true
fi
echo "::endgroup::"

# --- Install Node.js ---
# Determine the required Node version straight from upstream, in order of
# authority, so we never maintain a hardcoded version table:
#   1. .nvmrc                        — a pinned full version, if upstream ships one
#   2. package.json "engines.node"   — the declared supported range (e.g. "^24")
#   3. fallback default              — last resort only
# A pinned pnpm in "packageManager" sets a hard floor: pnpm 11+ loads the
# node:sqlite builtin and requires Node >= 22. If upstream's declared Node is
# somehow below that floor, bump it — otherwise corepack activation crashes:
#   Error [ERR_UNKNOWN_BUILTIN_MODULE]: No such built-in module: node:sqlite
# which aborts the install and makes vite die on missing devDeps
# (rollup-plugin-visualizer, jsdom).
DEFAULT_NODE_MAJOR=20
NODE_VERSION=""

if [[ -f "${SOURCE_DIR}/.nvmrc" ]]; then
  NODE_VERSION=$(cat "${SOURCE_DIR}/.nvmrc" | tr -d 'v \n')
  echo "=== Node version from .nvmrc: ${NODE_VERSION}"
fi

if [[ -z "${NODE_VERSION}" && -f "${SOURCE_DIR}/package.json" ]]; then
  # Pull the first integer out of the engines.node range ("^24" -> 24,
  # ">=22.0.0" -> 22). The -A window scopes the match to the engines block so
  # we don't accidentally read a version from elsewhere in package.json.
  ENGINE_NODE_MAJOR=$(grep -A3 '"engines"' "${SOURCE_DIR}/package.json" 2>/dev/null \
    | grep -oE '"node"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | grep -oE '[0-9]+' | head -1 || true)
  if [[ -n "${ENGINE_NODE_MAJOR}" ]]; then
    NODE_VERSION="${ENGINE_NODE_MAJOR}"
    echo "=== Node major from package.json engines.node: ${NODE_VERSION}"
  fi
fi

if [[ -z "${NODE_VERSION}" ]]; then
  NODE_VERSION="${DEFAULT_NODE_MAJOR}"
  echo "=== No Node version declared upstream; defaulting to ${NODE_VERSION}"
fi

# pnpm floor: pnpm 11+ needs Node >= 22.
PNPM_PIN_MAJOR=$(grep -oE '"packageManager"[[:space:]]*:[[:space:]]*"pnpm@[0-9]+' "${SOURCE_DIR}/package.json" 2>/dev/null | grep -oE '[0-9]+$' || true)
if [[ -n "${PNPM_PIN_MAJOR}" && "${PNPM_PIN_MAJOR}" -ge 11 && "${NODE_VERSION%%.*}" -lt 22 ]]; then
  echo "=== Pinned pnpm@${PNPM_PIN_MAJOR} requires Node >= 22; bumping ${NODE_VERSION} -> 22"
  NODE_VERSION="22"
fi

# Decide whether the (possibly preinstalled) Node is new enough. A runner with
# preinstalled Node 20 must be overridden when a newer major is required.
NODE_NEEDS_INSTALL=1
if command -v node &>/dev/null; then
  CUR_NODE_MAJOR=$(node --version | sed -E 's/^v?([0-9]+).*/\1/')
  if [[ -n "${CUR_NODE_MAJOR}" && "${CUR_NODE_MAJOR}" -ge "${NODE_VERSION%%.*}" ]]; then
    NODE_NEEDS_INSTALL=0
  else
    echo "=== Preinstalled Node v${CUR_NODE_MAJOR} < required v${NODE_VERSION%%.*}; installing newer"
  fi
fi

if [[ "${NODE_NEEDS_INSTALL}" == "1" ]]; then
  echo "::group::Install Node.js"
  NODE_MAJOR="${NODE_VERSION%%.*}"

  if command -v brew &>/dev/null; then
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
        # Last-resort fallback if the dist listing is unreachable: the X.0.0
        # release of the requested major. Stays at the right major (so a
        # pnpm@11 pin never regresses to node:sqlite) without a hardcoded list.
        NODE_DL_VER="${NODE_MAJOR}.0.0"
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
  # Verify pnpm actually runs. A version mismatch (e.g. a pinned pnpm@11 on
  # Node < 22) makes corepack activate a pnpm that crashes on every invocation
  # with node:sqlite. Fail here with a clear message instead of limping into a
  # silently-skipped install and a confusing vite failure 2 minutes later.
  if ! PNPM_VER=$(pnpm --version 2>&1); then
    echo "ERROR: pnpm is not runnable after setup."
    echo "  Node: $(node --version)   pinned pnpm: ${PNPM_PIN_MAJOR:-none}"
    echo "  pnpm output: ${PNPM_VER}"
    exit 1
  fi
  echo "pnpm: ${PNPM_VER}"
  echo "::endgroup::"

  # Install Rust toolchain for wasm build (build-ironrdp-wasm)
  # Pin CARGO_HOME/RUSTUP_HOME so paths are consistent regardless of $HOME
  # (in CI docker actions, $HOME=/github/home but euid home is /root)
  export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
  export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
  echo "::group::Install Rust toolchain"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "${RUST_TOOLCHAIN}"
  export PATH="${CARGO_HOME}/bin:${PATH}"
  rustup target add wasm32-unknown-unknown
  # Prebuilt wasm-pack (cargo install wasm-pack fails with old Rust + new crates.io)
  curl -fsSL https://rustwasm.github.io/wasm-pack/installer/init.sh | sh
  echo "Rust: $(rustc --version)"
  echo "wasm-pack: $(wasm-pack --version)"
  echo "::endgroup::"

  echo "::group::pnpm install"
  # Fail loud: a broken install must abort the build, not get swallowed and
  # surface later as a missing-devDep vite error. Try frozen-lockfile first
  # (reproducible); on lockfile drift, retry unfrozen; if that also fails, the
  # unguarded failure trips `set -e` and the script exits non-zero.
  if ! pnpm install --frozen-lockfile; then
    echo "WARNING: 'pnpm install --frozen-lockfile' failed (lockfile drift?); retrying without --frozen-lockfile"
    pnpm install
  fi
  echo "::endgroup::"

  # Build WASM directly, then vite — same approach as yarn+wasm path
  # "make ensure-webassets" and "pnpm build-ui-oss" both run "cargo install --locked
  # wasm-bindgen-cli" which fails due to crates.io transitive dep edition drift
  echo "::group::Build WASM (wasm-pack)"
  IRONRDP_DIR=""
  for candidate in "web/packages/teleport/src/ironrdp" "web/packages/shared/libs/ironrdp"; do
    if [[ -d "${candidate}" && -f "${candidate}/Cargo.toml" ]]; then
      IRONRDP_DIR="${candidate}"
      break
    fi
  done
  if [[ -n "${IRONRDP_DIR}" ]]; then
    echo "=== Building ironrdp WASM from ${IRONRDP_DIR}"
    wasm-pack build "${IRONRDP_DIR}" --target web
  else
    echo "WARNING: ironrdp directory not found — skipping WASM build"
  fi
  echo "::endgroup::"

  echo "::group::Build web UI (vite)"
  cd web/packages/teleport
  npx vite build
  cd "${SOURCE_DIR}"
  echo "::endgroup::"

elif [[ -f "yarn.lock" ]]; then
  # v10-v16.1: yarn monorepo
  echo "::group::Install yarn"
  npm install -g yarn 2>/dev/null || true
  echo "yarn: $(yarn --version)"
  echo "::endgroup::"

  # v15+ yarn projects need Rust/WASM for ironrdp (build-wasm target)
  # The project's package.json build-wasm script does "cargo install --locked wasm-bindgen-cli"
  # which can't compile with current crates.io due to transitive dep edition drift.
  # Instead: install Rust + prebuilt wasm-pack, build WASM directly, then run vite.
  if grep -rq "build-wasm" web/packages/teleport/package.json 2>/dev/null; then
    export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
    export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
    echo "::group::Install Rust toolchain (yarn+wasm)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "${RUST_TOOLCHAIN}"
    export PATH="${CARGO_HOME}/bin:${PATH}"
    rustup target add wasm32-unknown-unknown
    # Prebuilt wasm-pack (cargo install wasm-pack fails with old Rust + new crates.io)
    curl -fsSL https://rustwasm.github.io/wasm-pack/installer/init.sh | sh
    echo "Rust: $(rustc --version)"
    echo "wasm-pack: $(wasm-pack --version)"
    echo "::endgroup::"

    echo "::group::yarn install"
    yarn install --frozen-lockfile 2>/dev/null || yarn install 2>/dev/null || true
    echo "::endgroup::"

    echo "::group::Build WASM (wasm-pack)"
    # ironrdp location moved across versions
    IRONRDP_DIR=""
    for candidate in "web/packages/teleport/src/ironrdp" "web/packages/shared/libs/ironrdp"; do
      if [[ -d "${candidate}" && -f "${candidate}/Cargo.toml" ]]; then
        IRONRDP_DIR="${candidate}"
        break
      fi
    done
    if [[ -n "${IRONRDP_DIR}" ]]; then
      echo "=== Building ironrdp WASM from ${IRONRDP_DIR}"
      wasm-pack build "${IRONRDP_DIR}" --target web
    else
      echo "WARNING: ironrdp directory not found — skipping WASM build"
    fi
    echo "::endgroup::"

    echo "::group::Build web UI (vite)"
    cd web/packages/teleport
    npx vite build
    cd "${SOURCE_DIR}"
    echo "::endgroup::"
  else
    echo "::group::yarn install"
    yarn install --frozen-lockfile 2>/dev/null || yarn install 2>/dev/null || true
    echo "::endgroup::"

    echo "::group::Build web UI (yarn)"
    yarn build-ui-oss 2>/dev/null || true
    echo "::endgroup::"
  fi

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
  echo "The upstream variant will NOT include web UI."
  ls -la webassets/ 2>/dev/null || echo "  (webassets/ does not exist)"
  exit 1
fi
