#!/bin/bash
set -e
echo "0: $0"
echo "@: $@"
echo "ARCH_LABEL: ${ARCH_LABEL}"
echo "BUILD_GOOS: ${BUILD_GOOS}"

echo '{"experimental":true}' | sudo tee /etc/docker/daemon.json
sudo service docker restart

docker version

STAGE=$(echo "${1#*-}" | tr '[a-z]' '[A-Z]')
case ${STAGE} in
	"binary")
		echo ${STAGE}
		;;
	"docker")
		echo ${STAGE}
		;;
esac
