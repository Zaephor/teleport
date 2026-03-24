#!/bin/bash
# prep.sh — Architecture-aware dependency installation
# Refactored from root prep.sh with darwin/windows support
# Environment variables: GO_OS, GO_ARCH, GO_ARM, REF_NAME, REF_PWD
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "== Prep: ${GO_OS:-linux}/${GO_ARCH:-amd64}"

# darwin/windows cross-compile: install minimal deps only (curl for GVM/Go download)
if [[ "${GO_OS:-linux}" == "darwin" || "${GO_OS:-linux}" == "windows" ]]; then
  echo "::group::Cross-compile deps for ${GO_OS}/${GO_ARCH}"
  apt-get -y update && apt-get -f -y install curl git bison gcc make binutils bsdmainutils || true
  echo "::endgroup::"
  mkdir -p "${REF_PWD:-${PWD}}/dist/teleport"
  exit 0
fi

# Create sudo shim if missing (old containers)
if [[ ! -e /usr/bin/sudo ]]; then
  echo "::group::sudo lazy shim"
  echo '#!/bin/sh' > /usr/bin/sudo
  echo '"$@"' >> /usr/bin/sudo
  chmod +x /usr/bin/sudo
  echo "::endgroup::"
fi

mkdir -p "${REF_PWD:-${PWD}}/dist/teleport"

echo "::group::apt-get update"
sudo apt-get -y update
echo "::endgroup::"

echo "::group::install base packages"
sudo apt-get -f -y install curl wget git zip libpam0g-dev binutils bison gcc make \
  binutils-multiarch build-essential bsdmainutils || true
echo "::endgroup::"

# Ubuntu 14.04 needs binutils-2.26 for gold linker
if [[ -f /etc/os-release ]]; then
  VERSION_ID=$(awk -F'[="]+' '/^VERSION_ID/{print $2}' /etc/os-release)
  if [[ "${VERSION_ID}" == "14.04" ]]; then
    echo "::group::install binutils-2.26 (trusty)"
    sudo apt-get -f -y install binutils-2.26 || true
    echo "::endgroup::"
  fi
fi

echo "::group::install arch-specific packages"
case "${GO_ARCH:-amd64}" in
  amd64)
    sudo apt-get -f -y install libc6-dev
    ;;
  386)
    sudo apt-get -f -y install gcc-multilib libc6-dev-i386
    ;;
  arm64)
    sudo apt-get -f -y install libc6-arm64-cross libc6-dev-arm64-cross \
      gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu || true
    ;;
  arm)
    if [[ "${GO_ARM:-6}" == "6" ]]; then
      sudo dpkg --add-architecture armhf 2>/dev/null || true
      sudo apt-get -y update || true
      sudo apt-get -f -y install libc6-armhf-cross libc6-dev-armhf-cross \
        gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf lld || true
    fi
    if [[ "${GO_ARM:-6}" == "5" ]]; then
      sudo dpkg --add-architecture armel 2>/dev/null || true
      sudo apt-get -y update || true
      sudo apt-get -f -y install libc6-armel-cross libc6-dev-armel-cross \
        gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi lld || true
    fi
    ;;
esac
echo "::endgroup::"

echo "::group::postinstall"
which ld || true
echo "::endgroup::"
