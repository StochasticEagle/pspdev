#!/usr/bin/env bash
# Shared PSPDEV install-permission helpers.
#
# Build commands run with the current process permissions. Installation
# commands elevate only when the current process cannot write the PSPDEV prefix.

pspdev_prefix_is_writable() {
    local target="${PSPDEV:-}"
    local parent dir next
    [[ -n "${target}" ]] || return 1

    if [[ -e "${target}" ]]; then
        [[ -d "${target}" && -w "${target}" && -x "${target}" ]] || return 1
        while IFS= read -r -d '' dir; do
            [[ -w "${dir}" && -x "${dir}" ]] || return 1
        done < <(find "${target}" -type d -print0)
        return 0
    fi

    parent="${target}"
    while [[ ! -e "${parent}" ]]; do
        next="$(dirname "${parent}")"
        [[ "${next}" != "${parent}" ]] || break
        parent="${next}"
    done

    [[ -d "${parent}" && -w "${parent}" && -x "${parent}" ]]
}

pspdev_prepare_install() {
    if pspdev_prefix_is_writable; then
        PSPDEV_INSTALL_ELEVATED=0
        return 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        echo "ERROR: ${PSPDEV:-<unset>} is not writable by the current process and sudo is unavailable." >&2
        return 1
    fi

    PSPDEV_INSTALL_ELEVATED=1
}

pspdev_run_install() {
    if [[ -z "${PSPDEV_INSTALL_ELEVATED+x}" ]]; then
        pspdev_prepare_install || return 1
    fi

    if (( PSPDEV_INSTALL_ELEVATED )); then
        sudo env \
            "PSPDEV=${PSPDEV}" \
            "PATH=${PATH}" \
            "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}" \
            "$@"
    else
        "$@"
    fi
}

pspdev_record_build_info() {
    local key="$1"
    local line="$2"
    local build_file="${PSPDEV}/build.txt"

    pspdev_run_install sh -c '
        file="$1"
        key="$2"
        line="$3"
        tmp="$(mktemp)"
        if [ -f "$file" ]; then
            grep -v "^$key " "$file" > "$tmp" || true
        fi
        printf "%s\n" "$line" >> "$tmp"
        mkdir -p "$(dirname "$file")"
        install -m 644 "$tmp" "$file"
        rm -f "$tmp"
    ' _ "${build_file}" "${key}" "${line}"
}
