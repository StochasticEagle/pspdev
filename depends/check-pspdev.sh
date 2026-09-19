#!/bin/sh
# Validate the PSPDEV installation prefix configuration.
#
# Do not test writability here. Build steps are always unprivileged; install
# commands decide whether elevation is required when installation actually runs.

if [ -z "${PSPDEV:-}" ]; then
    echo "ERROR: Set \$PSPDEV before continuing."
    exit 1
fi

if [ -e "${PSPDEV}" ] && [ ! -d "${PSPDEV}" ]; then
    echo "ERROR: ${PSPDEV} exists but is not a directory."
    exit 1
fi

exit 0
