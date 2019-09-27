#!/bin/bash
set -e
export BUILD_TYPE="${1}"
echo "0: $0"
echo "BUILD_TYPE: ${BUILD_TYPE}"

ALT_BRANCH=$(sort -V ${TRAVIS_BUILD_DIR}/VERSIONS | tail -n1) # Detect last version in VERSIONS file
REMOTE_BRANCH=${TRAVIS_TAG:-${ALT_BRANCH}} # Detect used tag, default to ALT_BRANCH if undefined
echo "ALT_BRANCH: ${ALT_BRANCH}"
echo "REMOTE_BRANCH: ${REMOTE_BRANCH}"


echo "== ${BUILD_TYPE}"
case ${BUILD_TYPE} in
	"tar")
		echo "ARCH_LABEL: ${ARCH_LABEL}"
		echo "BUILD_GOOS: ${BUILD_GOOS}"
		git clone -q --depth=1 --branch=${REMOTE_BRANCH} https://github.com/gravitational/teleport.git ${GOPATH}/src/github.com/gravitational/teleport
		TPWD=$(pwd)
		cd ${GOPATH}/src/github.com/gravitational/teleport
		git checkout -qf ${REMOTE_BRANCH}

		for build_env in $(printenv | awk -F '=' '/^BUILD_/{print $1}' | sed 's@BUILD_@@g'); do
			set_var="BUILD_${build_env}"
			export ${build_env}=${!set_var}
		done
		if [[ -n "${BUILD_CC}${BUILD_CXX}" || "${GOHOSTARCH}" != "${BUILD_GOARCH}" ]]; then
			export CGO_ENABLED=1
		fi

		go env
		make release

		mv teleport-${REMOTE_BRANCH}-* ${TPWD}
		cd ${TPWD}
		BUNDLE=$(ls -1 | grep 'teleport-.*\(zip\|tar.gz\)')
		VERSION=${REMOTE_BRANCH:-$(echo "${BUNDLE}" | awk -F '-' '{print $2"-"$3}')}
		NEW_NAME="teleport-${VERSION}-${BUILD_GOOS}-${ARCH_LABEL}"
		mkdir artifacts
		if [[ "${BUNDLE#*.}" == "zip" ]]; then
			mv "${BUNDLE}" "artifacts/${NEW_NAME}.zip"
		else
			mv "${BUNDLE}" "artifacts/${NEW_NAME}.tar.gz"
		fi
		ls artifacts
		;;
	"docker")
		docker version
		docker run --rm --privileged multiarch/qemu-user-static:register
		docker run --privileged linuxkit/binfmt:v0.7

		echo "Logging in"
		docker login -u "${DOCKER_USERNAME}" -p "${DOCKER_PASSWORD}" &> /dev/null

		echo "Creating buildx project"
		docker buildx create --name teleport
		docker buildx use teleport
		docker buildx ls

		# Determine TAGS
		DOCKER_TAGS=()
		if [[ -n "${ALT_BRANCH}" && -n "${TRAVIS_TAG}" && "${ALT_BRANCH}" == "${TRAVIS_TAG}" ]]; then
			DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:latest" )
			echo "Queing tag ${DOCKER_TAG}:latest"
		else
			DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:debug" )
			echo "Queing tag ${DOCKER_TAG}:debug"
		fi
		if [[ -n "${TRAVIS_TAG}" && "${TRAVIS_BRANCH}" == "${TRAVIS_TAG}" ]]; then
			DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:${REMOTE_BRANCH}" )
			echo "Queing tag ${DOCKER_TAG}:${REMOTE_BRANCH}"
		fi

		SUBTAG=${REMOTE_BRANCH}
		while [[ -n "${SUBTAG//[^.]}" ]]; do
			LATEST_MATCH=$(awk "/${SUBTAG%.**}/ {a=\$0} END{print a}" "${TRAVIS_BUILD_DIR}/VERSIONS")
			if [[ "${LATEST_MATCH}" == "${TRAVIS_TAG}" ]]; then
				DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:${SUBTAG%.**}" )
			echo "Queing tag ${DOCKER_TAG}:${SUBTAG%.**}"
			fi
			SUBTAG=${SUBTAG%.**}
		done

		# Determine Platforms
		FROM=$(awk '/^FROM/{print $NF}' "Dockerfile" | tail -n 1)
		PLATFORMS=""
		for PLAT in $(docker manifest inspect "${FROM}" | jq -c --raw-output '.manifests[].platform'); do
			PLAT_OS=$(echo "${PLAT}" | jq -c --raw-output '.os')
			PLAT_ARCH=$(echo "${PLAT}" | jq -c --raw-output '.architecture')
			PLAT_VARIANT=$(echo "${PLAT}" | jq -c --raw-output '.variant')
			echo "Detected platform from base image: ${PLAT_OS} - ${PLAT_ARCH}"
			if [[ -n "${PLATFORMS}" ]]; then
				PLATFORMS+=","
			fi
			PLATFORMS+="${PLAT_OS}/${PLAT_ARCH}"
			if [[ -n "${PLAT_VARIANT}" && "${PLAT_VARIANT}" != "null" ]]; then
				PLATFORMS+="/${PLAT_VARIANT}"
			fi
		done
		if [[ -z "${PLATFORMS}" ]]; then
			PLATFORMS="linux/amd64"
		fi

		DOCKER_ARGS=( "buildx" "build" "--platform" "${PLATFORMS}" "--build-arg" "RELEASE=${REMOTE_BRANCH}" )
		DOCKER_ARGS+=( ${DOCKER_TAGS[@]} )
		DOCKER_ARGS+=("--push")
		DOCKER_ARGS+=( "-f" "Dockerfile" "." )

		docker ${DOCKER_ARGS[@]}

		docker buildx imagetools inspect "${DOCKER_TAGS[1]}"
		docker manifest inspect "${DOCKER_TAGS[1]}"
		;;
	"pkgs")
		mkdir /tmp/tars
		for download in $(curl -s https://api.github.com/repos/Zaephor/teleport/releases/tags/${REMOTE_BRANCH} | jq -c --raw-output '.assets[].browser_download_url'); do
			wget --quiet ${download} -P /tmp/tars
		done
#		for pkg in 'deb' 'rpm'; do
		for pkg in 'deb'; do
			docker build -t "fpm:${pkg}" -f Dockerfile.${pkg}.fpm .
			for TAR_FILE in $(ls -1 /tmp/tars | grep linux); do
				TAR_ARCH=$(echo "${TAR_FILE}" | awk -F '[-.]' '{print $(NF-2)}')
				mkdir -p /tmp/${TAR_ARCH}/usr/sbin
				tar -xvf /tmp/tars/${TAR_FILE} -C /tmp/${TAR_ARCH}/usr/sbin --strip-components=1 teleport/teleport teleport/tctl teleport/tsh
				docker run --rm -it -v "/tmp/${TAR_ARCH}:/tmp/fpm" -w "/tmp/fpm" \
					"fpm:${pkg}" -s dir -t ${pkg} -n 'teleport' -v ${REMOTE_BRANCH/v/} -C /tmp/fpm --architecture "${TAR_ARCH}" -p teleport_VERSION_ARCH.${pkg}
#					"fpm:${pkg}" -s dir -t ${pkg} -n 'teleport' -v ${REMOTE_BRANCH/v/} -C /tmp/fpm --architecture "${TAR_ARCH}" -p teleport_VERSION_ARCH.${pkg} --prefix /usr/local/bin/
			done
		done
		find /tmp
		;;
esac
