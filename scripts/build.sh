#!/bin/bash
# build.sh — Build teleport binaries
# Refactored from root build.sh with darwin/windows and PAM support
# Environment variables:
#   GO_VERSION, GO_OS, GO_ARCH, GO_ARM, GO_EXPERIMENT
#   CC, REF_PWD, REF_VER, UPSTREAM, PAM (true/false)
#   BUILD_METHOD (go-build|make-release, default: go-build)
set -eo pipefail

IFS=$'\n'

# Source GVM if available
# GVM scripts reference unbound variables; disable strict modes for sourcing
_SAVED_GOPATH="${GOPATH:-}"
if [[ -f "${REF_PWD}/gvm/scripts/gvm" ]]; then
  set +eo pipefail 2>/dev/null || true
  source "${REF_PWD}/gvm/scripts/gvm" 2>/dev/null || true
  gvm use "go${GO_VERSION}" --default 2>/dev/null || true
  set -eo pipefail
  # GVM installs a 'cd' wrapper that can interfere with navigation;
  # remove it so the shell builtin is used directly
  unset -f cd 2>/dev/null || true
fi
# Restore GOPATH if it was set (GVM overrides it)
if [[ -n "${_SAVED_GOPATH}" ]]; then
  export GOPATH="${_SAVED_GOPATH}"
fi

echo "=== Build: ${GO_OS}/${GO_ARCH} (version ${REF_VER})"

# Add binutils-2.26 to PATH if available (ubuntu:14.04)
if [[ -d "/usr/lib/binutils-2.26/bin" ]]; then
  export PATH="/usr/lib/binutils-2.26/bin:$PATH"
fi

export GOOS="${GO_OS}"
export GOARCH="${GO_ARCH}"
if [[ -n "${GO_ARM:-}" ]]; then export GOARM="${GO_ARM}"; fi
if [[ -n "${GO_EXPERIMENT:-}" && "${GO_VERSION:-}" == 1.20* ]]; then
  export GOEXPERIMENT="${GO_EXPERIMENT}"
fi

# CGO settings
if [[ "${GO_OS}" == "darwin" || "${GO_OS}" == "windows" ]]; then
  export CGO_ENABLED=0
elif [[ "${GOHOSTARCH:-$(go env GOHOSTARCH)}" != "${GO_ARCH}" ]]; then
  export CGO_ENABLED=1
fi
if [[ -n "${CC:-}" ]]; then
  export CC="${CC}"
  export CGO_ENABLED=1
fi

# Build tags
BUILD_TAGS=""
if [[ "${PAM:-true}" == "true" && "${GO_OS}" == "linux" ]]; then
  BUILD_TAGS="pam"
fi

# Linker flag combinations to try (some fail on certain toolchains)
# For CGO_ENABLED=0 (darwin/windows), extldflags are irrelevant — use simple flags only
if [[ "${CGO_ENABLED:-1}" == "0" ]]; then
  FLAGS=('-s -w' '-s' '-w' '')
else
  FLAGS=(
    '-s -w'
    '-s -w -extldflags "--long-plt"'
    '-s -w -extldflags "--no-plt"'
    '-s -w -extldflags "-fuse-ld=gold"'
    '-s -w -extldflags "-fuse-ld=gold --long-plt"'
    '-s -w -extldflags "-fuse-ld=gold --no-plt"'
    '-s'
    '-w'
    ''
  )
fi

SOURCE_DIR="${REF_PWD}/go/src/${UPSTREAM}"
mkdir -p "${REF_PWD}/dist/teleport"

git config --global --add safe.directory "${SOURCE_DIR}"
cd "${SOURCE_DIR}"

echo "::group::go env"
go env
echo "::endgroup::"

# Build method
BUILD_METHOD="${BUILD_METHOD:-go-build}"

if [[ "${BUILD_METHOD}" == "make-release" ]]; then
  echo "::group::make release"
  make release
  echo "::endgroup::"

  # Find and extract the release bundle
  BUNDLE=""
  for f in teleport-*.tar.gz teleport-*.zip; do
    if [[ -f "$f" ]]; then
      BUNDLE="$f"
      break
    fi
  done
  if [[ -n "${BUNDLE}" ]]; then
    tar -xf "${BUNDLE}" -C "${REF_PWD}/dist/" 2>/dev/null || \
      unzip -o "${BUNDLE}" -d "${REF_PWD}/dist/" 2>/dev/null || true
  fi
else
  # Direct go build for each binary
  echo "::group::go clean"
  go clean -modcache 2>/dev/null || true
  echo "::endgroup::"

  echo "::group::go get"
  go get 2>/dev/null || go mod download 2>/dev/null || true
  echo "::endgroup::"

  for x in 'tbot' 'tctl' 'tsh' 'teleport'; do
    if [[ -d "./tool/${x}" ]]; then
      BUILT=false
      for ldflag in "${FLAGS[@]}"; do
        echo "::group::Trying to build ${x} with '${ldflag}'"
        TAG_ARGS=()
        if [[ -n "${BUILD_TAGS}" ]]; then
          TAG_ARGS=(-tags "${BUILD_TAGS}")
        fi
        # shellcheck disable=SC2086
        if go build -v "${TAG_ARGS[@]}" -ldflags="${ldflag}" -o "${REF_PWD}/dist/teleport/${x}" "./tool/${x}"; then
          echo "::endgroup::"
          echo "== ${x} - Success"
          BUILT=true
          break
        fi
        echo "::endgroup::"
        go clean -cache 2>/dev/null || true
      done
      if [[ "${BUILT}" != "true" ]]; then
        if [[ "${GO_OS}" != "linux" ]]; then
          echo "== ${x} - SKIPPED (cross-compile to ${GO_OS}/${GO_ARCH} failed, continuing)"
        else
          echo "== ${x} - FAILED (all linker flag combos exhausted)"
          exit 1
        fi
      fi
    fi
  done
fi

# Write VERSION file and copy examples
echo "${REF_VER}" > "${REF_PWD}/dist/teleport/VERSION"
if [[ -d "${SOURCE_DIR}/examples" ]]; then
  cp -r "${SOURCE_DIR}/examples" "${REF_PWD}/dist/teleport/" 2>/dev/null || true
fi

echo "=== Build complete"
ls -la "${REF_PWD}/dist/teleport/"
