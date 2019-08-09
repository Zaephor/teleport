#!/bin/bash
if [[ -n "${DOCKER_TAG}" && ${BUILD_GOOS} == "linux" && ${ARCH_LABEL} == "amd64" ]]; then
	docker tag ${DOCKER_TAG}:${ARCH_LABEL}-${REMOTE_BRANCH} ${DOCKER_TAG}:debug
	echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin &>/dev/null
	docker push ${DOCKER_TAG}:debug
fi
