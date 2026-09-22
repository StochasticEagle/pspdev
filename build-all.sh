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

PROGRESS_MODE=""
if [[ "${1:-}" == "p" ]]; then
    PROGRESS_MODE="true"
    shift
fi
FULL_BUILD=0
(( $# == 0 )) && FULL_BUILD=1

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
if (( FULL_BUILD )) && [[ -e "${PSPDEV}" ]]; then
    if [[ ! -d "${PSPDEV}" ]]; then
        echo "ERROR: ${PSPDEV} exists but is not a directory." >&2
        exit 1
    fi
    if [[ "${PSPDEV}" == "/" ]]; then
        echo "ERROR: Refusing to clear PSPDEV=/." >&2
        exit 1
    fi

    if find "${PSPDEV}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
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
fi

## Ensure tools installed earlier in the build are used by later stages.
export PATH="${PSPDEV}/bin:${PATH}"

## Collect dependency and build scripts.
shopt -s nullglob
DEPEND_SCRIPTS=("${ROOT}"/depends/*.sh)
BUILD_SCRIPTS=("${ROOT}"/scripts/*.sh)
shopt -u nullglob

stage_label() {
    case "$1" in
        1) printf '%s\n' "PSP toolchain" ;;
        2) printf '%s\n' "PSPSDK" ;;
        3) printf '%s\n' "PSP packages" ;;
        4) printf '%s\n' "psp-linkusb" ;;
        5) printf '%s\n' "psp-ebootsigner" ;;
        *) printf '%s\n' "Step $1" ;;
    esac
}

render_stage_progress() {
    local step="$1"
    local total="$2"
    local label="$3"
    local last="$4"
    local width=30
    local filled=$(( step * width / total ))
    local empty=$(( width - filled ))
    local done_bar
    local left_bar

    printf -v done_bar '%*s' "${filled}" ''
    printf -v left_bar '%*s' "${empty}" ''
    done_bar="${done_bar// /#}"
    left_bar="${left_bar// /-}"
    printf '\033[2A\r\033[2K[%s%s] %d/%d %s\n\r\033[2K%s\n' "${done_bar}" "${left_bar}" "${step}" "${total}" "${label}" "${last}"
}

persist_progress_log() {
    local source="$1"
    local destination="$2"

    pspdev_run_install mkdir -p "${PSPDEV}/build/logs"
    pspdev_run_install cp "${source}" "${destination}"
}

run_progress_step() {
    local step="$1"
    local script="$2"
    local total="${#BUILD_SCRIPTS[@]}"
    local label
    local stamp
    local temp_log
    local final_log
    local line
    local current
    local package_total
    local package
    local state
    local status
    local last

    label="$(stage_label "${step}")"
    stamp="$(date +%Y%m%d-%H%M%S)"
    temp_log="$(mktemp)"
    final_log="${PSPDEV}/build/logs/step-${step}-${stamp}.log"
    printf 'START step=%s label=%s\n' "${step}" "${label}" > "${temp_log}"

    printf '\n\n'
    render_stage_progress "${step}" "${total}" "${label}" "Starting ${label}"

    set +e
    if (( step == 3 )); then
        PSPDEV_PROGRESS=1 "${script}" 2>&1 |
            while IFS= read -r line; do
                if [[ "${line}" == PSP_PROGRESS* || "${line}" == ERROR:* || "${line}" == WARNING:* ]]; then
                    printf '%s\n' "${line}" >> "${temp_log}"
                fi
                if [[ "${line}" == PSP_PROGRESS* ]]; then
                    IFS="$(printf '\t')" read -r _ current package_total package state <<< "${line}"
                    render_stage_progress "${step}" "${total}" "${label}" "Packages ${current}/${package_total}: ${state} ${package}"
                elif [[ "${line}" == ERROR:* || "${line}" == WARNING:* ]]; then
                    render_stage_progress "${step}" "${total}" "${label}" "${line}"
                fi
            done
    else
        "${script}" 2>&1 |
            while IFS= read -r line; do
                printf '%s\n' "${line}" >> "${temp_log}"
                if [[ "${line}" =~ ^(Building|Installing|Cleaning|Configuring|Reusing|ERROR:|WARNING:|==\>[[:space:]](Making|Starting|Finished|Creating|Installing)) ]]; then
                    render_stage_progress "${step}" "${total}" "${label}" "${line}"
                fi
            done
    fi
    status=${PIPESTATUS[0]}
    set -e

    if (( status == 0 )); then
        printf 'DONE step=%s label=%s\n' "${step}" "${label}" >> "${temp_log}"
        render_stage_progress "${step}" "${total}" "${label}" "Completed ${label}"
    else
        printf 'FAILED step=%s label=%s status=%s\n' "${step}" "${label}" "${status}" >> "${temp_log}"
        last="$(tail -n 1 "${temp_log}")"
        render_stage_progress "${step}" "${total}" "${label}" "${last}"
    fi

    persist_progress_log "${temp_log}" "${final_log}"
    rm -f "${temp_log}"
    printf 'Log: %s\n' "${final_log}"
    return "${status}"
}

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
        if [[ -n "${PROGRESS_MODE}" && -t 1 && -z "${CI:-}" ]]; then
            run_progress_step "${STEP}" "${SCRIPT}"
        else
            "${SCRIPT}"
        fi
    done

else

    ## Run all build scripts.
    STEP=0
    for SCRIPT in "${BUILD_SCRIPTS[@]}"; do
        STEP=$(( STEP + 1 ))
        if [[ -n "${PROGRESS_MODE}" && -t 1 && -z "${CI:-}" ]]; then
            run_progress_step "${STEP}" "${SCRIPT}"
        else
            "${SCRIPT}"
        fi
    done

fi

## Store build information.
pspdev_record_build_info "pspdev" "$(git -C "${ROOT}" log -1 --format="pspdev %H %cs %s")"
