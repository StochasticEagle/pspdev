#!/bin/bash
# ebootsigner by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/components/psp-ebootsigner"
BUILD="${SOURCE}/build"
STAGE="${BUILD}/install"
source "${ROOT}/install-permissions.sh"

if [ ! -f "${SOURCE}/CMakeLists.txt" ]; then
    echo "ERROR: psp-ebootsigner submodule is not initialized."
    echo "Run: git submodule update --init --recursive --depth=1"
    exit 1
fi

PROC_NR=$(getconf _NPROCESSORS_ONLN)

cmake -S "${SOURCE}" -B "${BUILD}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
    -DCMAKE_INSTALL_PREFIX="${STAGE}"

cmake --build "${BUILD}" --parallel "${PROC_NR}"

# Stage the CMake install as the invoking user so the persistent build tree
# remains writable for incremental builds. The PSPDEV permission layer only
# elevates the final installation into the selected prefix when necessary.
rm -rf "${STAGE}"
cmake --install "${BUILD}"

pspdev_run_install mkdir -p "${PSPDEV}/bin"
pspdev_run_install install -m 755 "${STAGE}/bin/ebootsign" "${PSPDEV}/bin/ebootsign"

## Store build information
pspdev_record_build_info "psp-ebootsigner" "$(git -C "${SOURCE}" log -1 --format="psp-ebootsigner %H %cs %s")"
