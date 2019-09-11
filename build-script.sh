#!/bin/bash
set -e
echo "0: $0"
echo "@: $@"
echo "ARCH_LABEL: ${ARCH_LABEL}"
echo "BUILD_GOOS: ${BUILD_GOOS}"

docker version

case ${BUILD_TYPE} in
	"tar")
		echo "== ${BUILD_TYPE}"
		docker run --rm --privileged multiarch/qemu-user-static:register
		docker run --privileged linuxkit/binfmt:v0.6

		ALT_BRANCH=$(tail -n1 ${TRAVIS_BUILD_DIR}/VERSIONS) # Detect last version in VERSIONS file
		REMOTE_BRANCH=${TRAVIS_TAG:-${ALT_BRANCH}} # Detect used tag, default to ALT_BRANCH if undefined

		git clone -q --depth=1 --branch=${REMOTE_BRANCH} https://github.com/gravitational/teleport.git teleport
		TPWD=$(pwd)
		cd teleport
		git checkout -qf ${REMOTE_BRANCH}
		cd ${TPWD}

		GO_ARGS=("-e" "GOOS=${BUILD_GOOS}" "-e" "GOARCH=${BUILD_GOARCH}")
		if [[ -n "${BUILD_GOARM}" ]]; then
			GO_ARGS+=("-e" "GOARM=${BUILD_GOARM}")
		fi

		docker run --rm -v "${PWD}/teleport":/go/src/github.com/gravitational/teleport -w /go/src/github.com/gravitational/teleport ${GO_ARGS[@]} golang:1.9.7-alpine3.8 sh -c "uname -a && apk add --no-cache git make gcc musl-dev zip tar && cd /go/src/github.com/gravitational/teleport && go env && make release"

		ls teleport

		;;
	"docker")
		echo "== ${BUILD_TYPE}"
#		docker login -u "${DOCKER_USER}" -p "${DOCKER_PASSWORD}" &> /dev/null

		docker run --rm --privileged multiarch/qemu-user-static:register
		docker run --privileged linuxkit/binfmt:v0.6

		docker buildx create --name teleport
		docker buildx use teleport
		docker buildx ls

		# Determine TAGS
		DOCKER_TAGS=()
		ALT_BRANCH=$(tail -n1 ${TRAVIS_BUILD_DIR}/VERSIONS) # Detect last version in VERSIONS file
		REMOTE_BRANCH=${TRAVIS_TAG:-${ALT_BRANCH}} # Detect used tag
		if [[ -n "${ALT_BRANCH}" && -n "${TRAVIS_TAG}" && "${ALT_BRANCH}" == "${TRAVIS_TAG}" ]]; then
			DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:latest" )
		fi
		DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:${REMOTE_BRANCH}" )

		SUBTAG=${REMOTE_BRANCH}
		while [[ -n "${SUBTAG//[^.]}" ]]; do
			LATEST_MATCH=$(awk "/${SUBTAG%.**}/ {a=\$0} END{print a}" "${TRAVIS_BUILD_DIR}/VERSIONS")
			if [[ "${LATEST_MATCH}" == "${TRAVIS_TAG}" ]]; then
				DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:${SUBTAG%.**}" )
				docker tag ${DOCKER_TAG}:${ARCH_LABEL}-${REMOTE_BRANCH} ${DOCKER_TAG}:${ARCH_LABEL}-${SUBTAG%.**}
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
			echo "Detected remote: ${PLAT_OS} - ${PLAT_ARCH}"
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

		if [[ -n "$(which travis_wait)" ]]; then
			echo "== Trying travis_wait"
			travis_wait 40 docker buildx build --platform "${PLATFORMS}" --build-arg REMOTE_BRANCH=${REMOTE_BRANCH} ${DOCKER_TAGS[@]} --push -f "Dockerfile" .
		else
			docker buildx build --platform "${PLATFORMS}" --build-arg REMOTE_BRANCH=${REMOTE_BRANCH} ${DOCKER_TAGS[@]} --push -f "Dockerfile" .
		fi

		docker buildx imagetools inspect "${DOCKER_TAG}:${REMOTE_BRANCH}"
		docker manifest inspect "${DOCKER_TAG}:${REMOTE_BRANCH}"

		;;
esac
