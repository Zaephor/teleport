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

# ARCH_NAME comes from matrix name (e.g. linux-amd64-full) — strip variant suffix to get clean arch
BUILD_VARIANT="${BUILD_VARIANT:-}"
CLEAN_ARCH="${ARCH_NAME%-upstream}"
CLEAN_ARCH="${CLEAN_ARCH%-lite}"

# Map arch names to upstream tarball naming convention
# CLEAN_ARCH uses Debian names (armhf, i386) but upstream Gravitational uses arm, 386
# Keep CLEAN_ARCH intact for DEB/RPM where Debian names are correct
TARBALL_ARCH="${CLEAN_ARCH}"
case "${TARBALL_ARCH}" in
  *-armhf) TARBALL_ARCH="${TARBALL_ARCH%-armhf}-arm" ;;
  *-i386)  TARBALL_ARCH="${TARBALL_ARCH%-i386}-386" ;;
  *-386)   TARBALL_ARCH="${TARBALL_ARCH%-386}-386" ;;
esac

# Tarball naming: upstream matches gravitational CDN convention
case "${BUILD_VARIANT}" in
  upstream) PLATFORM_NAME="${TARBALL_ARCH}-bin" ;;
  lite)     PLATFORM_NAME="${TARBALL_ARCH}-lite" ;;
  *)        echo "ERROR: Unknown BUILD_VARIANT '${BUILD_VARIANT}'" >&2; exit 1 ;;
esac

# DEB/RPM: variant goes in package name, not arch
case "${BUILD_VARIANT}" in
  upstream) PKG_NAME="teleport" ;;
  lite)     PKG_NAME="teleport-lite" ;;
esac

echo "=== Packaging ${VERSION} for ${PLATFORM_NAME}"

# All known teleport binaries
TELEPORT_BINARIES=(teleport tctl tsh tbot teleport-update fdpass-teleport)

# Set permissions (skip on Windows — no chmod needed for .exe)
if [[ "${OS}" != "windows" ]]; then
  for x in "${TELEPORT_BINARIES[@]}"; do
    if [[ -e "${DIST_DIR}/teleport/${x}" ]]; then
      chmod +x "${DIST_DIR}/teleport/${x}"
    fi
  done
fi

# Create archive
if [[ "${OS}" == "windows" ]]; then
  # ZIP for Windows — use PowerShell (zip not available on Windows runners)
  cd "${DIST_DIR}"
  ARCHIVE="teleport-${VERSION}-${PLATFORM_NAME}.zip"
  if command -v zip &>/dev/null; then
    zip -r "${ARTIFACTS_DIR}/${ARCHIVE}" teleport/
  elif command -v powershell.exe &>/dev/null; then
    powershell.exe -NoProfile -Command "Compress-Archive -Path 'teleport' -DestinationPath '${ARTIFACTS_DIR}/${ARCHIVE}' -Force"
  elif command -v 7z &>/dev/null; then
    7z a "${ARTIFACTS_DIR}/${ARCHIVE}" teleport/
  else
    echo "ERROR: No zip tool available (tried zip, powershell, 7z)"
    exit 1
  fi
  echo "Created ${ARCHIVE}"
else
  # tar.gz for Linux and macOS
  # Include upstream install script and LICENSE in tarball
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "${SCRIPT_DIR}/install" ]]; then
    cp "${SCRIPT_DIR}/install" "${DIST_DIR}/teleport/install"
    chmod +x "${DIST_DIR}/teleport/install"
  fi
  if [[ -f "${BASE_DIR}/LICENSE" ]]; then
    cp "${BASE_DIR}/LICENSE" "${DIST_DIR}/teleport/LICENSE"
  fi
  rm -rf "${DIST_DIR}/teleport/examples"
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
  NFPM_TOOL_VERSION="2.45.2"
  NFPM_TMP_DL=$(mktemp -d)
  trap "rm -rf ${NFPM_TMP_DL}" RETURN 2>/dev/null || true
  curl -fsSL "https://github.com/goreleaser/nfpm/releases/download/v${NFPM_TOOL_VERSION}/nfpm_${NFPM_TOOL_VERSION}_Linux_x86_64.tar.gz" -o "${NFPM_TMP_DL}/nfpm.tar.gz"
  tar -xf "${NFPM_TMP_DL}/nfpm.tar.gz" -C "${BASE_DIR}/bin" nfpm
  rm -rf "${NFPM_TMP_DL}"
  chmod +x "${BASE_DIR}/bin/nfpm"
  NFPM_BIN="${BASE_DIR}/bin/nfpm"
  echo "::endgroup::"
fi

# Prepare nfpm tmp directory — copy all available binaries
NFPM_TMP="${BASE_DIR}/tmp"
mkdir -p "${NFPM_TMP}"
for x in "${TELEPORT_BINARIES[@]}"; do
  if [[ -e "${DIST_DIR}/teleport/${x}" ]]; then
    cp "${DIST_DIR}/teleport/${x}" "${NFPM_TMP}/"
  fi
done

NFPM_TEMPLATE="${CI_DIR}/nfpm.yaml"
if [[ ! -f "${NFPM_TEMPLATE}" ]]; then
  echo "Warning: nfpm template not found at ${NFPM_TEMPLATE}, skipping DEB/RPM"
  exit 0
fi

# Copy service files to BASE_DIR where nfpm runs (nfpm.yaml references them with ./ paths)
cp "${CI_DIR}/systemd-teleport.service" "${BASE_DIR}/systemd-teleport.service"
cp "${CI_DIR}/upstart-teleport.conf" "${BASE_DIR}/upstart-teleport.conf"

# Generate maintainer scripts: use upstream teleport-update if available, otherwise fallback
SCRIPTS_DIR="${CI_DIR}/scripts"
if [[ -e "${NFPM_TMP}/teleport-update" ]]; then
  cp "${SCRIPTS_DIR}/postinst.sh" "${NFPM_TMP}/postinst.sh"
  cp "${SCRIPTS_DIR}/prerm.sh" "${NFPM_TMP}/prerm.sh"
  # RPM no-op postinstall: RPM uses posttrans instead of postinstall
  cat > "${NFPM_TMP}/rpm-postinst-noop.sh" <<'RPM_NOOP'
#!/bin/bash
# No-op: RPM uses posttrans instead of postinstall
RPM_NOOP
else
  # Fallback postinst: create symlinks manually
  cat > "${NFPM_TMP}/postinst.sh" <<'POSTINST'
#!/bin/bash
set -eu
for bin in /opt/teleport/system/bin/*; do
  [ -f "$bin" ] && [ -x "$bin" ] && ln -sf "$bin" "/usr/local/bin/$(basename "$bin")"
done
POSTINST

  # Fallback prerm: remove symlinks on package removal
  cat > "${NFPM_TMP}/prerm.sh" <<'PRERM'
#!/bin/bash
set -eu
case "${1:-}" in
  remove|0)
    for bin in /opt/teleport/system/bin/*; do
      name=$(basename "$bin")
      [ -L "/usr/local/bin/$name" ] && rm -f "/usr/local/bin/$name"
    done
    ;;
esac
PRERM

  # RPM no-op postinstall: RPM uses posttrans instead of postinstall
  cat > "${NFPM_TMP}/rpm-postinst-noop.sh" <<'RPM_NOOP'
#!/bin/bash
# No-op: RPM uses posttrans instead of postinstall
RPM_NOOP
fi
chmod +x "${NFPM_TMP}/postinst.sh" "${NFPM_TMP}/prerm.sh" "${NFPM_TMP}/rpm-postinst-noop.sh"

# Generate nfpm config: start from template, append binary entries dynamically
NFPM_CONFIG="${BASE_DIR}/nfpm-generated.yaml"
# nfpm expects version without 'v' prefix for proper deb/rpm versioning
NFPM_VERSION="${VERSION#v}"
# nfpm expects Debian arch names (amd64, arm64, armhf) — use CLEAN_ARCH to avoid variant pollution
NFPM_ARCH="${CLEAN_ARCH#linux-}"
NFPM_ARCH="${NFPM_ARCH#darwin-}"
NFPM_ARCH="${NFPM_ARCH#windows-}"
# Map Go arch names to Debian arch names
case "${NFPM_ARCH}" in
  i386|386) NFPM_ARCH="i386" ;;
  armhf)    NFPM_ARCH="armhf" ;;
  armel)    NFPM_ARCH="armel" ;;
esac
sed -e "s#%VERSION%#${NFPM_VERSION}#g" -e "s#%ARCH%#${NFPM_ARCH}#g" -e "s#%NAME%#${PKG_NAME}#g" "${NFPM_TEMPLATE}" > "${NFPM_CONFIG}"

# Append binary entries for each binary found in tmp/
for x in "${TELEPORT_BINARIES[@]}"; do
  if [[ -e "${NFPM_TMP}/${x}" ]]; then
    cat >> "${NFPM_CONFIG}" <<EOF
  - src: ./tmp/${x}
    dst: /opt/teleport/system/bin/${x}
    file_info:
      mode: 0755
EOF
  fi
done

# Build DEB and RPM
echo "::group::build DEB"
"${NFPM_BIN}" package -f "${NFPM_CONFIG}" -p deb -t "${ARTIFACTS_DIR}/" 2>&1
echo "::endgroup::"

echo "::group::build RPM"
"${NFPM_BIN}" package -f "${NFPM_CONFIG}" -p rpm -t "${ARTIFACTS_DIR}/" 2>&1
echo "::endgroup::"

# Cleanup
rm -rf "${NFPM_TMP}" "${NFPM_CONFIG}"
rm -f "${BASE_DIR}/systemd-teleport.service" "${BASE_DIR}/upstart-teleport.conf"

echo "=== Packaging complete"
ls -la "${ARTIFACTS_DIR}/"
