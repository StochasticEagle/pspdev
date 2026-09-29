# PSPDEV PSPTEST integration

PSPSDK and psp-packages own their PSPTEST source modules. PSPDEV owns the integration build and runnable bundle.

PSPTEST is PSPDEV build stage 6:

    ./build.sh 6
    ./build.sh p 6

Stage 6 discovers every `Makefile.test` under the PSPSDK and psp-packages `psptest/` trees and builds directly from those checked-out submodule sources. It does not copy or modify those source trees.

All generated launcher, export, object, ELF, PRX, manifest, and archive output is under PSPDEV's Git-ignored `build/` directory. Stage 6 verifies that neither submodule's `psptest/` tree changes during the build.

The runnable Memory Stick tree is:

    build/PSP/GAME/psptest/

The archive is:

    build/psptest.tar.gz

Adding another module under either owning repository automatically includes it in stage 6.
