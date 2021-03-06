#!/bin/bash
REMOTE="origin"
BRANCH="master"
if [[ -n "${TRAVIS_BUILD_DIR}" ]]; then
	cd ${TRAVIS_BUILD_DIR}
fi
git status
if [[ "${CI}" == "true" && "${TRAVIS}" == "true" ]]; then
	git checkout master
	git config user.email "travis@travis-ci.org"
	git config user.name "Travis CI"
	git config push.default current
	if [[ -n "${GITHUB_OAUTH_TOKEN}" ]]; then
		git remote add https-origin "https://${GITHUB_OAUTH_TOKEN}:x-oauth-basic@github.com/${TRAVIS_REPO_SLUG}" &> /dev/null
	else
		git remote add https-origin "https://github.com/${TRAVIS_REPO_SLUG}" &> /dev/null
	fi
	REMOTE="https-origin"
fi

for z in $(git ls-remote --tags https://github.com/gravitational/teleport.git | awk -F '/' '!/{}/ && /v/{print $NF}' | grep -v '\(v0.\|-[a-Z]\)' | sort -V); do
	MAJOR=$(echo "${z}" | awk -F '[.v]' '/v/{print $2}')
	if [[ -n "${MAJOR}" && ${MAJOR} -ge 3 ]]; then
		if ! grep -q "^${z}$" VERSIONS; then
			echo ${z} >> VERSIONS
			sort -V VERSIONS | tail -n 1 > LATEST
			git add VERSIONS LATEST
			git commit -m "TP: ${z}"
			git push --quiet -u "${REMOTE}" "${BRANCH}"
			git tag ${z} --force
			git push --quiet -u "${REMOTE}" --tags --force
			sleep 1m
		fi
	fi
done
