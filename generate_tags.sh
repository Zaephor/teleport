#!/bin/bash
for z in $(git ls-remote --tags https://github.com/gravitational/teleport.git | awk -F '/' '!/{}/ && /v/{print $NF}' | grep -v '\(alpha\|beta\|rc\|v0.\)'); do
	if ! grep -q "^${z}$" VERSIONS; then
		echo ${z} >> VERSIONS
		git add VERSIONS
		git commit -m "TP: ${z}"
		git tag ${z}
		git push -u origin master
		git push --tags
	fi
done
