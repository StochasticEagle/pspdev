#!/bin/bash
# pspsdk.sh by fjtrujy

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/components/pspsdk"

if [ ! -f "${SOURCE}/build-and-install.sh" ]; then
	echo "ERROR: pspsdk submodule is not initialized."
	echo "Run: git submodule update --init --recursive --depth=1"
	exit 1
fi

cd "${SOURCE}"
./build-and-install.sh
