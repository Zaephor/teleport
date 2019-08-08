#!/bin/bash
ALL_BASE="${GOPATH}/src/github.com/gravitational/teleport"

TARBALL=$(ls -1 ${ALL_BASE}/teleport*.tar.gz | sed "s@^${ALL_BASE}/@@g")
ZIPBALL=$(ls -1 ${ALL_BASE}/teleport*.zip | sed "s@^${ALL_BASE}/@@g")

if [[ ! -d "${TRAVIS_BUILD_DIR}/artifacts" ]]; then
	mkdir "${TRAVIS_BUILD_DIR}/artifacts"
fi
if [[ -n "${TARBALL}" ]]; then
	VERSION=${APPVEYOR_REPO_TAG_NAME:-$(echo "${TARBALL}" | awk -F '-' '{print $2"-"$3}')}
	NEW_NAME="teleport-${VERSION}-${GOOS}-${ARCH_LABEL}"
	mv "${ALL_BASE}/${TARBALL}" "${TRAVIS_BUILD_DIR}/artifacts/${NEW_NAME}.tar.gz"
fi
if [[ -n "${ZIPBALL}" ]]; then
	VERSION=${APPVEYOR_REPO_TAG_NAME:-$(echo "${ZIPBALL}" | awk -F '-' '{print $2"-"$3}')}
	NEW_NAME="teleport-${VERSION}-${GOOS}-${ARCH_LABEL}"
	mv "${ALL_BASE}/${ZIPBALL}" "${TRAVIS_BUILD_DIR}/artifacts/${NEW_NAME}.zip"
fi
