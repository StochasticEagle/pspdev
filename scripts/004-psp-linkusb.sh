#!/bin/bash
# psplinkusb by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/components/psp-linkusb"
source "${ROOT}/install-permissions.sh"

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
    make --quiet -j "$PROC_NR" -C pspsh all
    make --quiet -j "$PROC_NR" -C usbhostfs_pc all

    pspdev_run_install mkdir -p "${PSPDEV}/bin" "${PSPDEV}/share/psplinkusb"
    pspdev_run_install install -m 755 pspsh/pspsh "${PSPDEV}/bin/pspsh"
    pspdev_run_install install -m 755 usbhostfs_pc/usbhostfs_pc "${PSPDEV}/bin/usbhostfs_pc"
    pspdev_run_install install -m 644 usbhostfs_pc/50-psplink.rules "${PSPDEV}/share/psplinkusb/50-psplink.rules"
fi

## Store build information
pspdev_record_build_info "psp-linkusb" "$(git -C "${SOURCE}" log -1 --format="psp-linkusb %H %cs %s")"
