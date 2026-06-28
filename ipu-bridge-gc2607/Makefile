# SPDX-License-Identifier: GPL-2.0-only
#
# Makefile for the Intel IPU bridge with the GC2607 (HUAWEI MateBook X
# VGHH-XX) upside-down-mount DMI quirk (out-of-tree build).
#

# Module name
obj-m := ipu-bridge.o

# Kernel headers directory (auto-detect running kernel)
KDIR ?= /lib/modules/$(shell uname -r)/build

# Build directory
PWD := $(shell pwd)

# Match the kernel's toolchain: clang-built kernels need LLVM=1 for external
# modules, gcc-built kernels must not set it. Detect from the kernel config so a
# plain `make` works on either. (DKMS builds go through dkms.conf, which does
# the same detection.)
CC_IS_CLANG := $(shell grep -hqs '^CONFIG_CC_IS_CLANG=y' \
	$(KDIR)/.config $(KDIR)/include/config/auto.conf && echo y)
ifeq ($(CC_IS_CLANG),y)
  KBUILD_ARGS := LLVM=1
endif

# Default target: build the module
all:
	$(MAKE) -C $(KDIR) M=$(PWD) $(KBUILD_ARGS) modules

# Install module to system
install: all
	$(MAKE) -C $(KDIR) M=$(PWD) $(KBUILD_ARGS) modules_install
	depmod -a

# Clean build artifacts
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) $(KBUILD_ARGS) clean
	rm -f Module.symvers modules.order

.PHONY: all install clean
