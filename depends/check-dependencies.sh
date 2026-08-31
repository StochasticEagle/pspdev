#!/bin/bash

missing_depends=()

function check_library
{
if pkg-config --exists "$1"; then
return 0
fi

missing_depends+=("$1")
return 1

}

function check_program
{
if command -v "$1" >/dev/null 2>&1; then
return 0
fi

missing_depends+=("$1")
return 1

}

check_program git
check_program patch
check_program autoconf
check_program automake
check_program make
check_program cmake
check_program gcc
check_program g++
check_program bison
check_program flex
check_program meson
check_program ninja
check_program gpgme-tool
check_program pkg-config

# macOS uses it's own fork of libtool
if [ "$(uname)" != "Darwin" ]; then
    check_program libtoolize
else
    check_program glibtoolize
fi

if command -v pkg-config >/dev/null 2>&1; then
    check_library libarchive
    check_library openssl
    check_library ncurses
fi

if [ ${#missing_depends[@]} -ne 0 ]; then
    echo "Couldn't find dependencies:"
    for dep in "${missing_depends[@]}"; do
        echo " - $dep"
    done
    exit 1
fi
