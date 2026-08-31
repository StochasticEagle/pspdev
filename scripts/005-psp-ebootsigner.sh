#!/bin/bash
# ebootsigner by fjtrujy

## Download the source code.
REPO_URL="https://github.com/StochasticEagle/psp-ebootsigner"
REPO_FOLDER="psp-ebootsigner"
BRANCH_NAME="master"
if test ! -d "$REPO_FOLDER"; then
	git clone --depth 1 -b $BRANCH_NAME $REPO_URL && cd $REPO_FOLDER || { exit 1; }
else
	cd $REPO_FOLDER && git fetch origin && git reset --hard origin/${BRANCH_NAME} || { exit 1; }
fi

## Determine the maximum number of processes that Make can work with.
PROC_NR=$(getconf _NPROCESSORS_ONLN)

## Compile and install.
make --quiet -j $PROC_NR clean          || { exit 1; }
make --quiet -j $PROC_NR all            || { exit 1; }
make --quiet -j $PROC_NR install        || { exit 1; }
make --quiet -j $PROC_NR clean          || { exit 1; }

## Store build information
BUILD_FILE="${PSPDEV}/build.txt"
if [[ -f "${BUILD_FILE}" ]]; then
  sed -i'' '/^psp-ebootsigner /d' "${BUILD_FILE}"
fi
git log -1 --format="psp-ebootsigner %H %cs %s" >> "${BUILD_FILE}"
