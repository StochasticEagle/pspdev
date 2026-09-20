<div align="center">

# PSPDEV

[![CI](https://img.shields.io/github/actions/workflow/status/StochasticEagle/pspdev/.github/workflows/compilation.yml?branch=dev%2Ffork&style=for-the-badge&logo=github&label=CI)](https://github.com/StochasticEagle/pspdev/actions/workflows/compilation.yml)

Main PSP Repo for building the whole `PSP Development` environment in your local machine.

This program will automatically build and install the whole compiler and other tools used in the creation of Homebrew software for the Sony PlayStation Portable® video game system.

</div>

## Table of Contents

- [PSPDEV](#pspdev)
  - [Table of Contents](#table-of-contents)
  - [Up and running](#up-and-running)
  - [What these scripts do](#what-these-scripts-do)
  - [Requirements](#requirements)
  - [Installation from source](#installation-from-source)
  - [Extra steps](#extra-steps)
    - [macOS](#macos)
    - [Local package builds](#local-package-builds)
  - [Thanks](#thanks)

## Up and running

Tagged builds are published on the [releases page](https://github.com/StochasticEagle/pspdev/releases). Development builds are available as artifacts from this fork's GitHub Actions runs.

Export the `PSPDEV` environment variable to point to the `pspdev` directory. For example:

```bash
export PSPDEV=~/pspdev
export PATH=$PATH:$PSPDEV/bin
```

## What these scripts do

These scripts download (`git clone`) and install:

- [psptoolchain](https://github.com/StochasticEagle/psp-toolchain "psp-toolchain")
- [pspsdk](https://github.com/StochasticEagle/pspsdk "pspsdk")
- [psp-packages](https://github.com/StochasticEagle/psp-packages "psp-packages")
- [psplinkusb](https://github.com/StochasticEagle/psp-linkusb "psplinkusb")
- [ebootsigner](https://github.com/StochasticEagle/psp-ebootsigner "psp-ebootsigner")

## Requirements

- Install
 `gcc/clang`, `make`, `cmake`, `patch`, `git`, `texinfo`, `flex`, `bison`, `gettext`, `wget`, `gsl`, `gmp`, `mpfr`, `mpc`, `libusb`, `readline`, `libarchive`, `gpgme`, `bash`, `openssl` and `libtool`.
- If you don't have those.
We offer a script to help you for installing dependencies:

```bash
sudo ./prepare.sh
```

> [!NOTE]
> This script will automatically detect your operating system.

## Installation from source

1. Ensure that you have enough permissions for managing PSPDEV location (default to `/usr/local/pspdev`, but you can use a different path). PSPDEV location MUST NOT have spaces or special characters in its path! PSPDEV should be an absolute path. On Unix systems, if the command `mkdir -p $PSPDEV` fails for you, you can set access for the current user by running commands:
    ```bash
    export PSPDEV=/usr/local/pspdev
    sudo mkdir -p $PSPDEV
    sudo chown -R $USER: $PSPDEV
    ```

2. Add this to your login script (example: `~/.bash_profile`)
    ```bash
    export PSPDEV=/usr/local/pspdev
    export PATH=$PATH:$PSPDEV/bin
    ```

    **NOTE**: Ensure that you have full access to the PSPDEV path. You can change the PSPDEV path with the following requirements: `Only use absolute paths`, `Do not use spaces.`, `Only use Latin characters`.


3. Run build-all.sh
    ```bash
    ./build-all.sh
    ```

Normal builds are incremental and preserve existing build trees. To force a fresh
package/SDK/host-tool build without deleting the installed PSPDEV prefix, run:

```bash
./clean-all.sh
./build-all.sh
```

> [!TIP]
> If you are upgrading from the previous version of the PSPDEV environment, it is highly recommended removing the content of the PSPDEV folder before upgrade. This is a     necessary step after the major toolchain upgrade.
> ```bash
> sudo rm -rf $PSPDEV
> ```

## Extra steps

The extra components are stages 4 and 5 of `build-all.sh`. To build only `psplinkusb` and `ebootsigner`, run:

```bash
./build-all.sh 4 5
```

### macOS

If you download the pre-built macOS binaries and get a security error such as _`"pspsh" cannot be opened because the developer cannot be verified.`_, you can remove the quarantine attribute by running:

```bash
xattr -dr com.apple.quarantine path/to/prebuilt/pspdev
```

### Local package builds

The toolchain (binutils, gcc), the SDK (pspsdk) and the host tools are built locally. Published packages are served from this fork's [psp-packages repository](https://stochasticeagle.github.io/psp-packages/). If you wish to build these packages locally, define _LOCAL_PACKAGE_BUILD_ to force packages to build from source instead of downloading them:

```bash
LOCAL_PACKAGE_BUILD=1 ./build-all.sh
```

This is particularly useful if you are testing changes in the toolchain (i.e. gcc or binutils) and want to test your changes end to end. It can also be useful if you want a hermetic build and don't want to use any of the provided binaries.

## Thanks

*Special thanks to all the contributors and maintainers whose efforts and commitment drive the continuous improvement of this project.*
