#!/bin/bash
# ebootsigner by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
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


prepare_cmake_tree() {
    local build="$1"
    local source="$2"
    local cache_source cache_build

    [[ -f "${build}/CMakeCache.txt" ]] || return 0

    cache_source="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "${build}/CMakeCache.txt" | tail -n 1)"
    cache_build="$(sed -n 's/^CMAKE_CACHEFILE_DIR:INTERNAL=//p' "${build}/CMakeCache.txt" | tail -n 1)"

    if [[ "${cache_source}" != "${source}" || "${cache_build}" != "${build}" ]]; then
        echo "Refreshing relocated psp-ebootsigner CMake tree."
        rm -rf "${build}"
    fi
}


## Re-run CMake in place so host/source changes refresh configuration while
## unchanged objects remain available for incremental rebuilds.
prepare_cmake_tree "${BUILD}" "${SOURCE}"
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
