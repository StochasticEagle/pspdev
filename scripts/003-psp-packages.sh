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

if [ -n "${LOCAL_PACKAGE_BUILD:-}" ] && [ "${LOCAL_PACKAGE_BUILD}" != "0" ]; then
    if [ ! -x "${PACKAGES_SOURCE}/build.sh" ]; then
        echo "ERROR: psp-packages submodule is not initialized."
        echo "Run: git submodule update --init --recursive --depth=1 components/psp-packages"
        exit 1
    fi

    # Explicit local mode builds and installs the package set from the checked
    # out recipes and source-component revisions.
    cd "${PACKAGES_SOURCE}"
    ./build.sh --install
else
    if ! command -v psp-pacman >/dev/null 2>&1; then
        echo "ERROR: psp-pacman is not installed in PATH."
        exit 1
    fi

    # Normal PSPDEV installs consume the package repository published by
    # StochasticEagle/psp-packages through GitHub Pages.
    psp-pacman -Sy --noconfirm
    psp-pacman -S --needed --noconfirm psp-libraries
fi

# CFW libraries and source-built PRX modules depend on PSP packages such as
# zlib and libpng, so build them only after the package stage is complete.
bash "${PSPSDK_SOURCE}/build-cfw-and-install.sh"
