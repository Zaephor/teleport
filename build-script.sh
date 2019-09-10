#!/bin/bash
set -e
echo "0: $0"
echo "@: $@"
echo "ARCH_LABEL: ${ARCH_LABEL}"
echo "BUILD_GOOS: ${BUILD_GOOS}"

docker version

STAGE=$(echo "${1#*-}" | tr '[A-Z]' '[a-z]')
case ${STAGE} in
	"binary")
		echo ${STAGE}
		
		;;
	"docker")
		echo ${STAGE}
#		docker login -u "${DOCKER_USER}" -p "${DOCKER_PASSWORD}" &> /dev/null

		docker run --rm --privileged multiarch/qemu-user-static:register
		docker run --privileged linuxkit/binfmt:v0.6

		docker buildx create --name teleport
		docker buildx use teleport
		docker buildx ls

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

		docker buildx build --platform "${PLATFORMS}" --build-arg REMOTE_BRANCH=${REMOTE_BRANCH} ${DOCKER_TAGS[@]} --push -f "Dockerfile" .

		docker buildx imagetools inspect "${DOCKER_TAG}:${REMOTE_BRANCH}"
		docker manifest inspect "${DOCKER_TAG}:${REMOTE_BRANCH}"

		;;
esac
