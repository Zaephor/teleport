#!/bin/bash
OIFS=$IFS
IFS=$'\n'

echo "GOPATH: ${GOPATH}"
export GOPATH="${HOME}/go"
echo "GOPATH: ${GOPATH}"

ENVIRONMENTS=(
'linux,armel'
'linux,armhf'
'linux,arm64'
'linux,i386'
'linux,amd64'
'windows,i386'
'windows,amd64'
)
#'darwin,amd64'

declare -A extras=(
	[i386]="386,,"
	[armel]="arm,5,arm-linux-gnueabi-gcc"
	[armhf]="arm,6,arm-linux-gnueabi-gcc"
	[arm64]="arm64,,arm-linux-gnueabi-gcc"
)

if [[ "${APPVEYOR_REPO_TAG}" == "true" ]]; then
	echo "======== Building: ${APPVEYOR_REPO_TAG_NAME}"
	REMOTE_BRANCH=${APPVEYOR_REPO_TAG_NAME}
else
	REMOTE_BRANCH=master
fi

mkdir ${APPVEYOR_BUILD_FOLDER}/artifacts ${HOME}/go/src/github.com/gravitational
git clone -q --branch=${REMOTE_BRANCH} https://github.com/gravitational/teleport.git ${HOME}/go/src/github.com/gravitational/teleport
cd ${HOME}/go/src/github.com/gravitational/teleport
git checkout -qf ${REMOTE_BRANCH}

for z in ${ENVIRONMENTS[@]}; do
	echo "======== ${z}"
	export GOOS=$(echo ${z} | cut -d',' -f1)
	ARCH=$(echo ${z} | cut -d',' -f2)
	if [[ -z "${extras[${ARCH}]}" ]]; then
		export GOARCH=${ARCH}
		unset GOARM
		unset CC
	else
		export GOARCH=$(echo ${extras[$ARCH]} | cut -d',' -f1)
		export GOARM=$(echo ${extras[$ARCH]} | cut -d',' -f2)
		export CC=$(echo ${extras[$ARCH]} | cut -d',' -f3)
		if [[ -z "${GOARM}" ]]; then
			unset GOARM
		fi
		if [[ -z "${CC}" ]]; then
			unset CC
		fi
	fi

	make release

	TARBALL=$(ls -1 teleport-*.tar.gz)
	ZIPBALL=$(ls -1 teleport-*.zip)
	if [[ -n "${TARBALL}" ]]; then
		VERSION=${APPVEYOR_REPO_TAG_NAME:-$(echo "${TARBALL}" | awk -F '-' '{print $2"-"$3}')}
		NEW_NAME="teleport-${VERSION}-${GOOS}-${ARCH}"
		mv "${TARBALL}" "${APPVEYOR_BUILD_FOLDER}/artifacts/${NEW_NAME}.tar.gz"
	fi
	if [[ -n "${ZIPBALL}" ]]; then
		VERSION=${APPVEYOR_REPO_TAG_NAME:-$(echo "${ZIPBALL}" | awk -F '-' '{print $2"-"$3}')}
		NEW_NAME="teleport-${VERSION}-${GOOS}-${ARCH}"
		mv "${ZIPBALL}" "${APPVEYOR_BUILD_FOLDER}/artifacts/${NEW_NAME}.zip"
	fi
done
ls -la ${APPVEYOR_BUILD_FOLDER}/artifacts/
cd ${APPVEYOR_BUILD_FOLDER}

IFS=$OIFS
