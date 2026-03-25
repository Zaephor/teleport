#!/bin/bash
# smoke-test.sh — Validate built binaries have correct architecture and can launch
# Environment variables: GO_OS, GO_ARCH, REF_PWD, BUILD_VARIANT, TP_VERSION (optional)
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

  # Determine version-aware minimum size for upstream variant
  # Based on upstream release sizes: v4=46MB tar, v8=65MB, v10=108MB, v14=141MB, v18=197MB
  # Individual uncompressed teleport binary is roughly 60-70% of tarball total
  MAJOR=0
  if [[ -n "${TP_VERSION:-}" ]]; then
    MAJOR=$(echo "${TP_VERSION#v}" | cut -d. -f1)
  fi

  echo "=== Smoke test: variant size check (variant=${BUILD_VARIANT}, teleport=${TELEPORT_SIZE_MB}MB, major=v${MAJOR})"

  case "${BUILD_VARIANT}" in
    upstream)
      # Version-aware minimum: upstream should include web assets
      if [[ "${MAJOR}" -ge 15 ]]; then
        MIN_SIZE_MB=100   # v15+: large UI with WASM
      elif [[ "${MAJOR}" -ge 10 ]]; then
        MIN_SIZE_MB=60    # v10-v14: go:embed webassets
      elif [[ "${MAJOR}" -ge 8 ]]; then
        MIN_SIZE_MB=40    # v8-v9: go:embed webassets (smaller UI)
      elif [[ "${MAJOR}" -ge 5 ]]; then
        MIN_SIZE_MB=20    # v5-v7: zip-append adds some bulk
      elif [[ "${MAJOR}" -ge 2 ]]; then
        MIN_SIZE_MB=10    # v2-v4: small binaries
      else
        MIN_SIZE_MB=5     # unknown version, very lenient
      fi

      if [[ "${TELEPORT_SIZE_MB}" -lt "${MIN_SIZE_MB}" ]]; then
        echo "  FAIL: upstream variant teleport binary is only ${TELEPORT_SIZE_MB}MB (expected >${MIN_SIZE_MB}MB for v${MAJOR})"
        FAIL=1
      else
        echo "  OK: upstream variant size ${TELEPORT_SIZE_MB}MB (min ${MIN_SIZE_MB}MB for v${MAJOR})"
      fi
      ;;
    *)
      # lite: no webassets, just report size
      echo "  OK: ${BUILD_VARIANT} variant size ${TELEPORT_SIZE_MB}MB"
      ;;
  esac
fi

# --- Binary manifest assertions ---
MAJOR=0
if [[ -n "${TP_VERSION:-}" ]]; then
  MAJOR=$(echo "${TP_VERSION#v}" | cut -d. -f1)
fi

if [[ "${MAJOR}" -gt 0 && "${GO_OS}" == "linux" ]]; then
  echo "=== Smoke test: binary manifest assertions (v${MAJOR}, ${GO_OS}/${GO_ARCH})"

  # tbot expected for v9+ on linux
  if [[ "${MAJOR}" -ge 9 ]]; then
    if [[ -f "${DIST_DIR}/tbot" ]]; then
      echo "  OK: tbot present (expected for v${MAJOR})"
    else
      echo "  FAIL: tbot missing (expected for v${MAJOR}+ on linux)"
      FAIL=1
    fi
  fi

  # fdpass-teleport expected for v16+ on linux amd64/arm64
  if [[ "${MAJOR}" -ge 16 && ( "${GO_ARCH}" == "amd64" || "${GO_ARCH}" == "arm64" ) ]]; then
    if [[ -f "${DIST_DIR}/fdpass-teleport" ]]; then
      echo "  OK: fdpass-teleport present (expected for v${MAJOR})"
    else
      echo "  FAIL: fdpass-teleport missing (expected for v${MAJOR}+ on linux ${GO_ARCH})"
      FAIL=1
    fi
  fi

  # teleport-update expected for v17+ on linux
  if [[ "${MAJOR}" -ge 17 ]]; then
    if [[ -f "${DIST_DIR}/teleport-update" ]]; then
      echo "  OK: teleport-update present (expected for v${MAJOR})"
    else
      echo "  FAIL: teleport-update missing (expected for v${MAJOR}+ on linux)"
      FAIL=1
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

    # Try --version first, fall back to version subcommand.
    # fdpass-teleport is a Rust helper with no --version; running it with no
    # args prints usage and exits 1 — that still proves it launches.
    echo "::group::Launch test: ${NAME}"
    if "${bin}" --version 2>&1; then
      echo "::endgroup::"
      echo "  OK: ${NAME} --version succeeded"
    elif "${bin}" version 2>&1; then
      echo "::endgroup::"
      echo "  OK: ${NAME} version succeeded"
    elif OUTPUT=$("${bin}" 2>&1) || [[ -n "${OUTPUT}" ]]; then
      echo "${OUTPUT}"
      echo "::endgroup::"
      echo "  OK: ${NAME} launched (no version flag, but produced output)"
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
