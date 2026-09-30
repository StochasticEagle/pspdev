#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_ROOT="${ROOT}/build/psptest"
FRAMEWORK_BUILD="${BUILD_ROOT}/framework"
MODULE_BUILD_ROOT="${BUILD_ROOT}/modules"
LAUNCHER_BUILD="${BUILD_ROOT}/launcher"
PSPTEST_SOURCE="${ROOT}/components/pspsdk/src/psptest"
PROGRAM_ROOT="${ROOT}/build/PSP/GAME/psptest"
MANIFEST="${PROGRAM_ROOT}/manifest.tsv"
ARCHIVE="${ROOT}/build/psptest.tar.gz"
EXPORTS="${ROOT}/psptest/psptest.exp"
MODULE_OVERRIDES="${BUILD_ROOT}/module-overrides.mk"

if [[ -z "${PSPDEV:-}" ]]; then
    echo "ERROR: PSPDEV is not set." >&2
    exit 1
fi

export PATH="${PSPDEV}/bin:${PATH}"
PSPSDK="$(psp-config --pspsdk-path)"

if [[ ! -f "${PSPTEST_SOURCE}/psptest.h" || ! -f "${PSPTEST_SOURCE}/psptest.c" ]]; then
    echo "ERROR: PSPSDK PSPTEST framework source is unavailable." >&2
    exit 1
fi

source_tree_state() {
    local repository="$1"
    shift
    git -C "${repository}" status --porcelain=v1 --untracked-files=all --ignored=matching -- "$@"
}

PSPSDK_TEST_STATE_BEFORE="$(source_tree_state "${ROOT}/components/pspsdk" src/psptest psptest)"
PACKAGES_TEST_STATE_BEFORE="$(source_tree_state "${ROOT}/components/psp-packages" psptest)"

rm -rf "${BUILD_ROOT}" "${PROGRAM_ROOT}"
mkdir -p "${FRAMEWORK_BUILD}" "${MODULE_BUILD_ROOT}" "${LAUNCHER_BUILD}" "${PROGRAM_ROOT}/results"

cat > "${MODULE_OVERRIDES}" <<'EOF'
override LDFLAGS += -nostartfiles
EOF

echo "Building PSPTEST framework ..."
psp-gcc -O2 -G0 -Wall -Wextra -Werror -I"${PSPTEST_SOURCE}" -I"${PSPSDK}/include" -c "${PSPTEST_SOURCE}/psptest.c" -o "${FRAMEWORK_BUILD}/psptest.o"
psp-gcc-ar rcs "${FRAMEWORK_BUILD}/libpsptest.a" "${FRAMEWORK_BUILD}/psptest.o"
psp-gcc-ranlib "${FRAMEWORK_BUILD}/libpsptest.a"

make -C "${LAUNCHER_BUILD}" -f "${ROOT}/psptest/launcher/Makefile" VPATH="${ROOT}/psptest/launcher" PSPTEST_FRAMEWORK_INCDIR="${PSPTEST_SOURCE}" PSPTEST_FRAMEWORK_LIBDIR="${FRAMEWORK_BUILD}" all
cp "${LAUNCHER_BUILD}/EBOOT.PBP" "${PROGRAM_ROOT}/EBOOT.PBP"
printf 'PSPTEST_MANIFEST\t1\n' > "${MANIFEST}"

build_namespace() {
    local source_root="$1"
    local namespace="$2"
    local makefile source_dir module build_dir program_module_dir prx local_exports build_log make_status
    local -a prx_files elf_files

    [[ -d "${source_root}" ]] || return 0

    mkdir -p "${PROGRAM_ROOT}/results/${namespace}"

    while IFS= read -r -d '' makefile; do
        source_dir="$(dirname "${makefile}")"
        module="$(basename "${source_dir}")"
        build_dir="${MODULE_BUILD_ROOT}/${namespace}/${module}"
        program_module_dir="${PROGRAM_ROOT}/${namespace}/${module}"

        mkdir -p "${build_dir}" "${program_module_dir}"
        local_exports="${build_dir}/psptest.exp"
        install -m 644 "${EXPORTS}" "${local_exports}"

        echo "Building PSPTEST ${namespace}/${module} ..."
        build_log="${build_dir}/build.log"
        set +e
        make -C "${build_dir}" -f "${makefile}" -f "${MODULE_OVERRIDES}" VPATH="${source_dir}" PSPTEST_FRAMEWORK_INCDIR="${PSPTEST_SOURCE}" PRX_EXPORTS="${local_exports}" all 2>&1 | tee "${build_log}"
        make_status=${PIPESTATUS[0]}
        set -e
        if (( make_status != 0 )); then
            exit "${make_status}"
        fi
        if grep -Fq 'could not fixup imports, stubs out of order' "${build_log}"; then
            echo "ERROR: PSPTEST ${namespace}/${module} has out-of-order PRX import stubs; refusing to package the module." >&2
            exit 1
        fi

        if grep -Eq -- '(^|[[:space:]])-lpsptest([[:space:]]|$)' "${build_log}"; then
            echo "ERROR: PSPTEST ${namespace}/${module} links the runner library; test PRXs must be registration-only." >&2
            exit 1
        fi

        if ! grep -Fq -- '-nostartfiles' "${build_log}"; then
            echo "ERROR: PSPTEST ${namespace}/${module} was linked without -nostartfiles." >&2
            exit 1
        fi

        mapfile -t elf_files < <(find "${build_dir}" -maxdepth 1 -type f -name '*.elf' -print | sort)
        if (( ${#elf_files[@]} != 1 )); then
            echo "ERROR: PSPTEST ${namespace}/${module} produced ${#elf_files[@]} ELF files; expected exactly one module ELF." >&2
            exit 1
        fi
        if psp-nm -g "${elf_files[0]}" | grep -Eq '[[:space:]]_start$'; then
            echo "ERROR: PSPTEST ${namespace}/${module} still contains CRT _start; refusing to package it as a loadable test module." >&2
            exit 1
        fi
        if ! psp-nm -g "${elf_files[0]}" | grep -Eq '[[:space:]]module_start        mapfile -t prx_files < <(find "${build_dir}" -maxdepth 1 -type f -name '*.prx' -print | sort)
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

PSPSDK_TEST_STATE_AFTER="$(source_tree_state "${ROOT}/components/pspsdk" src/psptest psptest)"
PACKAGES_TEST_STATE_AFTER="$(source_tree_state "${ROOT}/components/psp-packages" psptest)"

if [[ "${PSPSDK_TEST_STATE_BEFORE}" != "${PSPSDK_TEST_STATE_AFTER}" ]]; then
    echo "ERROR: PSPTEST build modified or generated files under PSPSDK PSPTEST source paths." >&2
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

tar -czf "${ARCHIVE}" -C "${ROOT}/build" PSP/GAME/psptest

echo "PSPTEST program tree:"
echo "  ${PROGRAM_ROOT}"
echo "Archive:"
echo "  ${ARCHIVE}"
; then
            echo "ERROR: PSPTEST ${namespace}/${module} does not export a direct module_start entry." >&2
            exit 1
        fi

        if psp-nm -u "${elf_files[0]}" | grep -Eq 'psptest_run_suite|psptest_run_suite_to_file|psptest_run_module'; then
            echo "ERROR: PSPTEST ${namespace}/${module} references runner/orchestrator symbols." >&2
            exit 1
        fi

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

PSPSDK_TEST_STATE_AFTER="$(source_tree_state "${ROOT}/components/pspsdk" src/psptest psptest)"
PACKAGES_TEST_STATE_AFTER="$(source_tree_state "${ROOT}/components/psp-packages" psptest)"

if [[ "${PSPSDK_TEST_STATE_BEFORE}" != "${PSPSDK_TEST_STATE_AFTER}" ]]; then
    echo "ERROR: PSPTEST build modified or generated files under PSPSDK PSPTEST source paths." >&2
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

tar -czf "${ARCHIVE}" -C "${ROOT}/build" PSP/GAME/psptest

echo "PSPTEST program tree:"
echo "  ${PROGRAM_ROOT}"
echo "Archive:"
echo "  ${ARCHIVE}"
