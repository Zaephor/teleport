#!/bin/bash
# smoke-test.sh — Validate built binaries have correct architecture and can launch
# Environment variables: GO_OS, GO_ARCH, REF_PWD, BUILD_VARIANT (optional)
set -eo pipefail

DIST_DIR="${REF_PWD}/dist/teleport"

if [[ ! -d "${DIST_DIR}" ]]; then
  echo "WARNING: dist directory not found at ${DIST_DIR}, skipping smoke test"
  exit 0
fi

FAIL=0

# --- Architecture validation ---
echo "=== Smoke test: architecture validation (${GO_OS}/${GO_ARCH})"

if ! command -v file &>/dev/null; then
  echo "WARNING: 'file' command not available, skipping architecture check"
else
  for bin in "${DIST_DIR}"/*; do
    [[ -f "${bin}" ]] || continue
    NAME=$(basename "${bin}")

    # Skip non-binary files
    case "${NAME}" in
      VERSION|*.md|*.yaml|*.yml|*.txt|*.conf|*.service) continue ;;
    esac
    # Skip directories (examples/)
    [[ -d "${bin}" ]] && continue

    FILE_OUT=$(file "${bin}")
    echo "  ${NAME}: ${FILE_OUT}"

    # Determine expected pattern based on OS and arch
    EXPECTED=""
    case "${GO_OS}" in
      linux)
        case "${GO_ARCH}" in
          amd64)  EXPECTED="x86-64" ;;
          386)    EXPECTED="Intel 80386" ;;
          arm64)  EXPECTED="aarch64" ;;
          arm)    EXPECTED="ARM," ;;
        esac
        ;;
      darwin)
        case "${GO_ARCH}" in
          amd64)  EXPECTED="x86_64" ;;
          arm64)  EXPECTED="arm64" ;;
        esac
        ;;
      windows)
        case "${GO_ARCH}" in
          amd64)  EXPECTED="x86-64" ;;
          386)    EXPECTED="Intel 80386" ;;
        esac
        ;;
    esac

    if [[ -z "${EXPECTED}" ]]; then
      echo "  WARNING: no expected arch pattern for ${GO_OS}/${GO_ARCH}, skipping"
      continue
    fi

    if echo "${FILE_OUT}" | grep -q "${EXPECTED}"; then
      echo "  OK: ${NAME} matches expected arch (${EXPECTED})"
    else
      echo "  FAIL: ${NAME} does not match expected arch (wanted '${EXPECTED}')"
      FAIL=1
    fi
  done
fi

# --- Build variant size check ---
BUILD_VARIANT="${BUILD_VARIANT:-}"
if [[ -n "${BUILD_VARIANT}" && -f "${DIST_DIR}/teleport" ]]; then
  TELEPORT_SIZE=$(stat -c%s "${DIST_DIR}/teleport" 2>/dev/null || stat -f%z "${DIST_DIR}/teleport" 2>/dev/null || echo "0")
  TELEPORT_SIZE_MB=$((TELEPORT_SIZE / 1048576))
  echo "=== Smoke test: variant size check (variant=${BUILD_VARIANT}, teleport=${TELEPORT_SIZE_MB}MB)"
  if [[ "${BUILD_VARIANT}" == "full" ]]; then
    if [[ "${TELEPORT_SIZE_MB}" -lt 250 ]]; then
      echo "  FAIL: full variant teleport binary is only ${TELEPORT_SIZE_MB}MB (expected >250MB with webassets)"
      FAIL=1
    else
      echo "  OK: full variant size ${TELEPORT_SIZE_MB}MB"
    fi
  elif [[ "${BUILD_VARIANT}" == "edge" ]]; then
    if [[ "${TELEPORT_SIZE_MB}" -gt 200 ]]; then
      echo "  FAIL: edge variant teleport binary is ${TELEPORT_SIZE_MB}MB (expected <200MB without webassets)"
      FAIL=1
    else
      echo "  OK: edge variant size ${TELEPORT_SIZE_MB}MB"
    fi
  fi
fi

# --- Launch test (linux-amd64 native only) ---
if [[ "${GO_OS}" == "linux" && "${GO_ARCH}" == "amd64" && "$(uname -m 2>/dev/null)" == "x86_64" ]]; then
  echo "=== Smoke test: launch test (native linux-amd64)"
  for bin in "${DIST_DIR}"/*; do
    [[ -f "${bin}" && -x "${bin}" ]] || continue
    NAME=$(basename "${bin}")

    # Skip non-binary files
    case "${NAME}" in
      VERSION|*.md|*.yaml|*.yml|*.txt|*.conf|*.service) continue ;;
    esac
    [[ -d "${bin}" ]] && continue

    # Try --version first, fall back to version
    echo "::group::Launch test: ${NAME}"
    if "${bin}" --version 2>&1; then
      echo "::endgroup::"
      echo "  OK: ${NAME} --version succeeded"
    elif "${bin}" version 2>&1; then
      echo "::endgroup::"
      echo "  OK: ${NAME} version succeeded"
    else
      echo "::endgroup::"
      echo "  FAIL: ${NAME} failed to launch"
      FAIL=1
    fi
  done
fi

if [[ "${FAIL}" -ne 0 ]]; then
  echo "=== Smoke test FAILED"
  exit 1
fi

echo "=== Smoke test passed"
