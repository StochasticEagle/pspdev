TARGET = psptest-launcher
OBJS = main.o

CFLAGS = -O2 -G0 -Wall -Wextra -Werror
CXXFLAGS = $(CFLAGS) -fno-exceptions -fno-rtti
ASFLAGS = $(CFLAGS)
LIBS = -lpsptest -lpspkubridge

EXTRA_TARGETS = EBOOT.PBP
PSP_EBOOT_TITLE = PSPTEST

PSPSDK := $(shell psp-config --pspsdk-path)
PSPTEST_FRAMEWORK_INCDIR ?= $(PSPSDK)/include
PSPTEST_FRAMEWORK_LIBDIR ?= $(PSPSDK)/lib
INCDIR += $(PSPTEST_FRAMEWORK_INCDIR)
LIBDIR += $(PSPTEST_FRAMEWORK_LIBDIR)

include $(PSPSDK)/lib/build.mak
