#!/bin/bash
set -e
source /github/home/.gvm/scripts/gvm
echo "=== Build"
export PATH="/usr/lib/binutils-2.26/bin:$PATH"
export GOOS=${GO_OS}
export GOARCH=${GO_ARCH}
if [[ -n "${GO_ARM}" ]]; then export GOARM=${GO_ARM}; fi
if [[ -n "${GO_EXPERIMENT}" && "${GOVERSION}" == go1.20* ]]; then export GOEXPERIMENT=${GO_EXPERIMENT}; fi
if [[ "${GOHOSTARCH}" != "${GO_ARCH}" ]]; then export CGO_ENABLED=1; fi
if [[ -n "${CC}" ]]; then export CC=${CC}; export CGO_ENABLED=1; fi

cd go/src/${UPSTREAM}
echo "::group::go clean"
go clean -modcache
echo "::endgroup::"
echo "::group::go get"
go get
echo "::endgroup::"

echo "::group::path/shell"
echo "PATH=$PATH"
echo "SHELL=$SHELL"
echo "::endgroup::"
echo "::group::go env"
go env
echo "::endgroup::"
for x in 'teleport' 'tsh' 'tctl' 'tbot'; do
	if [[ -d ./tool/$x ]]; then
		echo "::group::Building ${x}"
		go build -tags "pam" -ldflags="-s -w" -o "${REF_PWD}/dist/teleport/${x}" ./tool/${x}
		echo "::endgroup::"
		if [[ ! -e "${REF_PWD}/dist/teleport/${x}" ]]; then
			exit 1
		fi
	fi
done
echo "${REF_VER}" > "${REF_PWD}/dist/teleport/VERSION"
cp -r "${REF_PWD}/go/src/${UPSTREAM}/examples" "${REF_PWD}/dist/teleport"

