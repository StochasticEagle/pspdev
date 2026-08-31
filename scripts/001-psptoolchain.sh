#!/bin/bash
# psptoolchain.sh by fjtrujy
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/components/psp-toolchain"

if [ ! -f "${SOURCE}/toolchain.sh" ]; then
echo "ERROR: psp-toolchain submodule is not initialized."
echo "Run: git submodule update --init --recursive --depth=1"
exit 1
fi

## Build and install.
cd "${SOURCE}"
./toolchain.sh
