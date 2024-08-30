#!/bin/bash
IFS=$'\n'
source ${PWD}/gvm/scripts/gvm
gvm use go${GO_VERSION} --default
echo "=== Build"
export PATH="/usr/lib/binutils-2.26/bin:$PATH"
export GOOS=${GO_OS}
export GOARCH=${GO_ARCH}
if [[ -n "${GO_ARM}" ]]; then export GOARM=${GO_ARM}; fi
if [[ -n "${GO_EXPERIMENT}" && "${GOVERSION}" == go1.20* ]]; then export GOEXPERIMENT=${GO_EXPERIMENT}; fi
if [[ "${GOHOSTARCH}" != "${GO_ARCH}" ]]; then export CGO_ENABLED=1; fi
if [[ -n "${CC}" ]]; then export CC=${CC}; export CGO_ENABLED=1; fi

FLAGS=(
	'-s -w'
	'-s -w -extldflags "--long-plt"'
	'-s -w -extldflags "--no-plt"'
	'-s -w -extldflags "-fuse-ld=gold"'
	'-s -w -extldflags "-fuse-ld=gold --long-plt"'
	'-s -w -extldflags "-fuse-ld=gold --no-plt"'
)

git config --global --add safe.directory "${PWD}/go/src/${UPSTREAM}"
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
for x in 'tbot' 'tctl' 'tsh' 'teleport'; do
	if [[ -d ./tool/$x ]]; then
		for ldflag in ${FLAGS[@]}; do
			echo "::group::Trying to build ${x} with ${ldflag}"
			go build -tags "pam" -ldflags="${ldflag}" -o "${REF_PWD}/dist/teleport/${x}" ./tool/${x}
			echo "::endgroup::"
			if [[ -e "${REF_PWD}/dist/teleport/${x}" ]]; then
				echo "== ${x} - Success"
				break
			else
				go clean -cache
			fi
		done
		if [[ ! -e "${REF_PWD}/dist/teleport/${x}" ]]; then
			echo "== ${x} - Fail"
			exit 1
		fi
	fi
done
echo "${REF_VER}" > "${REF_PWD}/dist/teleport/VERSION"
cp -r "${REF_PWD}/go/src/${UPSTREAM}/examples" "${REF_PWD}/dist/teleport"

