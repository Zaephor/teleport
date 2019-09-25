#!/bin/bash
REMOTE="origin"
BRANCH="master"
if [[ "${CI}" == "true" && "${TRAVIS}" == "true" ]]; then
	git config user.email "travis@travis-ci.org"
	git config user.name "Travis CI"
	git config push.default current
	if [[ -n "${GITHUB_OAUTH_TOKEN}" ]]; then
		git remote add https-origin $(git remote get-url origin | sed "s#git@github.com:#https://${GITHUB_OAUTH_TOKEN}@github.com/#g") &> /dev/null
	else
		git remote add https-origin $(git remote get-url origin | sed "s#git@github.com:#https://github.com/#g")
	fi
	REMOTE="https-origin"
fi

for z in $(git ls-remote --tags https://github.com/gravitational/teleport.git | awk -F '/' '!/{}/ && /v/{print $NF}' | grep -v '\(alpha\|beta\|rc\|v0.\)' | sort -V); do
	MAJOR=$(echo "${z}" | awk -F '[.v]' '/v/{print $2}')
	if [[ -n "${MAJOR}" && ${MAJOR} -ge 3 ]]; then
		if ! grep -q "^${z}$" VERSIONS; then
			echo ${z} >> VERSIONS
			git add VERSIONS
			git commit -m "TP: ${z}"
			git push --quiet -u "${REMOTE}" "${BRANCH}"
			git tag ${z} --force
			git push --quiet -u "${REMOTE}" --tags --force
			sleep 1m
		fi
	fi
done
