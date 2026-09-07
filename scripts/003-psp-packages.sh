#!/bin/bash
# psp-packages by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_SOURCE="${ROOT}/components/psp-packages"
PSPSDK_SOURCE="${ROOT}/components/pspsdk"

if [ ! -x "${PACKAGES_SOURCE}/build.sh" ]; then
    echo "ERROR: psp-packages submodule is not initialized."
    echo "Run: git submodule update --init --recursive --depth=1 components/psp-packages"
    exit 1
fi

if [ ! -f "${PSPSDK_SOURCE}/build-cfw-and-install.sh" ]; then
    echo "ERROR: PSPSDK CFW build script is not available."
    exit 1
fi

## Build and install the PSP package set. Existing package archives are reused,
## and package dependencies are installed recursively by psp-packages/build.sh.
cd "${PACKAGES_SOURCE}"
./build.sh --install

## CFW additions depend on PSP packages such as zlib and libpng, so they must be
## built only after the package set has been installed.
bash "${PSPSDK_SOURCE}/build-cfw-and-install.sh"
