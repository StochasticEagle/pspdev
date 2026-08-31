#!/bin/sh
# check-pspdev.sh by Naomi Peori (naomi@peori.ca)

## Check if $PSPDEV is set.
if [ -z "${PSPDEV:-}" ]; then
    echo "ERROR: Set \$PSPDEV before continuing."
    exit 1
fi

## Check for the $PSPDEV directory.
ls -ld "${PSPDEV}" >/dev/null 2>&1 ||
mkdir -p "${PSPDEV}" >/dev/null 2>&1 ||
{
    echo "ERROR: Create ${PSPDEV} before continuing."
    exit 1
}

## Check for write permission.
touch "${PSPDEV}/.pspdev-write-test" >/dev/null 2>&1 ||
{
    echo "ERROR: Grant write permissions for ${PSPDEV} before continuing."
    exit 1
}

rm -f "${PSPDEV}/.pspdev-write-test"

