#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec "${ROOT}/build-all.sh" "$@"
