#!/bin/bash
eval $(go env | sed -r 's/^(set )?(\w+)=("?)(.*)\3$/\2="\4"/gm')
ARCH_LABEL="${1}"
LATEST="$(cat LATEST)"

## Func
function _log {
	echo "==== ${@}"
}

# General Setup
OPWD=$(pwd)
BUILD_TAG=${GITHUB_REF##*/}
BUILD_TARGET=${BUILD_TAG:-${LATEST}}
_log "Ref: ${GITHUB_REF##*/}"
_log "Latest: ${LATEST}"
_log "Build Target: ${BUILD_TARGET}"
_log "Build Arch: ${ARCH_LABEL}"

# Arch stuff
case "${ARCH_LABEL}" in
	"i386")
		export GOOS=linux
		export GOARCH=386
		sudo apt-get -f -y install gcc-multilib libc6-dev-i386
		;;
	"amd64")
		export GOOS=linux
		export GOARCH=amd64
		;;
	"armel")
		export GOOS=linux
		export GOARCH=arm
		export GOARM=5
		export CC=arm-linux-gnueabi-gcc
		sudo apt-get -f -y install gcc-arm-linux-gnueabi gcc-7-arm-linux-gnueabi gcc-arm-linux-gnueabihf gcc-7-arm-linux-gnueabihf libc6-armel-cross libc6-dev-armel-cross libc6-armhf-armel-cross libc6-dev-armhf-armel-cross
		;;
	"armhf")
		export GOOS=linux
		export GOARCH=arm
		export GOARM=6
		export CC=arm-linux-gnueabi-gcc
		sudo apt-get -f -y install gcc-arm-linux-gnueabi gcc-7-arm-linux-gnueabi gcc-arm-linux-gnueabihf gcc-7-arm-linux-gnueabihf libc6-armel-cross libc6-dev-armel-cross libc6-armhf-armel-cross libc6-dev-armhf-armel-cross
		;;
	"arm64")
		export GOOS=linux
		export GOARCH=arm64
		export CC=aarch64-linux-gnu-gcc
		sudo apt-get -f -y install gcc-aarch64-linux-gnu gcc-7-aarch64-linux-gnu libc6-arm64-cross libc6-dev-arm64-cross
		;;
esac
if [[ -n "${CC}${CXX}" || "${GOHOSTARCH}" != "${GOARCH}" ]]; then
	export CGO_ENABLED=1
fi

## Logic
# Clone teleport release
_log "Clone tp"
git clone -q --depth=1 --branch=${BUILD_TARGET} https://github.com/gravitational/teleport.git ${GOPATH}/src/github.com/gravitational/teleport
cd ${GOPATH}/src/github.com/gravitational/teleport
git checkout -qf ${BUILD_TARGET}
if [[ "${BUILD_TARGET}" != "v"* ]]; then
	BUILD_TARGET=$(awk -F '=' '/^VERSION=/{print $NF}' Makefile)
	_log "Revising Build Target to ${BUILD_TARGET} from Makefile"
fi

# Informational
_log "go env"
go env

# Build release
_log "Build ${BUILD_TARGET}"
make release

# Rename artifact to my convention
_log "Rename artifact"
BUNDLE=$(ls -1 | grep 'teleport-.*\(zip\|tar.gz\)')
VERSION=${BUILD_TARGET:-$(echo "${BUNDLE}" | awk -F '-' '{print $2"-"$3}')}
NEW_NAME="teleport-${VERSION}-${GOOS}-${ARCH_LABEL}"
mkdir ${OPWD}/artifacts
if [[ "${BUNDLE#*.}" == "zip" ]]; then
	mv "${BUNDLE}" "${OPWD}/artifacts/${NEW_NAME}.zip"
else
	mv "${BUNDLE}" "${OPWD}/artifacts/${NEW_NAME}.tar.gz"
fi
cd ${OPWD}
ls -la artifacts
