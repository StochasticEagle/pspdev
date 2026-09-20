#!/bin/bash

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Cleaning PSPDEV build artifacts..."

PACMAN="${ROOT}/components/psp-toolchain/components/psp-pacman"
if [[ -x "${PACMAN}/clean.sh" ]]; then
    "${PACMAN}/clean.sh"
fi

PSPSDK="${ROOT}/components/pspsdk"
if [[ -x "${PSPSDK}/clean.sh" ]]; then
    "${PSPSDK}/clean.sh"
fi

PACKAGES="${ROOT}/components/psp-packages"
if [[ -x "${PACKAGES}/build.sh" ]]; then
    "${PACKAGES}/build.sh" --clean
fi

PSPLINK="${ROOT}/components/psp-linkusb"
if [[ -f "${PSPLINK}/Makefile" ]]; then
    make -C "${PSPLINK}" clean
fi

EBOOTSIGNER="${ROOT}/components/psp-ebootsigner"
if [[ -f "${EBOOTSIGNER}/Makefile" ]]; then
    make -C "${EBOOTSIGNER}" clean
fi

echo "Build artifacts cleaned. The PSPDEV install prefix was not modified."
