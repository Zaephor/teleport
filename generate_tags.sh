#!/bin/bash
for z in $(git ls-remote --tags https://github.com/gravitational/teleport.git | awk -F '/' '!/{}/ && /v/{print $NF}' | grep -v '\(alpha\|beta\|rc\|v0.\)' | sort -V); do
	MAJOR=$(echo "${z}" | awk -F '[.v]' '/v/{print $2}')
	if [[ -n "${MAJOR}" && ${MAJOR} -ge 3 ]]; then
		if ! grep -q "^${z}$" VERSIONS; then
			echo ${z} >> VERSIONS
			git add VERSIONS
			git commit -m "TP: ${z}"
			git push -u origin master
			git tag ${z} --force
			git push --tags --force
			sleep 30m
		fi
	fi
done
