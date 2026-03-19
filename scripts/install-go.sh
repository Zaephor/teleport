#!/bin/bash
# install-go.sh — Install Go via GVM with bootstrap chain
# go1.4 → go1.17.13 → go1.20.14 → target
# Usage: install-go.sh <go_version> [gvm_dir]
set -eo pipefail

GO_VERSION="${1:?Usage: install-go.sh <go_version>}"
GVM_DIR="${2:-${PWD}/gvm}"

# Install GVM if not present
if [[ ! -d "${GVM_DIR}" ]]; then
  echo "::group::install gvm"
  GVM_VERSION="master"
  curl -fsSL "https://raw.githubusercontent.com/moovweb/gvm/${GVM_VERSION}/binscripts/gvm-installer" -o gvm-installer
  bash gvm-installer master "$(dirname "${GVM_DIR}")"
  rm -f gvm-installer
  echo "::endgroup::"
fi

# Fix git ownership issues from cache restoration (different runner UID)
git config --global --add safe.directory '*' 2>/dev/null || true

# GVM scripts may reference unbound variables and return non-zero;
# temporarily disable all strict modes for sourcing
set +euo pipefail 2>/dev/null || true
source "${GVM_DIR}/scripts/gvm" 2>/dev/null || true
set -eo pipefail

# Determine which bootstrap steps are needed
# Go 1.4 can compile up to Go 1.19
# Go 1.17.13 can compile up to Go 1.21
# Go 1.20.14 can compile anything newer

install_if_needed() {
  local ver="$1"
  local binary="${2:-false}"
  if gvm list 2>/dev/null | grep -q "go${ver}"; then
    echo "go${ver} already installed"
    gvm use "go${ver}"
    return 0
  fi
  echo "::group::install go${ver}"
  if [[ "${binary}" == "true" ]]; then
    gvm install "go${ver}" -B
  else
    export GOROOT_BOOTSTRAP=$GOROOT
    gvm install "go${ver}"
  fi
  gvm use "go${ver}"
  echo "::endgroup::"
}

# Compare versions: returns 0 if $1 >= $2
version_ge() {
  printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# Bootstrap chain — use binary downloads for bootstrap versions
# Prebuilt binaries are available and avoid compilation issues across containers
install_if_needed "1.4" true

if version_ge "${GO_VERSION}" "1.18"; then
  install_if_needed "1.17.13" true
fi

if version_ge "${GO_VERSION}" "1.21"; then
  install_if_needed "1.20.14" true
fi

# Install target version
# Temporarily unset CC to use host compiler — cross-compilers (e.g., aarch64-linux-gnu-gcc)
# don't understand host flags like -m64 that Go's build system passes
if ! gvm list 2>/dev/null | grep -q "go${GO_VERSION}"; then
  echo "::group::install go${GO_VERSION}"
  export GOROOT_BOOTSTRAP=$GOROOT
  _SAVED_CC="${CC:-}"
  unset CC
  set +e
  gvm install "go${GO_VERSION}"
  if [[ $? -ne 0 ]]; then
    echo "Failed to compile go${GO_VERSION}, check logs"
    cat "${GVM_DIR}/logs/go-go${GO_VERSION}-compile.log" 2>/dev/null || true
    exit 1
  fi
  set -e
  if [[ -n "${_SAVED_CC}" ]]; then export CC="${_SAVED_CC}"; fi
  echo "::endgroup::"
fi

gvm use "go${GO_VERSION}" --default
echo "Go ${GO_VERSION} installed and active"
