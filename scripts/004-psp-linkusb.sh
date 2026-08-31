#!/bin/bash
# psplinkusb by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/components/psp-linkusb"

if [ ! -f "${SOURCE}/Makefile" ]; then
	echo "ERROR: psp-linkusb submodule is not initialized."
	echo "Run: git submodule update --init --recursive --depth=1"
	exit 1
fi

## Determine the maximum number of processes that Make can work with.
PROC_NR=$(getconf _NPROCESSORS_ONLN)
OSVER=$(uname)

cd "${SOURCE}"

## Compile and install.
make --quiet -j "$PROC_NR" all

# Windows currently can't compile pspsh, usbhostfs_pc
if [ "${OSVER:0:5}" != "MINGW" ]; then
	make --quiet -j "$PROC_NR" -C pspsh install
	make --quiet -j "$PROC_NR" -C usbhostfs_pc install
fi

## Store build information
BUILD_FILE="${PSPDEV}/build.txt"
if [[ -f "${BUILD_FILE}" ]]; then
	sed -i'' '/^psp-linkusb /d' "${BUILD_FILE}"
fi

git -C "${SOURCE}" log -1 --format="psp-linkusb %H %cs %s" >> "${BUILD_FILE}"
