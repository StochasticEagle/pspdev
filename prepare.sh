#!/bin/bash

set -e

echo "Detecting OS and installing packages required for PSP SDK"

## Handle macOS first.

if [ "$(uname -s)" = "Darwin" ]; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "ERROR: Homebrew is required on macOS."
        exit 1
    fi

    brew install \
        gettext texinfo bison \
        flex gnu-sed ncurses \
        gsl gmp mpfr \
        autoconf automake cmake \
        libusb libarchive gpgme \
        bash openssl libtool \
        zlib libmpc meson ninja \
        pkgconf

    exit 0
fi

## Package managers below require root.
if [ "${EUID}" -ne 0 ]; then
    echo "Elevating to root so packages can be installed"
    exec sudo "$0" "$@"
fi

if [ ! -r /etc/os-release ]; then
    echo "ERROR: Unable to determine Linux distribution."
    exit 1
fi

. /etc/os-release
TESTOS="${ID:-unknown}"

case "${TESTOS}" in

ubuntu | linuxmint | debian | pop)
    apt-get -y --no-install-recommends install \
        gcc g++ make git patch file \
        autoconf automake cmake \
        texinfo bison flex gettext \
        pkg-config libtool \
        libgmp-dev libmpfr-dev libmpc-dev \
        libusb-1.0-0-dev libreadline-dev \
        libcurl4-openssl-dev libssl-dev \
        libarchive-dev libgpgme-dev \
        libncurses-dev libgsl-dev \
        zlib1g-dev wget \
        meson ninja-build
    ;;

rhel | fedora)
    dnf -y install \
        @development-tools \
        gcc gcc-c++ \
        git patch wget file \
        autoconf automake make cmake \
        pkgconf libtool \
        gettext texinfo bison flex \
        gmp-devel mpfr-devel libmpc-devel \
        ncurses-devel gsl-devel \
        libusb1-devel readline-devel \
        libcurl-devel libarchive-devel \
        openssl-devel gpgme-devel \
        diffutils gawk xz \
        meson ninja-build
    ;;

gentoo)
    emerge --noreplace \
        net-misc/wget \
        dev-vcs/git \
        sys-apps/fakeroot \
        app-arch/libarchive \
        app-crypt/gpgme \
        sys-devel/bison \
        sys-devel/flex \
        dev-libs/mpc \
        dev-libs/libusb \
        dev-build/ninja \
        dev-build/meson
    ;;

arch | manjaro | endeavouros | cachyos)
    pacman -S --needed \
        gcc clang make cmake patch git \
        texinfo flex bison gettext wget \
        gsl gmp mpfr libmpc \
        libusb readline libarchive gpgme \
        bash openssl libtool boost \
        pkgconf meson ninja
    ;;

opensuse*)
    zypper install -y \
        --no-recommends \
        --auto-agree-with-licenses \
        gcc gcc-c++ clang binutils \
        git patch make cmake \
        autoconf automake libtool \
        texinfo bison flex gettext \
        pkg-config \
        gpgme libgpgme-devel \
        libarchive-devel \
        openssl libopenssl-devel \
        ncurses ncurses-devel \
        gmp-devel mpfr-devel mpc-devel \
        meson ninja
    ;;

*)
    echo "ERROR: ${TESTOS} is not supported."
    exit 1
    ;;

esac
