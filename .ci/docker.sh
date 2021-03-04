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

if [[ -n "${GH_USERNAME}${GH_PAT}" ]]; then
	_log "Logging into github registry"
	docker login gchr.io -u "${GH_USERNAME}" -p "${GH_PAT}" &> /dev/null
fi

_log "Setup buildx project"
#docker buildx create --name teleport
#docker buildx use teleport
docker buildx use mybuilder
docker buildx ls


_log "Determine tag prefixes"
TAG_PREFIXES=()
if [[ -n "${DOCKER_TAG_PREFIXES}" ]]; then
	TAG_PREFIXES+=( ${DOCKER_TAG_PREFIXES//,/ } )
fi

_log "Determine tags"
DOCKER_TAGS=()

if [[ -n "${LATEST}" && -n "${BUILD_TARGET}" && "${LATEST}" == "${BUILD_TARGET}" && "${BUILD_TAG}" != "master" ]]; then
	for PREF in ${TAG_PREFIXES[@]}; do
		DOCKER_TAGS+=( "-t" "${PREF}:latest" )
		_log "Queing tag ${PREF}:latest"
	done
else
	for PREF in ${TAG_PREFIXES[@]}; do
		DOCKER_TAGS+=( "-t" "${PREF}:debug" )
		_log "Queing tag ${PREF}:debug"
	done
fi

# Elaborate tags should only be used for actual releases
if [[ -n "${BUILD_TAG}" && "${BUILD_TAG}" != "master" ]]; then
	if [[ -n "${BUILD_TAG}" && "${LATEST}" == "${BUILD_TARGET}" ]]; then
		for PREF in ${TAG_PREFIXES[@]}; do
			DOCKER_TAGS+=( "-t" "${PREF}:${BUILD_TARGET}" )
			_log "Queing tag ${PREF}:${BUILD_TARGET}"
		done
	fi

	SUBTAG=${BUILD_TARGET}
	while [[ -n "${SUBTAG//[^.]}" ]]; do
		LATEST_MATCH=$(awk "/${SUBTAG%.**}/ {a=\$0} END{print a}" "VERSIONS")
		if [[ "${LATEST_MATCH}" == "${BUILD_TARGET}" ]]; then
			for PREF in ${TAG_PREFIXES[@]}; do
				DOCKER_TAGS+=( "-t" "${PREF}:${SUBTAG%.**}" )
				echo "Queing tag ${PREF}:${SUBTAG%.**}"
			done
		fi
		SUBTAG=${SUBTAG%.**}
	done
fi

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
DOCKER_ARGS=( "buildx" "build" "--platform" "$(_join "," "${PLATFORMS[@]}")" "--build-arg" "RELEASE=${BUILD_TARGET}" )
DOCKER_ARGS+=( ${DOCKER_TAGS[@]} )
DOCKER_ARGS+=("--push")
DOCKER_ARGS+=( "-f" "Dockerfile" "." )
echo docker ${DOCKER_ARGS[@]}
docker ${DOCKER_ARGS[@]}
