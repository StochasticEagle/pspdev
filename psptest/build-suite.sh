#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_ROOT="${ROOT}/build/psptest"
MODULE_BUILD_ROOT="${BUILD_ROOT}/modules"
LAUNCHER_BUILD="${BUILD_ROOT}/launcher"
STAGE="${ROOT}/build/PSP/GAME/psptest"
MANIFEST="${STAGE}/manifest.tsv"
ARCHIVE="${ROOT}/build/psptest.tar.gz"
EXPORTS="${ROOT}/psptest/psptest.exp"

if [[ -z "${PSPDEV:-}" ]]; then
    echo "ERROR: PSPDEV is not set." >&2
    exit 1
fi

export PATH="${PSPDEV}/bin:${PATH}"

if [[ ! -f "${PSPDEV}/psp/sdk/include/psptest.h" || ! -f "${PSPDEV}/psp/sdk/lib/libpsptest.a" ]]; then
    echo "ERROR: Installed PSPSDK does not provide PSPTEST." >&2
    exit 1
fi

rm -rf "${BUILD_ROOT}" "${STAGE}"
mkdir -p "${MODULE_BUILD_ROOT}" "${LAUNCHER_BUILD}" "${STAGE}/results"

make -C "${LAUNCHER_BUILD}" -f "${ROOT}/psptest/launcher/Makefile" VPATH="${ROOT}/psptest/launcher" all
install -m 644 "${LAUNCHER_BUILD}/EBOOT.PBP" "${STAGE}/EBOOT.PBP"
printf 'PSPTEST_MANIFEST\t1\n' > "${MANIFEST}"

build_namespace() {
    local source_root="$1"
    local namespace="$2"
    local makefile source_dir module build_dir stage_dir target prx

    [[ -d "${source_root}" ]] || return 0

    while IFS= read -r -d '' makefile; do
        source_dir="$(dirname "${makefile}")"
        module="$(basename "${source_dir}")"
        build_dir="${MODULE_BUILD_ROOT}/${namespace}/${module}"
        stage_dir="${STAGE}/${namespace}/${module}"

        mkdir -p "${build_dir}" "${stage_dir}"

        target="$(make -s -C "${build_dir}" -f "${makefile}" VPATH="${source_dir}" PRX_EXPORTS="${EXPORTS}" --no-print-directory -pn | awk -F ' = ' '/^TARGET = / { print $2; exit }')"
        if [[ -z "${target}" ]]; then
            echo "ERROR: Unable to resolve TARGET from ${makefile}." >&2
            exit 1
        fi

        echo "Building PSPTEST ${namespace}/${module} ..."
        make -C "${build_dir}" -f "${makefile}" VPATH="${source_dir}" PRX_EXPORTS="${EXPORTS}" all

        prx="${build_dir}/${target}.prx"
        if [[ ! -f "${prx}" ]]; then
            echo "ERROR: PSPTEST ${namespace}/${module} did not produce ${target}.prx." >&2
            exit 1
        fi

        install -m 644 "${prx}" "${stage_dir}/test.prx"
        printf 'TEST\t%s/%s\t%s/%s/test.prx\tmodule\n' "${namespace}" "${module}" "${namespace}" "${module}" >> "${MANIFEST}"
    done < <(find "${source_root}" -mindepth 2 -maxdepth 2 -type f -name Makefile.test -print0 | sort -z)
}

build_namespace "${ROOT}/components/pspsdk/psptest" "pspsdk"
build_namespace "${ROOT}/components/psp-packages/psptest" "packages"

if ! grep -q '^TEST' "${MANIFEST}"; then
    echo "ERROR: No PSPTEST modules were discovered." >&2
    exit 1
fi

tar -czf "${ARCHIVE}" -C "${ROOT}/build" PSP

echo "PSPTEST bundle:"
echo "  ${STAGE}"
echo "Archive:"
echo "  ${ARCHIVE}"
