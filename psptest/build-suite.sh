#!/usr/bin/env bash

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${ROOT}/build/psptest"
STAGE="${BUILD_ROOT}/PSP/GAME/PSPDEV-TEST"
LAUNCHER_BUILD="${BUILD_ROOT}/launcher"
MANIFEST="${STAGE}/tests.manifest"
BUILD_INFO="${STAGE}/build-info.txt"

if [[ -z "${PSPDEV:-}" ]]; then
    echo "ERROR: PSPDEV is not set." >&2
    exit 1
fi

export PATH="${PSPDEV}/bin:${PATH}"

if [[ ! -f "${PSPDEV}/psp/sdk/include/psptest.h" || ! -f "${PSPDEV}/psp/sdk/lib/libpsptest.a" ]]; then
    echo "ERROR: Installed PSPSDK does not provide PSPTEST yet." >&2
    echo "Install a PSPSDK build containing psptest.h and libpsptest.a first." >&2
    exit 1
fi

rm -rf "${BUILD_ROOT}"
mkdir -p "${LAUNCHER_BUILD}" "${STAGE}/tests/pspsdk" "${STAGE}/tests/packages"
cp "${ROOT}/psptest/launcher/Makefile" "${ROOT}/psptest/launcher/main.c" "${LAUNCHER_BUILD}/"
make -C "${LAUNCHER_BUILD}" -j "$(getconf _NPROCESSORS_ONLN)"
install -m 644 "${LAUNCHER_BUILD}/EBOOT.PBP" "${STAGE}/EBOOT.PBP"

: > "${MANIFEST}"

git_head() {
    local repository="$1"
    if git -C "${repository}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "${repository}" rev-parse HEAD
    else
        printf 'unknown\n'
    fi
}

{
    printf 'pspdev %s\n' "$(git_head "${ROOT}")"
    printf 'pspsdk %s\n' "$(git_head "${ROOT}/components/pspsdk")"
    printf 'psp-packages %s\n' "$(git_head "${ROOT}/components/psp-packages")"
} > "${BUILD_INFO}"

build_test_tree() {
    local source_root="$1"
    local namespace="$2"
    local makefile module module_source module_build module_stage

    if [[ ! -d "${source_root}" ]]; then
        echo "ERROR: Test source tree is unavailable: ${source_root}" >&2
        exit 1
    fi

    while IFS= read -r -d '' makefile; do
        module_source="$(dirname "${makefile}")"
        module="$(basename "${module_source}")"
        module_build="${BUILD_ROOT}/modules/${namespace}/${module}"
        module_stage="${STAGE}/tests/${namespace}/${module}"

        rm -rf "${module_build}"
        mkdir -p "${module_build}" "${module_stage}"
        cp -a "${module_source}/." "${module_build}/"

        echo "Building PSPTEST ${namespace}/${module} ..."
        make -C "${module_build}" -f Makefile.test -j "$(getconf _NPROCESSORS_ONLN)"

        if [[ ! -f "${module_build}/EBOOT.PBP" ]]; then
            echo "ERROR: PSPTEST ${namespace}/${module} did not produce EBOOT.PBP." >&2
            exit 1
        fi

        install -m 644 "${module_build}/EBOOT.PBP" "${module_stage}/EBOOT.PBP"
        printf '%s\t%s\t%s / %s\ttests/%s/%s/EBOOT.PBP\n' "${namespace}" "${module}" "${namespace}" "${module}" "${namespace}" "${module}" >> "${MANIFEST}"
    done < <(find "${source_root}" -mindepth 2 -maxdepth 2 -type f -name Makefile.test -print0 | sort -z)
}

build_test_tree "${ROOT}/components/pspsdk/psptest" "pspsdk"
build_test_tree "${ROOT}/components/psp-packages/psptest" "packages"

if [[ ! -s "${MANIFEST}" ]]; then
    echo "ERROR: No PSPTEST modules were found." >&2
    exit 1
fi

tar -czf "${BUILD_ROOT}/pspdev-tests.tar.gz" -C "${BUILD_ROOT}" PSP

echo "PSPTEST suite staged at:"
echo "  ${STAGE}"
echo "Archive:"
echo "  ${BUILD_ROOT}/pspdev-tests.tar.gz"
