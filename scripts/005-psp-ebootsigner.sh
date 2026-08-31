#!/bin/bash
# ebootsigner by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/components/psp-ebootsigner"

if [ ! -f "${SOURCE}/Makefile" ]; then
	echo "ERROR: psp-ebootsigner submodule is not initialized."
	echo "Run: git submodule update --init --recursive --depth=1"
	exit 1
fi

## Determine the maximum number of processes that Make can work with.
PROC_NR=$(getconf _NPROCESSORS_ONLN)

cd "${SOURCE}"

## Compile and install.
make --quiet -j "$PROC_NR" all
make --quiet -j "$PROC_NR" install

## Store build information
BUILD_FILE="${PSPDEV}/build.txt"
if [[ -f "${BUILD_FILE}" ]]; then
sed -i'' '/^psp-ebootsigner /d' "${BUILD_FILE}"
fi

git -C "${SOURCE}" log -1 --format="psp-ebootsigner %H %cs %s" >> "${BUILD_FILE}"
