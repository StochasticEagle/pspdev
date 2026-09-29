# PSPDEV PSPTEST integration

PSPSDK and psp-packages own their PSPTEST source modules. PSPDEV owns the integration build and runnable bundle.

PSPTEST is PSPDEV build stage 6:

    ./build.sh 6
    ./build.sh p 6

Stage 6 discovers every `Makefile.test` under the PSPSDK and psp-packages `psptest/` trees and builds directly from those checked-out submodule sources. It does not copy or modify those source trees.

All generated launcher, framework, export, object, ELF, PRX, manifest, result-directory, and archive output is under PSPDEV's Git-ignored `build/` directory. Stage 6 verifies that the PSPSDK PSPTEST framework/test sources and the psp-packages PSPTEST sources are unchanged by the build.

The PSPTEST program is built as a complete Memory Stick tree at:

    build/PSP/GAME/psptest/

The same program tree is archived as:

    build/psptest.tar.gz

Adding another module under either owning repository automatically includes it in stage 6.
