#!/bin/bash
# build-fdpass.sh — Build the fdpass-teleport Rust binary for a target arch
# Runs as a pre-step job to produce the fdpass-teleport binary
# Environment variables: REF_PWD, UPSTREAM, GO_ARCH (amd64|arm64)
set -eo pipefail

SOURCE_DIR="${REF_PWD}/go/src/${UPSTREAM}"
GO_ARCH="${GO_ARCH:-amd64}"

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "ERROR: Source directory not found at ${SOURCE_DIR}"
  exit 1
fi

cd "${SOURCE_DIR}"

# Check if this version has fdpass-teleport
if [[ ! -f "tool/fdpass-teleport/Cargo.toml" ]]; then
  echo "=== No fdpass-teleport in this version, skipping"
  exit 0
fi

# Determine Rust target
case "${GO_ARCH}" in
  amd64) RUST_TARGET="x86_64-unknown-linux-gnu" ;;
  arm64) RUST_TARGET="aarch64-unknown-linux-gnu" ;;
  *)
    echo "=== fdpass-teleport not supported on ${GO_ARCH}, skipping"
    exit 0
    ;;
esac

# --- Install system dependencies ---
echo "::group::Install build dependencies"
apt-get update -qq 2>/dev/null || true
apt-get install -y -qq curl ca-certificates gcc make 2>/dev/null || true
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
# Use env var — config file search starts from cwd, not manifest dir,
# so .cargo/config.toml in the crate directory is not found
if [[ "${GO_ARCH}" == "arm64" ]]; then
  export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
fi

# --- Build ---
echo "::group::Build fdpass-teleport (${RUST_TARGET})"
cargo build \
  --manifest-path tool/fdpass-teleport/Cargo.toml \
  --release --locked --target "${RUST_TARGET}" 2>&1 || {
  echo "WARNING: fdpass-teleport build failed"
  echo "::endgroup::"
  exit 1
}
echo "::endgroup::"

# --- Output ---
BIN_PATH="tool/fdpass-teleport/target/${RUST_TARGET}/release/fdpass-teleport"
# Cargo may also place it at the workspace target dir
ALT_BIN_PATH="target/${RUST_TARGET}/release/fdpass-teleport"

FOUND_BIN=""
if [[ -f "${BIN_PATH}" ]]; then
  FOUND_BIN="${BIN_PATH}"
elif [[ -f "${ALT_BIN_PATH}" ]]; then
  FOUND_BIN="${ALT_BIN_PATH}"
fi

if [[ -n "${FOUND_BIN}" ]]; then
  OUTPUT_DIR="${REF_PWD}/fdpass"
  mkdir -p "${OUTPUT_DIR}"
  cp "${FOUND_BIN}" "${OUTPUT_DIR}/fdpass-teleport"
  echo "=== fdpass-teleport built: ${RUST_TARGET} ($(stat -c%s "${FOUND_BIN}" 2>/dev/null || stat -f%z "${FOUND_BIN}") bytes)"
else
  echo "ERROR: fdpass-teleport binary not found after build"
  echo "  Checked: ${BIN_PATH}"
  echo "  Checked: ${ALT_BIN_PATH}"
  exit 1
fi
