# PSPDEV PSPTEST integration

PSPDEV owns the persistent PSPTEST EBOOT, integration build, module orchestration, progress UI, watchdog, and result serialization. PSPSDK and psp-packages own their test source modules.

PSPTEST is PSPDEV build stage 6:

    ./build.sh 6
    ./build.sh p 6

## Runtime model

The EBOOT is the sole test runner. For each manifest entry it:

1. loads the test PRX;
2. passes a binary `PspTestModuleRequest` to `sceKernelStartModule()`;
3. receives a `PspTestSuite` descriptor from the PRX;
4. creates the runner-owned worker thread with the suite's requested thread attributes;
5. executes the suite through `libpsptest`;
6. renders progress and enforces the stalled-test watchdog;
7. writes the result file;
8. stops and unloads the PRX.

A test PRX contains test functions, case/suite metadata, and the minimal registration entrypoint only. Test PRXs do not link `libpsptest` and do not own PSPTEST threads, progress, files, or lifecycle orchestration.

Stage 6 builds directly from the owning PSPSDK and psp-packages source trees. It never copies test source into PSPDEV or the PSPTEST program tree. Generated objects, ELFs, PRXs, manifests, results, and archives remain under PSPDEV's ignored `build/` hierarchy.

The complete Memory Stick tree is:

    build/PSP/GAME/psptest/

and the archive is:

    build/psptest.tar.gz
