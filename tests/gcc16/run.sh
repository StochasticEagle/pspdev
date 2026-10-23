#!/usr/bin/env bash
# GCC 16.2 / Allegrex / PSPDEV integration tests. Uses an isolated temporary dir.
set -euo pipefail

: "${PSPDEV:?PSPDEV is required}"
export PATH="$PSPDEV/bin:$PATH"
command -v psp-gcc >/dev/null
command -v psp-g++ >/dev/null
command -v psp-nm >/dev/null
command -v psp-objdump >/dev/null
test "$(psp-gcc -dumpmachine)" = "psp"
test "$(psp-gcc -dumpfullversion)" = "16.2.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"

echo "[1/8] C11/C17/C23 compilation and newlib headers"
for dialect in c11 c17 c23; do
  psp-gcc -std="$dialect" -O2 -Wall -Wextra -Werror \
    -c "$ROOT/c-standard.c" -o "c-$dialect.o"
done

echo "[2/8] Allegrex builtin instruction generation"
psp-gcc -O2 -Wall -Wextra -Werror -S "$ROOT/allegrex.c" -o allegrex.s
for instruction in bitrev clo; do
  grep -Eq "^[[:space:]]*$instruction[[:space:]]" allegrex.s || {
    echo "Expected Allegrex instruction not emitted: $instruction" >&2
    exit 1
  }
done

echo "[3/8] C++17/20/23/26 frontends"
for dialect in c++17 c++20 c++23 c++26; do
  psp-g++ -std="$dialect" -O2 -Wall -Wextra -Werror \
    -c "$ROOT/cxx-standard.cpp" -o "cxx-$dialect.o"
done

echo "[4/8] C++ runtime, exceptions, RTTI and static initialization"
for opt in O0 O2 O3 Os; do
  psp-g++ -std=c++20 "-$opt" -Wall -Wextra \
    "$ROOT/sdk-cxx.cpp" -o "sdk-cxx-$opt.elf"
  psp-nm "sdk-cxx-$opt.elf" | grep -Eq 'main|module_start|_start'
done

echo "[5/8] Compile and link with link-time optimization"
psp-g++ -std=c++20 -O2 -flto -c "$ROOT/lto.cpp" -o lto.o
psp-g++ -std=c++20 -O2 -flto "$ROOT/sdk-cxx.cpp" lto.o -o sdk-lto.elf

echo "[6/8] PSP SDK C EBOOT link"
psp-gcc -std=c11 -O2 "$ROOT/sdk-c.c" -o sdk-c.elf
psp-objdump -f sdk-c.elf | grep -q 'elf32'
psp-objdump -f sdk-cxx-O2.elf | grep -q 'elf32'

echo "[7/8] SDK PRX / relocatable module link"
PSPSDK="$(psp-config --pspsdk-path)"
test -f "$PSPSDK/lib/prxspecs"
test -f "$PSPSDK/lib/linkfile.prx"
psp-gcc -O2 -G0 -c "$ROOT/prx-module.c" -o prx-module.o
# Relocatable PRX generation requires SDK linker scripts and exports.
# Build through the standard PSPDEV PRX path rather than forcing an EBOOT ABI.
make -s -C "$ROOT/prx" \
  PSPSDK="$PSPSDK" PSPDEV="$PSPDEV" \
  WORK="$WORK" all
test -s "$WORK/gcc16-test.prx"

echo "[8/8] Verify symbol and relocation tools"
psp-nm sdk-c.elf >/dev/null
psp-objdump -r sdk-lto.elf >/dev/null
echo "All GCC 16.2 compile/link validation gates passed."
