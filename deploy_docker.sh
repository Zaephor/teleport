#!/bin/bash
if [[ ${ALT_BRANCH} == ${TRAVIS_TAG} ]]; then
	docker tag ${DOCKER_TAG}:${ARCH_LABEL}-${REMOTE_BRANCH} ${DOCKER_TAG}:${ARCH_LABEL}
	if [[ "${ARCH_LABEL}" == "amd64" ]]; then
		docker tag ${DOCKER_TAG}:${ARCH_LABEL}-${REMOTE_BRANCH} ${DOCKER_TAG}:latest
	fi
fi
SUBTAG=${REMOTE_BRANCH}
while [[ -n "${SUBTAG//[^.]}" ]]; do
	LATEST_MATCH=$(awk "/${SUBTAG%.**}/ {a=\$0} END{print a}" "${TRAVIS_BUILD_DIR}/VERSIONS")
	if [[ "${LATEST_MATCH}" == "${TRAVIS_TAG}" ]]; then
		docker tag ${DOCKER_TAG}:${ARCH_LABEL}-${REMOTE_BRANCH} ${DOCKER_TAG}:${ARCH_LABEL}-${SUBTAG%.**}
	fi
	SUBTAG=${SUBTAG%.**}
done

echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin &>/dev/null
docker push ${DOCKER_TAG}
