#!/bin/bash
set -e
OPWD=$(pwd)
export DOCKER_CLI_EXPERIMENTAL=enabled

## Func
function _log {
        echo "==== ${@}"
}
function _join {
        local IFS="$1"; shift; echo "$*";
}

sudo apt-get install -f -y jq

LATEST="$(cat LATEST)"
#BUILD_TAG=${GITHUB_REF##*/}
BUILD_TAG="${1}"
BUILD_TARGET=${BUILD_TAG:-${LATEST}}
if [[ "${BUILD_TARGET}" == "master" ]]; then
        BUILD_TARGET=${LATEST}
fi

docker version
_log "Setup deps for cross-building docker containers"
docker run --rm --privileged multiarch/qemu-user-static:register
docker run --privileged linuxkit/binfmt:v0.7

_log "Logging into docker registry"
docker login -u "${DOCKER_USERNAME}" -p "${DOCKER_PASSWORD}" &> /dev/null

if [[ -n "${GITHUB_USERNAME}${GITHUB_PAT}" ]]; then
	_log "Logging into github registry"
	docker login https://docker.pkg.github.com -u "${GITHUB_USERNAME}" -p "${GITHUB_PAT}" &> /dev/null
fi

_log "Create buildx project"
docker buildx create --name teleport
docker buildx use teleport
docker buildx ls

_log "Determine tags"
DOCKER_TAGS=()

if [[ -n "${LATEST}" && -n "${BUILD_TARGET}" && "${LATEST}" == "${BUILD_TARGET}" && "${BUILD_TARGET}" != "master" ]]; then
	DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:latest" )
	_log "Queing tag ${DOCKER_TAG}:latest"
else
	DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:debug" )
	_log "Queing tag ${DOCKER_TAG}:debug"
fi
if [[ -n "${BUILD_TAG}" && "${LATEST}" == "${BUILD_TARGET}" ]]; then
	DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:${REMOTE_BRANCH}" )
	_log "Queing tag ${DOCKER_TAG}:${REMOTE_BRANCH}"
fi

SUBTAG=${REMOTE_BRANCH}
while [[ -n "${SUBTAG//[^.]}" ]]; do
	LATEST_MATCH=$(awk "/${SUBTAG%.**}/ {a=\$0} END{print a}" "VERSIONS")
	if [[ "${LATEST_MATCH}" == "${BUILD_TARGET}" ]]; then
		DOCKER_TAGS+=( "-t" "${DOCKER_TAG}:${SUBTAG%.**}" )
		echo "Queing tag ${DOCKER_TAG}:${SUBTAG%.**}"
	fi
	SUBTAG=${SUBTAG%.**}
done


_log "Determine platforms"
FROM=$(awk '/^FROM/{print $NF}' "Dockerfile" | tail -n 1)
PLATFORMS=()
for PLAT in $(docker manifest inspect "${FROM}" | jq -c --raw-output '.manifests[].platform'); do
	PLAT_OS=$(echo "${PLAT}" | jq -c --raw-output '.os')
	PLAT_ARCH=$(echo "${PLAT}" | jq -c --raw-output '.architecture')
	PLAT_VARIANT=$(echo "${PLAT}" | jq -c --raw-output '.variant')
	_log "Detected platform from base image: ${PLAT_OS} - ${PLAT_ARCH}"
	if [[ -n "${PLAT_VARIANT}" && "${PLAT_VARIANT}" != "null" ]]; then
		PLATFORMS+=( "${PLAT_OS}/${PLAT_ARCH}/${PLAT_VARIANT}" )
	else
		PLATFORMS+=( "${PLAT_OS}/${PLAT_ARCH}" )
	fi
done
if [[ "${#PLATFORMS[@]}" -eq 0 ]]; then
	PLATFORMS+=( "linux/amd64" )
fi



_log "Build containers"
DOCKER_ARGS=( "buildx" "build" "--platform" "$(_join "," "${PLATFORMS[@]}")" "--build-arg" "RELEASE=${REMOTE_BRANCH}" )
DOCKER_ARGS+=( ${DOCKER_TAGS[@]} )
DOCKER_ARGS+=("--push")
DOCKER_ARGS+=( "-f" "Dockerfile" "." )
echo docker ${DOCKER_ARGS[@]}
