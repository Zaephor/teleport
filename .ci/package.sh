#!/bin/bash
OPWD=$(pwd)

## Func
function _log {
        echo "==== ${@}"
}


if [[ ! -d /tmp/tars ]]; then
	_log "Create temporary folder"
	mkdir -p /tmp/tars
fi
_log "Copying artifact tars to temporary folder"
cp artifacts/teleport-*.tar.gz /tmp/tars
for pkg in 'deb'; do
	_log "Building fpm container for ${pkg}"
	docker build -t "fpm:${pkg}" -f Dockerfile.${pkg}.fpm .
	for TAR_FILE in $(ls -1 /tmp/tars | grep linux); do
		_log "Processing ${TAR_FILE}"
		TAR_ARCH=$(echo "${TAR_FILE}" | awk -F '[-.]' '{print $(NF-2)}')
		_log "${TAR_FILE} - Identified ${TAR_ARCH}"
		_log "${TAR_FILE} - Creating more temp folders"
		mkdir -p /tmp/tp-${pkg}-${TAR_ARCH}/usr/local/bin /tmp/tp-${pkg}-${TAR_ARCH}/etc/systemd/system /tmp/tp-${pkg}-${TAR_ARCH}/etc/init
		_log "${TAR_FILE} - Copying assets into position"
		cp systemd-teleport.service /tmp/tp-${pkg}-${TAR_ARCH}/etc/systemd/system/teleport.service
		cp upstart-teleport.conf /tmp/tp-${pkg}-${TAR_ARCH}/etc/init/teleport.conf
		tar -xvf /tmp/tars/${TAR_FILE} -C /tmp/tp-${pkg}-${TAR_ARCH}/usr/local/bin --strip-components=1 teleport/teleport teleport/tctl teleport/tsh teleport/VERSION
		_log "${TAR_FILE} - Identifying package version"
		BUILD_TARGET=$(cat /tmp/tp-${pkg}-${TAR_ARCH}/usr/local/bin/VERSION)
		rm /tmp/tp-${pkg}-${TAR_ARCH}/usr/local/bin/VERSION
		_log "${TAR_FILE} - Launching fpm container to build desired ${pkg} file"
		docker run --rm -t $(tty &>/dev/null && echo "-i") -v "/tmp/tp-${pkg}-${TAR_ARCH}:/tmp/fpm" -w "/tmp/fpm" \
			"fpm:${pkg}" \
				-n 'teleport' \
				-v ${BUILD_TARGET/v/} \
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
		_log "${TAR_FILE} - Copying resulting ${pkg} file to primary artifacts directory"
		cp /tmp/tp-${pkg}-${TAR_ARCH}/teleport_*.${pkg} ${OPWD}/artifacts/
	done
done
cd ${OPWD}
ls -la artifacts/
