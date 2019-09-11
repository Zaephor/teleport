#!/bin/bash
set -ex
export BUILD_TYPE="${1}"
echo "0: $0"
echo "BUILD_TYPE: ${BUILD_TYPE}"
echo "ARCH_LABEL: ${ARCH_LABEL}"
echo "BUILD_GOOS: ${BUILD_GOOS}"
QEMU=""

docker version
docker run --rm --privileged multiarch/qemu-user-static:register
docker run --privileged linuxkit/binfmt:v0.7

ALT_BRANCH=$(tail -n1 ${TRAVIS_BUILD_DIR}/VERSIONS) # Detect last version in VERSIONS file
REMOTE_BRANCH=${TRAVIS_TAG:-${ALT_BRANCH}} # Detect used tag, default to ALT_BRANCH if undefined

echo "== ${BUILD_TYPE}"
case ${BUILD_TYPE} in
	"tar")
		git clone -q --depth=1 --branch=${REMOTE_BRANCH} https://github.com/gravitational/teleport.git ${GOPATH}/src/github.com/gravitational/teleport
		TPWD=$(pwd)
		cd ${GOPATH}/src/github.com/gravitational/teleport
		git checkout -qf ${REMOTE_BRANCH}

		for build_env in $(printenv | awk -F '=' '/^BUILD_/{print $1}' | sed 's@BUILD_@@g'); do
			set_var="BUILD_${build_env}"
			export ${build_env}=${!set_var}
		done

		go env
		make release

		mv teleport-${REMOTE_BRANCH}-* ${TPWD}
		cd ${TPWD}
		ls
		;;
	"docker")
#		docker login -u "${DOCKER_USER}" -p "${DOCKER_PASSWORD}" &> /dev/null

		docker buildx create --name teleport
		docker buildx use teleport
		docker buildx ls

		# Determine TAGS
		DOCKER_TAGS=()
		if [[ -n "${ALT_BRANCH}" && -n "${TRAVIS_TAG}" && "${ALT_BRANCH}" == "${TRAVIS_TAG}" ]]; then
			DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:latest" )
		else
			DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:debug" )
		fi
		if [[ -n "${TRAVIS_TAG}" && "${TRAVIS_BRANCH}" == "${TRAVIS_TAG}" ]]; then
			DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:${REMOTE_BRANCH}" )
		fi

		SUBTAG=${REMOTE_BRANCH}
		while [[ -n "${SUBTAG//[^.]}" ]]; do
			LATEST_MATCH=$(awk "/${SUBTAG%.**}/ {a=\$0} END{print a}" "${TRAVIS_BUILD_DIR}/VERSIONS")
			if [[ "${LATEST_MATCH}" == "${TRAVIS_TAG}" ]]; then
				DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:${SUBTAG%.**}" )
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

		DOCKER_ARGS=( "buildx" "build" "--platform" "${PLATFORMS}" "--build-arg" "RELEASE=${REMOTE_BRANCH}" )
		DOCKER_ARGS+=( ${DOCKER_TAGS[@]} )
		DOCKER_ARGS+=("--push")
		DOCKER_ARGS+=( "-f" "Dockerfile" "." )

#		if [[ -n "$(which travis_wait)" ]]; then
#			echo "== Trying travis_wait"
#			travis_wait 40 docker buildx build --platform "${PLATFORMS}" --build-arg RELEASE=${REMOTE_BRANCH} ${DOCKER_TAGS[@]} --push -f "Dockerfile" .
#		else
#			docker buildx build --platform "${PLATFORMS}" --build-arg RELEASE=${REMOTE_BRANCH} ${DOCKER_TAGS[@]} --push -f "Dockerfile" .
#		fi
		docker ${DOCKER_ARGS[@]}

#		docker buildx imagetools inspect "${DOCKER_TAG}:${REMOTE_BRANCH}"
#		docker manifest inspect "${DOCKER_TAG}:${REMOTE_BRANCH}"
		docker buildx imagetools inspect "${DOCKER_TAGS[1]}"
		docker manifest inspect "${DOCKER_TAGS[1]}"
		;;
esac
