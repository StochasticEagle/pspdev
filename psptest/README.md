# PSPDEV Test Suite

This directory packages the PSPSDK and psp-packages PSPTEST modules into a single Memory Stick-ready test suite.

## Execution rule

Selection is the only gate. Every selected test is executed in manifest order. The launcher never filters tests by PSP model, firmware, peripheral availability, prior hardware validation, SDK status, or any other capability or proven-hardware flag.

If a selected EBOOT cannot be loaded, PSPDEV records a FAIL and continues with the remaining selected tests. If a test starts but does not return to the launcher, the persisted run state records that as a FAIL the next time the launcher starts, then continues the remaining selection.

Individual tests determine their result only after they run on the actual PSP.

## Building the suite

The installed PSPSDK must contain psptest.h and libpsptest.a.

    ./psptest/build-suite.sh

The output is staged under build/psptest/PSP/GAME/PSPDEV-TEST/ and archived as build/psptest/pspdev-tests.tar.gz.

## Runtime results

The launcher defaults every discovered test to selected. The menu can toggle individual tests, select all, clear the selection, and run the selection.

Each test writes its own result file and returns to the launcher. The launcher maintains:

- results/latest.log — complete aggregate run log;
- results/failures.md — issue-ready report containing build information and only failures;
- results/<scope>-<module>.log — raw result for each executed test.

The run state is persisted between EBOOTs so the launcher can continue through the complete selected set.
