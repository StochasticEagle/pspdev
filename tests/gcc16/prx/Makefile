TARGET = gcc16-test
OBJS = $(WORK)/prx-module.o
BUILD_PRX = 1
PRX_EXPORTS = $(CURDIR)/gcc16.exp
# This test supplies module_start/module_stop directly; no CRT startup.
LDFLAGS += -nostartfiles
PSPSDK ?= $(shell psp-config --pspsdk-path)
include $(PSPSDK)/lib/build.mak
