#!/bin/bash
if [[ ${ALT_BRANCH} == ${TRAVIS_TAG} ]]; then
	docker tag ${DOCKER_TAG}:${ARCH_LABEL}-${REMOTE_BRANCH} ${DOCKER_TAG}:${ARCH_LABEL}
	if [[ ${ARCH_LABEL} == "amd64" ]]; then
		docker tag ${DOCKER_TAG}:${ARCH_LABEL}-${REMOTE_BRANCH} ${DOCKER_TAG}:latest
	fi
	SUBTAG=${REMOTE_BRANCH}
	while [[ -n "${SUBTAG//[^.]}" ]]; do
		docker tag ${DOCKER_TAG}:${ARCH_LABEL}-${REMOTE_BRANCH} ${DOCKER_TAG}:${ARCH_LABEL}-${SUBTAG%.**}
		SUBTAG=${SUBTAG%.**}
	done
fi

echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin &>/dev/null
docker push ${DOCKER_TAG}
