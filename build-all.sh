#!/bin/bash
# build-all.sh by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

## Update branch-tracking submodules shallowly.
##
## A shallow submodule clone may only have the ref selected during its initial
## clone, even when .gitmodules names a different tracking branch.  Do not rely
## on "git submodule update --remote" finding that remote-tracking ref.  Fetch
## the configured branch explicitly and update the submodule to that branch tip.
update_tracking_submodules() {
    local repo="$1"
    local key name branch path subrepo

    git -C "${repo}" submodule sync
    git -C "${repo}" submodule update --init --depth 1

    while read -r key branch; do
        [[ -n "${key}" && -n "${branch}" ]] || continue

        name="${key#submodule.}"
        name="${name%.branch}"
        path="$(git -C "${repo}" config -f .gitmodules --get "submodule.${name}.path")"

        if [[ -z "${path}" ]]; then
            echo "ERROR: No path configured for submodule '${name}' in ${repo}/.gitmodules"
            exit 1
        fi

        subrepo="${repo}/${path}"

        git -C "${subrepo}" fetch --depth 1 origin \
            "+refs/heads/${branch}:refs/remotes/origin/${branch}"
        git -C "${subrepo}" checkout --detach "refs/remotes/origin/${branch}"
    done < <(git -C "${repo}" config -f .gitmodules \
        --get-regexp '^submodule\..*\.branch$' || true)
}

## Refresh the top-level StochasticEagle forks to their configured branch heads.
update_tracking_submodules "${ROOT}"

## The toolchain hierarchy consists of StochasticEagle forks and is intentionally
## floating: always build the current configured fork branches recursively.
update_tracking_submodules "${ROOT}/components/psp-toolchain"
update_tracking_submodules \
    "${ROOT}/components/psp-toolchain/components/psp-toolchain-allegrex"

## PSPSDK also contains a StochasticEagle forked component; keep that current.
update_tracking_submodules "${ROOT}/components/pspsdk"

## Package source components are third-party release selections.  Initialize them
## at the revisions selected by psp-packages; do not float them to development
## branch heads with --remote.
git -C "${ROOT}/components/psp-packages" submodule sync --recursive
git -C "${ROOT}/components/psp-packages" submodule update \
    --init --recursive --depth 1

## PSPDEV is the authoritative installation location.
if [ -z "${PSPDEV:-}" ]; then
    echo "ERROR: PSPDEV environment variable is not set."
    exit 1
fi

## Ensure tools installed earlier in the build are used by later stages.
export PATH="${PSPDEV}/bin:${PATH}"

## Collect dependency and build scripts.
shopt -s nullglob
DEPEND_SCRIPTS=("${ROOT}"/depends/*.sh)
BUILD_SCRIPTS=("${ROOT}"/scripts/*.sh)
shopt -u nullglob

## Run dependency checks.
for SCRIPT in "${DEPEND_SCRIPTS[@]}"; do
    "${SCRIPT}"
done

if (( ${#BUILD_SCRIPTS[@]} == 0 )); then
    echo "ERROR: No build scripts found."
    exit 1
fi

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

    ## Run all build scripts.
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
