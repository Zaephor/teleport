#!/bin/bash
for z in $(git ls-remote --tags https://github.com/gravitational/teleport.git | awk -F '/' '!/{}/ && /v/{print $NF}' | grep -v '\(v0.\|-[a-Z]\)' | sort -V); do
	MAJOR=$(echo "${z}" | awk -F '[.v]' '/v/{print $2}')
	if [[ -n "${MAJOR}" && ${MAJOR} -ge 3 ]]; then
		if ! grep -q "^${z}$" VERSIONS; then
			echo ${z} >> VERSIONS
			sort -V VERSIONS | tail -n 1 > LATEST
			break
		fi
	fi
done
