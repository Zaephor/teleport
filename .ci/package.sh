#!/bin/bash
OPWD=$(pwd)
if [[ ! -d /tmp/tars ]]; then
	mkdir -p /tmp/tars
fi
cp artifacts/teleport-*.tar.gz /tmp/tars
for pkg in 'deb'; do
	docker build -t "fpm:${pkg}" -f Dockerfile.${pkg}.fpm .
	for TAR_FILE in $(ls -1 /tmp/tars | grep linux); do
		TAR_ARCH=$(echo "${TAR_FILE}" | awk -F '[-.]' '{print $(NF-2)}')
		mkdir -p /tmp/tp-${pkg}-${TAR_ARCH}/usr/local/bin /tmp/tp-${pkg}-${TAR_ARCH}/etc/systemd/system /tmp/tp-${pkg}-${TAR_ARCH}/etc/init
		cp systemd-teleport.service /tmp/tp-${pkg}-${TAR_ARCH}/etc/systemd/system/teleport.service
		cp upstart-teleport.conf /tmp/tp-${pkg}-${TAR_ARCH}/etc/init/teleport.conf
		tar -xvf /tmp/tars/${TAR_FILE} -C /tmp/tp-${pkg}-${TAR_ARCH}/usr/local/bin --strip-components=1 teleport/teleport teleport/tctl teleport/tsh
		docker run --rm -it -v "/tmp/tp-${pkg}-${TAR_ARCH}:/tmp/fpm" -w "/tmp/fpm" \
			"fpm:${pkg}" \
				-n 'teleport' \
				-v ${REMOTE_BRANCH/v/} \
				-C /tmp/fpm \
				-s dir \
				-t ${pkg} \
				--architecture "${TAR_ARCH}" \
				--deb-no-default-config-files \
				--directories "/var/lib/teleport" \
				-p teleport_VERSION_ARCH.${pkg} \
				./usr/local/bin/=/usr/local/bin \
				./etc/=/etc
#				./teleport.dir/usr/share/=/usr/share \
		cp /tmp/tp-${pkg}-${TAR_ARCH}/teleport_*.${pkg} ${OPWD}/artifacts/
	done
done
cd ${OPWD}
ls -la artifacts/
