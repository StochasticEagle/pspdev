#!/bin/bash
# build-all.sh by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT}/install-permissions.sh"

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

## PSP pacman tracks the current Arch pacman master source shallowly.
update_tracking_submodules \
    "${ROOT}/components/psp-toolchain/components/psp-pacman"

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

clear_pspdev_contents() {
    local dir

    if [[ -z "${PSPDEV:-}" || "${PSPDEV}" == "/" ]]; then
        echo "ERROR: Refusing to clear unsafe PSPDEV prefix: ${PSPDEV:-<unset>}" >&2
        return 1
    fi

    if [[ ! -d "${PSPDEV}" ]]; then
        return 0
    fi

    while IFS= read -r -d '' dir; do
        if [[ ! -w "${dir}" || ! -x "${dir}" ]]; then
            echo "ERROR: Cannot clear ${PSPDEV} without elevated privileges." >&2
            echo "Directory is not writable by the current user: ${dir}" >&2
            return 1
        fi
    done < <(find "${PSPDEV}" -type d -print0)

    find "${PSPDEV}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

## A full PSPDEV build starts from an empty installation prefix. The prefix
## directory itself is preserved so its ownership and permissions are unchanged.
## Targeted step builds remain incremental and do not clear the prefix.
if (( $# == 0 )) && [[ -e "${PSPDEV}" ]]; then
    if [[ ! -d "${PSPDEV}" ]]; then
        echo "ERROR: ${PSPDEV} exists but is not a directory." >&2
        exit 1
    fi
    if [[ "${PSPDEV}" == "/" ]]; then
        echo "ERROR: Refusing to clear PSPDEV=/." >&2
        exit 1
    fi
    if [[ ! -t 0 ]]; then
        echo "ERROR: Full build requires interactive confirmation before clearing:" >&2
        echo "  ${PSPDEV}" >&2
        exit 1
    fi

    printf 'Full build will permanently remove all contents of the existing PSPDEV installation:\n  %s\n' "${PSPDEV}"
    printf 'The PSPDEV directory itself will be preserved.\n'
    printf 'Type the full path exactly to confirm removal of its contents: '
    IFS= read -r confirmation
    if [[ "${confirmation}" != "${PSPDEV}" ]]; then
        echo "PSPDEV reset cancelled." >&2
        exit 1
    fi

    clear_pspdev_contents
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
pspdev_record_build_info "pspdev" "$(git -C "${ROOT}" log -1 --format="pspdev %H %cs %s")"
