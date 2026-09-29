#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_ROOT="${ROOT}/build/psptest"
MODULE_BUILD_ROOT="${BUILD_ROOT}/modules"
LAUNCHER_BUILD="${BUILD_ROOT}/launcher"
PROGRAM_ROOT="${ROOT}/build/PSP/GAME/psptest"
MANIFEST="${PROGRAM_ROOT}/manifest.tsv"
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

rm -rf "${BUILD_ROOT}" "${PROGRAM_ROOT}"
mkdir -p "${MODULE_BUILD_ROOT}" "${LAUNCHER_BUILD}" "${PROGRAM_ROOT}/results"

make -C "${LAUNCHER_BUILD}" -f "${ROOT}/psptest/launcher/Makefile" VPATH="${ROOT}/psptest/launcher" all
cp "${LAUNCHER_BUILD}/EBOOT.PBP" "${PROGRAM_ROOT}/EBOOT.PBP"
printf 'PSPTEST_MANIFEST\t1\n' > "${MANIFEST}"

source_tree_state() {
    local repository="$1"
    git -C "${repository}" status --porcelain=v1 --untracked-files=all --ignored=matching -- psptest
}

PSPSDK_TEST_STATE_BEFORE="$(source_tree_state "${ROOT}/components/pspsdk")"
PACKAGES_TEST_STATE_BEFORE="$(source_tree_state "${ROOT}/components/psp-packages")"

build_namespace() {
    local source_root="$1"
    local namespace="$2"
    local makefile source_dir module build_dir program_module_dir prx local_exports
    local -a prx_files

    [[ -d "${source_root}" ]] || return 0

    while IFS= read -r -d '' makefile; do
        source_dir="$(dirname "${makefile}")"
        module="$(basename "${source_dir}")"
        build_dir="${MODULE_BUILD_ROOT}/${namespace}/${module}"
        program_module_dir="${PROGRAM_ROOT}/${namespace}/${module}"

        mkdir -p "${build_dir}" "${program_module_dir}"
        local_exports="${build_dir}/psptest.exp"
        install -m 644 "${EXPORTS}" "${local_exports}"

        echo "Building PSPTEST ${namespace}/${module} ..."
        make -C "${build_dir}" -f "${makefile}" VPATH="${source_dir}" PRX_EXPORTS="${local_exports}" all

        mapfile -t prx_files < <(find "${build_dir}" -maxdepth 1 -type f -name '*.prx' -print | sort)
        if (( ${#prx_files[@]} != 1 )); then
            echo "ERROR: PSPTEST ${namespace}/${module} produced ${#prx_files[@]} PRX files; expected exactly one module PRX." >&2
            exit 1
        fi
        prx="${prx_files[0]}"

        cp "${prx}" "${program_module_dir}/test.prx"
        printf 'TEST\t%s/%s\t%s/%s/test.prx\tmodule\n' "${namespace}" "${module}" "${namespace}" "${module}" >> "${MANIFEST}"
    done < <(find "${source_root}" -mindepth 2 -maxdepth 2 -type f -name Makefile.test -print0 | sort -z)
}

build_namespace "${ROOT}/components/pspsdk/psptest" "pspsdk"
build_namespace "${ROOT}/components/psp-packages/psptest" "packages"

PSPSDK_TEST_STATE_AFTER="$(source_tree_state "${ROOT}/components/pspsdk")"
PACKAGES_TEST_STATE_AFTER="$(source_tree_state "${ROOT}/components/psp-packages")"

if [[ "${PSPSDK_TEST_STATE_BEFORE}" != "${PSPSDK_TEST_STATE_AFTER}" ]]; then
    echo "ERROR: PSPTEST build modified or generated files under components/pspsdk/psptest." >&2
    diff -u <(printf '%s\n' "${PSPSDK_TEST_STATE_BEFORE}") <(printf '%s\n' "${PSPSDK_TEST_STATE_AFTER}") || true
    exit 1
fi
if [[ "${PACKAGES_TEST_STATE_BEFORE}" != "${PACKAGES_TEST_STATE_AFTER}" ]]; then
    echo "ERROR: PSPTEST build modified or generated files under components/psp-packages/psptest." >&2
    diff -u <(printf '%s\n' "${PACKAGES_TEST_STATE_BEFORE}") <(printf '%s\n' "${PACKAGES_TEST_STATE_AFTER}") || true
    exit 1
fi

if ! grep -q '^TEST' "${MANIFEST}"; then
    echo "ERROR: No PSPTEST modules were discovered." >&2
    exit 1
fi

tar -czf "${ARCHIVE}" -C "${ROOT}/build" PSP

echo "PSPTEST program tree:"
echo "  ${PROGRAM_ROOT}"
echo "Archive:"
echo "  ${ARCHIVE}"
