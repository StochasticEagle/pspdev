#!/bin/bash
# toolchain.sh by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

## PSPDEV is the authoritative installation location.
if [ -z "${PSPDEV:-}" ]; then
  echo "ERROR: PSPDEV environment variable is not set."
  exit 1
fi

## Ensure the installed PSPDEV tools are available.
export PATH="${PSPDEV}/bin:${PATH}"

## Collect dependency scripts.
shopt -s nullglob
DEPEND_SCRIPTS=("${ROOT}"/depends/*.sh)
shopt -u nullglob

##Extra components only.
BUILD_SCRIPTS=(
    "${ROOT}/scripts/004-psp-linkusb.sh"
    "${ROOT}/scripts/005-psp-ebootsigner.sh"
)

## Run dependency checks.
for SCRIPT in "${DEPEND_SCRIPTS[@]}"; do
    "${SCRIPT}"
done

## If specific steps were requested...
if (( $# > 0 )); then

for STEP in "$@"; do
    if [[ ! "${STEP}" =~ ^[1-9][0-9]*$ ]] ||
       (( STEP > ${#BUILD_SCRIPTS[@]} )); then
        echo "ERROR: Invalid build step '${STEP}'."
        echo "Valid steps are 1-${#BUILD_SCRIPTS[@]}."
        exit 1
    fi

    SCRIPT="${BUILD_SCRIPTS[STEP-1]}"
    "${SCRIPT}"
done

else

## Run all extra build scripts.
for SCRIPT in "${BUILD_SCRIPTS[@]}"; do
    "${SCRIPT}"
done

fi

## Store build information.

BUILD_FILE="${PSPDEV}/build.txt"

if [[ -f "${BUILD_FILE}" ]]; then
sed -i'' '/^pspdev /d' "${BUILD_FILE}"
fi

git -C "${ROOT}" log -1 --format="pspdev %H %cs %s" >> "${BUILD_FILE}"



