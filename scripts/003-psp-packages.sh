#!/bin/bash
# psp-packages by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/components/psp-packages"

if [ -z "${LOCAL_PACKAGE_BUILD:-}" ]; then
	## Install prebuilt packages.
	psp-pacman -Sy
	psp-pacman -S --noconfirm psp-libraries
else
	if [ ! -f "${SOURCE}/build.sh" ]; then
		echo "ERROR: psp-packages submodule is not initialized."
		echo "Run: git submodule update --init --recursive --depth=1"
		exit 1
	fi

	cd "${SOURCE}"

	## Build and install packages locally.
	./build.sh --install
fi
