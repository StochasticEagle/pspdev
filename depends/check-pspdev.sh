#!/bin/sh
# Check whether PSPDEV can be installed by this process or via sudo.

if [ -z "${PSPDEV:-}" ]; then
    echo "ERROR: Set \$PSPDEV before continuing."
    exit 1
fi

if [ -e "${PSPDEV}" ] && [ ! -d "${PSPDEV}" ]; then
    echo "ERROR: ${PSPDEV} exists but is not a directory."
    exit 1
fi

if [ -d "${PSPDEV}" ] && [ -w "${PSPDEV}" ] && [ -x "${PSPDEV}" ]; then
    exit 0
fi

parent="${PSPDEV}"
while [ ! -e "${parent}" ]; do
    next="$(dirname "${parent}")"
    [ "${next}" != "${parent}" ] || break
    parent="${next}"
done

if [ -d "${parent}" ] && [ -w "${parent}" ] && [ -x "${parent}" ]; then
    exit 0
fi

if command -v sudo >/dev/null 2>&1; then
    exit 0
fi

echo "ERROR: ${PSPDEV} is not writable by the current process and sudo is unavailable."
exit 1
