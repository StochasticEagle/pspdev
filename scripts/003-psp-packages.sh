#!/bin/bash
# psp-packages by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_SOURCE="${ROOT}/components/psp-packages"
PSPSDK_SOURCE="${ROOT}/components/pspsdk"

if [ ! -f "${PSPSDK_SOURCE}/build-cfw-and-install.sh" ]; then
    echo "ERROR: PSPSDK CFW build script is not available."
    exit 1
fi

build_local_packages() {
    if [ ! -x "${PACKAGES_SOURCE}/build.sh" ]; then
        echo "ERROR: psp-packages submodule is not initialized."
        echo "Run: git submodule update --init --recursive --depth=1 components/psp-packages"
        exit 1
    fi

    echo "Building and installing PSP packages locally."
    (
        cd "${PACKAGES_SOURCE}"
        if [[ "${PSPDEV_PROGRESS:-0}" == "1" ]]; then
            PSP_PROGRESS_PARENT=1 ./build.sh p --install
        else
            ./build.sh --install
        fi
    )
}

if [ -n "${LOCAL_PACKAGE_BUILD:-}" ] && [ "${LOCAL_PACKAGE_BUILD}" != "0" ]; then
    # Explicit local mode builds and installs the package set from the checked
    # out recipes and source-component revisions.
    build_local_packages
else
    if ! command -v psp-pacman >/dev/null 2>&1; then
        echo "ERROR: psp-pacman is not installed in PATH."
        exit 1
    fi

    # Prefer the published package repository when it is available. Until the
    # repository is populated, or if it is temporarily unavailable, fall back
    # to the checked-out package recipes instead of aborting the PSPDEV build.
    if psp-pacman -Sy --noconfirm &&
       psp-pacman -S --needed --noconfirm psp-libraries; then
        :
    else
        echo "WARNING: PSP package repository is unavailable; using local package builds."
        build_local_packages
    fi
fi

# CFW libraries and source-built PRX modules depend on PSP packages such as
# zlib and libpng, so build them only after the package stage is complete.
bash "${PSPSDK_SOURCE}/build-cfw-and-install.sh"
