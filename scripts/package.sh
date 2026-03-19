#!/bin/bash
# package.sh — Package teleport binaries into tar.gz/zip/deb/rpm
# Usage: package.sh <version> <os> <arch_name> [ci_dir]
# Environment: REF_PWD (base directory with dist/teleport/)
set -euo pipefail

VERSION="${1:?Usage: package.sh <version> <os> <arch_name> [ci_dir]}"
OS="${2:?Usage: package.sh <version> <os> <arch_name> [ci_dir]}"
ARCH_NAME="${3:?Usage: package.sh <version> <os> <arch_name> [ci_dir]}"
CI_DIR="${4:-.}"

# Save original directory before any cd operations
BASE_DIR="${REF_PWD:-${PWD}}"
DIST_DIR="${BASE_DIR}/dist"
ARTIFACTS_DIR="${BASE_DIR}/artifacts"
mkdir -p "${ARTIFACTS_DIR}"

# ARCH_NAME is already the full platform identifier (e.g. linux-amd64, darwin-arm64)
PLATFORM_NAME="${ARCH_NAME}"

echo "=== Packaging ${VERSION} for ${PLATFORM_NAME}"

# Set permissions
for x in teleport tctl tsh tbot; do
  if [[ -e "${DIST_DIR}/teleport/${x}" ]]; then
    chmod +x "${DIST_DIR}/teleport/${x}"
  fi
done

# Create archive
if [[ "${OS}" == "windows" ]]; then
  # ZIP for Windows
  cd "${DIST_DIR}"
  ARCHIVE="teleport-${VERSION}-${PLATFORM_NAME}.zip"
  zip -r "${ARTIFACTS_DIR}/${ARCHIVE}" teleport/
  echo "Created ${ARCHIVE}"
else
  # tar.gz for Linux and macOS
  cd "${DIST_DIR}"
  ARCHIVE="teleport-${VERSION}-${PLATFORM_NAME}.tar.gz"
  tar czf "${ARTIFACTS_DIR}/${ARCHIVE}" teleport/
  echo "Created ${ARCHIVE}"
fi

# Return to base directory for nfpm
cd "${BASE_DIR}"

# DEB/RPM only for Linux
if [[ "${OS}" != "linux" ]]; then
  echo "Skipping DEB/RPM for ${OS}"
  exit 0
fi

# Check if nfpm is available, install if not
NFPM_BIN=""
if command -v nfpm &>/dev/null; then
  NFPM_BIN="nfpm"
elif [[ -x "${BASE_DIR}/bin/nfpm" ]]; then
  NFPM_BIN="${BASE_DIR}/bin/nfpm"
else
  echo "::group::install nfpm"
  mkdir -p "${BASE_DIR}/bin"
  NFPM_VERSION="2.6.0"
  NFPM_TMP_DL=$(mktemp -d)
  trap "rm -rf ${NFPM_TMP_DL}" RETURN 2>/dev/null || true
  curl -fsSL "https://github.com/goreleaser/nfpm/releases/download/v${NFPM_VERSION}/nfpm_${NFPM_VERSION}_Linux_x86_64.tar.gz" -o "${NFPM_TMP_DL}/nfpm.tar.gz"
  tar -xf "${NFPM_TMP_DL}/nfpm.tar.gz" -C "${BASE_DIR}/bin" nfpm
  rm -rf "${NFPM_TMP_DL}"
  chmod +x "${BASE_DIR}/bin/nfpm"
  NFPM_BIN="${BASE_DIR}/bin/nfpm"
  echo "::endgroup::"
fi

# Prepare nfpm tmp directory
NFPM_TMP="${BASE_DIR}/tmp"
mkdir -p "${NFPM_TMP}"
for x in teleport tctl tsh tbot; do
  if [[ -e "${DIST_DIR}/teleport/${x}" ]]; then
    cp "${DIST_DIR}/teleport/${x}" "${NFPM_TMP}/"
  fi
done

# Determine which nfpm config to use (with or without tbot)
if [[ -e "${NFPM_TMP}/tbot" ]]; then
  NFPM_TEMPLATE="${CI_DIR}/nfpm-tbot.yaml"
else
  NFPM_TEMPLATE="${CI_DIR}/nfpm.yaml"
fi

if [[ ! -f "${NFPM_TEMPLATE}" ]]; then
  echo "Warning: nfpm template not found at ${NFPM_TEMPLATE}, skipping DEB/RPM"
  exit 0
fi

# Ensure ./ci/ is accessible for nfpm (service file paths in nfpm.yaml reference ./ci/)
if [[ ! -d "./ci" && -d "${CI_DIR}" ]]; then
  ln -sf "$(cd "${CI_DIR}" && pwd)" ./ci
fi

# Generate nfpm config with substitutions
NFPM_CONFIG="${BASE_DIR}/nfpm-generated.yaml"
# nfpm expects version without 'v' prefix for proper deb/rpm versioning
NFPM_VERSION="${VERSION#v}"
# nfpm expects Debian arch names (amd64, arm64, armhf), not platform names (linux-amd64)
NFPM_ARCH="${ARCH_NAME#linux-}"
NFPM_ARCH="${NFPM_ARCH#darwin-}"
NFPM_ARCH="${NFPM_ARCH#windows-}"
# Map Go arch names to Debian arch names
case "${NFPM_ARCH}" in
  i386|386) NFPM_ARCH="i386" ;;
  armhf)    NFPM_ARCH="armhf" ;;
  armel)    NFPM_ARCH="armel" ;;
esac
sed -e "s#%VERSION%#${NFPM_VERSION}#g" -e "s#%ARCH%#${NFPM_ARCH}#g" "${NFPM_TEMPLATE}" > "${NFPM_CONFIG}"

# Build DEB and RPM
echo "::group::build DEB"
"${NFPM_BIN}" package -f "${NFPM_CONFIG}" -p deb -t "${ARTIFACTS_DIR}/" 2>&1 || echo "DEB packaging failed (non-fatal)"
echo "::endgroup::"

echo "::group::build RPM"
"${NFPM_BIN}" package -f "${NFPM_CONFIG}" -p rpm -t "${ARTIFACTS_DIR}/" 2>&1 || echo "RPM packaging failed (non-fatal)"
echo "::endgroup::"

# Cleanup
rm -rf "${NFPM_TMP}" "${NFPM_CONFIG}"
# Remove ci symlink if we created it
if [[ -L "./ci" ]]; then
  rm -f "./ci"
fi

echo "=== Packaging complete"
ls -la "${ARTIFACTS_DIR}/"
