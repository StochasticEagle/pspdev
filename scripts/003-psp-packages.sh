#!/bin/bash
# psp-packages by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_SOURCE="${ROOT}/components/psp-packages"
PSPSDK_SOURCE="${ROOT}/components/pspsdk"

if [ ! -f "${PSPSDK_SOURCE}/build-cfw-and-install.sh" ]; then
    echo "ERROR: PSPSDK CFW build script is not available."
    exit 1
fi


package_repo_source_sha() {
    local server arch

    server="$(awk '
        /^\[pspdev\]$/ { in_repo = 1; next }
        /^\[/ { in_repo = 0 }
        in_repo && /^[[:space:]]*Server[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            print
            exit
        }
    ' "${PSPDEV}/etc/pacman.conf")"

    [[ -n "${server}" ]] || return 1

    server="${server//\$repo/pspdev}"
    if [[ "${server}" == *'\$arch'* ]]; then
        arch="$("${PSPDEV}/share/pacman/bin/get-arch")"
        server="${server//\$arch/${arch}}"
    fi

    wget -qO- "${server%/}/psp-packages.sha"
}

package_repo_matches_checkout() {
    local checkout_sha remote_sha

    checkout_sha="$(git -C "${PACKAGES_SOURCE}" rev-parse HEAD)"
    remote_sha="$(package_repo_source_sha 2>/dev/null || true)"

    if [[ ! "${remote_sha}" =~ ^[0-9a-fA-F]{40}$ ]]; then
        echo "WARNING: Published PSP package repository has no valid source-SHA marker." >&2
        return 1
    fi

    if [[ "${remote_sha,,}" != "${checkout_sha,,}" ]]; then
        echo "WARNING: Published PSP packages were built from ${remote_sha}, but the checkout is ${checkout_sha}." >&2
        return 1
    fi

    return 0
}

build_local_packages() {
    local status

    if [ ! -x "${PACKAGES_SOURCE}/build.sh" ]; then
        echo "ERROR: psp-packages submodule is not initialized."
        echo "Run: git submodule update --init --recursive --depth=1 components/psp-packages"
        return 1
    fi

    echo "Building and installing PSP packages locally."

    set +e
    (
        cd "${PACKAGES_SOURCE}" || exit 1
        if [[ "${PSPDEV_PROGRESS:-0}" == "1" ]]; then
            PSP_PROGRESS_PARENT=1 ./build.sh p --install
        else
            ./build.sh --install
        fi
    )
    status=$?
    set -e

    if (( status != 0 )); then
        echo "ERROR: Local PSP package fallback failed with status ${status}."
        return "${status}"
    fi

    return 0
}

if [ -n "${LOCAL_PACKAGE_BUILD:-}" ] && [ "${LOCAL_PACKAGE_BUILD}" != "0" ]; then
    # Explicit local mode builds and installs the package set from the checked
    # out recipes and source-component revisions.
    build_local_packages
else
    if ! command -v psp-pacman >/dev/null 2>&1; then
        echo "ERROR: psp-pacman is not installed in PATH."
        exit 1
    fi

    # Use published packages only when the repository explicitly identifies
    # the same psp-packages commit as this checkout. A mismatch is data, not a
    # shell failure: normal development builds fall back to the local checkout.
    repo_matches=0
    if package_repo_matches_checkout; then
        repo_matches=1
    fi

    if (( repo_matches )); then
        if psp-pacman -Sy --noconfirm &&
           psp-pacman -S --needed --noconfirm psp-libraries; then
            :
        elif [ -n "${PSP_PACKAGE_REPO_REQUIRED:-}" ] && [ "${PSP_PACKAGE_REPO_REQUIRED}" != "0" ]; then
            echo "ERROR: Matching published PSP package repository is unavailable or incomplete."
            exit 1
        else
            echo "WARNING: Matching PSP package repository could not be installed; using local package builds."
            build_local_packages
        fi
    elif [ -n "${PSP_PACKAGE_REPO_REQUIRED:-}" ] && [ "${PSP_PACKAGE_REPO_REQUIRED}" != "0" ]; then
        echo "ERROR: Published PSP package repository does not match the checked-out psp-packages commit."
        exit 1
    else
        echo "Using local PSP package builds because no matching published repository exists."
        build_local_packages
    fi
fi

# CFW libraries and source-built PRX modules depend on PSP packages such as
# zlib and libpng, so build them only after the package stage is complete.
bash "${PSPSDK_SOURCE}/build-cfw-and-install.sh"
