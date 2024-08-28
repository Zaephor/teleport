#!/bin/bash
echo "== Prep"
if [[ ! -e /usr/bin/sudo ]]; then
	echo "::group::sudo lazy shim"
	echo "SHELL - $SHELL"
	echo "#!/bin/sh" > /usr/bin/sudo
	echo '${@}' >> /usr/bin/sudo
	chmod +x /usr/bin/sudo
	echo "::endgroup::"
fi
echo "::group::preinstall"
dpkg -l
echo "::endgroup::"
mkdir -p ${REF_PWD:-${PWD}}/dist/teleport
echo "::group::apt-get update"
sudo apt-get -y update
echo "::endgroup::"
echo "::group::install"
if [[ "${ENV_OS}" == "ubuntu-latest" ]]; then
	sudo apt-get -f -y install curl wget git libpam0g-dev binutils bison gcc make binutils-multiarch build-essential
	VERSION_ID==$(awk -F'[[==\"]]' '/^VERSION_ID/{print $(NF-1)}' /etc/os-release)
	if [[ "${VERSION_ID}" == "14.04" ]]; then
		sudo apt-get -f -y install binutils-2.26
	fi
fi

if [[ "${GO_ARCH}" == "amd64" ]]; then
	sudo apt-get -f -y install libc6-dev
fi
if [[ "${GO_ARCH}" == "386" ]]; then
	sudo apt-get -f -y install gcc-multilib libc6-dev-i386
fi
if [[ "${GO_ARCH}" == "arm64" ]]; then
	sudo apt-get -f -y install libc6-arm64-cross libc6-dev-arm64-cross
fi
if [[ "${GO_ARCH}" == "arm" ]]; then
	if [[ "${GO_ARM}" == "6" ]]; then
		sudo dpkg --add-architecture armhf
		sudo apt-get -f -y install libc6-armhf-cross libc6-dev-armhf-cross libc6-armhf-cross libc6-dev-armhf-cross
	fi
	if [[ "${GO_ARM}" == "5" ]]; then
		sudo dpkg --add-architecture armel
		sudo apt-get -f -y install libc6-armel-cross libc6-dev-armel-cross libc6-armel-cross libc6-dev-armel-cross
	fi
fi
if [[ "${GO_ARCH}" == "mips" ]]; then
	sudo apt-get -f -y install libc6-mips-cross libc6-dev-mips-cross
fi

if [[ "${REF_NAME}" == "linux-arm64" ]]; then
	sudo apt-get -f -y install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
fi
if [[ "${REF_NAME}" == "linux-armhf" ]]; then
	sudo dpkg --add-architecture armhf
	sudo apt-get -f -y install gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf
fi
if [[ "${REF_NAME}" == "linux-armel" ]]; then
	sudo dpkg --add-architecture armel
	sudo apt-get -f -y install gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi
fi
if [[ "${REF_NAME}" == "linux-mips" ]]; then
	sudo apt-get -f -y install gcc-mips-linux-gnu binutils-mips-linux-gnu
fi
echo "::endgroup::"
echo "::group::postinstall"
dpkg -l
echo "::endgroup::"
echo "::group::other"
which ld
echo "::endgroup::"

