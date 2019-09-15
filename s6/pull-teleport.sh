#!/bin/sh
DL_ARCH=""
case "$(uname -m)" in
	"x86_64")
		DL_ARCH="amd64"
		;;
	"armv6l")
		DL_ARCH="armel"
		;;
	"armv7l")
		DL_ARCH="armhf"
		;;
	"aarch64")
		DL_ARCH="arm64"
		;;
	*)
		echo "Error: Unknown arch($(uname -m))"
		exit 1
		;;
esac

wget https://github.com/Zaephor/teleport/releases/download/${RELEASE}/teleport-${RELEASE}-$(uname -s | tr '[A-Z]' '[a-z]')-${DL_ARCH}.tar.gz -O /tmp/teleport.tar.gz
tar -xvf /tmp/teleport.tar.gz -C /usr/sbin --strip-components=1 teleport/teleport teleport/tctl teleport/tsh
