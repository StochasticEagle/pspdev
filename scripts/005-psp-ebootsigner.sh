#!/bin/bash
# ebootsigner by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/components/psp-ebootsigner"
source "${ROOT}/install-permissions.sh"

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
pspdev_run_install mkdir -p "${PSPDEV}/bin"
pspdev_run_install install -m 755 ebootsign "${PSPDEV}/bin/ebootsign"

## Store build information
pspdev_record_build_info "psp-ebootsigner" "$(git -C "${SOURCE}" log -1 --format="psp-ebootsigner %H %cs %s")"
