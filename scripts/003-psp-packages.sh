#!/bin/bash
# psp-packages by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/components/psp-packages"

if [ ! -d "${SOURCE}" ]; then
    echo "ERROR: psp-packages submodule is not initialized."
    echo "Run: git submodule update --init --depth=1 components/psp-packages"
    exit 1
fi

shopt -s nullglob globstar
PACKAGES=("${SOURCE}"/**/*.pkg.tar.*)
shopt -u globstar nullglob

if (( ${#PACKAGES[@]} == 0 )); then
    echo "ERROR: No locally built PSP packages were found in:"
    echo "  ${SOURCE}"
    echo "Stage 3 does not download or build packages."
    exit 1
fi

echo "Installing ${#PACKAGES[@]} locally built PSP packages..."

psp-pacman -U --noconfirm "${PACKAGES[@]}" --overwrite '*'
