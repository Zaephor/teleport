#!/bin/bash
# build-rdpclient.sh — Build the Rust rdp-client static library for a target arch
# Runs as a pre-step job (like build-webassets.sh) to produce librdp_client.a
# Environment variables: REF_PWD, UPSTREAM, GO_ARCH (amd64|arm64)
set -eo pipefail

SOURCE_DIR="${REF_PWD}/go/src/${UPSTREAM}"
GO_ARCH="${GO_ARCH:-amd64}"

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "ERROR: Source directory not found at ${SOURCE_DIR}"
  exit 1
fi

cd "${SOURCE_DIR}"

# Check if this version has rdp-client (v8+)
if ! grep -q 'rdp-client' Cargo.toml 2>/dev/null && ! grep -q 'rdp-client' Cargo.lock 2>/dev/null; then
  echo "=== No rdp-client crate in this version, skipping"
  exit 0
fi

# Determine Rust target
case "${GO_ARCH}" in
  amd64) RUST_TARGET="x86_64-unknown-linux-gnu" ;;
  arm64) RUST_TARGET="aarch64-unknown-linux-gnu" ;;
  *)
    echo "=== RDP client not supported on ${GO_ARCH}, skipping"
    exit 0
    ;;
esac

# --- Install system dependencies ---
echo "::group::Install build dependencies"
apt-get update -qq 2>/dev/null || true
apt-get install -y -qq curl ca-certificates gcc make pkg-config 2>/dev/null || true
if [[ "${GO_ARCH}" == "arm64" ]]; then
  apt-get install -y -qq gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu 2>/dev/null || true
fi
echo "::endgroup::"

# --- Install Rust toolchain ---
echo "::group::Install Rust toolchain"
export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
export PATH="${CARGO_HOME}/bin:${PATH}"
if [[ "${GO_ARCH}" == "arm64" ]]; then
  rustup target add aarch64-unknown-linux-gnu
fi
echo "Rust: $(rustc --version)"
echo "::endgroup::"

# --- Configure cross-linker for arm64 ---
if [[ "${GO_ARCH}" == "arm64" ]]; then
  mkdir -p "${HOME}/.cargo"
  cat > "${HOME}/.cargo/config.toml" <<TOML
[target.aarch64-unknown-linux-gnu]
linker = "aarch64-linux-gnu-gcc"
TOML
fi

# --- Build ---
echo "::group::Build rdp-client (${RUST_TARGET})"
cargo build -p rdp-client --release --locked --target "${RUST_TARGET}" 2>&1 || {
  echo "WARNING: rdp-client build failed"
  echo "::endgroup::"
  exit 1
}
echo "::endgroup::"

# --- Output ---
LIB_PATH="target/${RUST_TARGET}/release/librdp_client.a"

if [[ ! -f "${LIB_PATH}" ]]; then
  echo "ERROR: librdp_client.a not found after build"
  exit 1
fi

OUTPUT_DIR="${REF_PWD}/rdpclient"
mkdir -p "${OUTPUT_DIR}"
cp "${LIB_PATH}" "${OUTPUT_DIR}/librdp_client.a"

# cbindgen generates the header during cargo build (via build.rs)
# Header name and location vary across teleport versions:
#   v18+: lib/srv/desktop/rdp/rdpclient/librdpclient.h
#   v10-v17: lib/srv/desktop/rdp/rdpclient/librdprs.h (older name)
# Search for it dynamically
HEADER=""
for candidate in \
  "lib/srv/desktop/rdp/rdpclient/librdpclient.h" \
  "lib/srv/desktop/rdp/rdpclient/librdprs.h"; do
  if [[ -f "${candidate}" ]]; then
    HEADER="${candidate}"
    break
  fi
done

if [[ -z "${HEADER}" ]]; then
  # Last resort: find any generated .h in the rdpclient crate
  HEADER=$(find lib/srv/desktop/rdp/rdpclient -name '*.h' -print -quit 2>/dev/null || true)
fi

if [[ -n "${HEADER}" && -f "${HEADER}" ]]; then
  cp "${HEADER}" "${OUTPUT_DIR}/$(basename "${HEADER}")"
  echo "=== rdp-client built: ${RUST_TARGET} (lib + header: $(basename "${HEADER}"))"
else
  echo "WARNING: rdp-client library built but no header found — copying lib only"
  echo "=== rdp-client built: ${RUST_TARGET} (lib only, no header)"
fi
