# SPDX-License-Identifier: GPL-2.0
#
# Makefile for GC2607 V4L2 driver (out-of-tree build)
#

# Module name
obj-m := gc2607.o

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

# Help target
help:
	@echo "GC2607 V4L2 Driver Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build the gc2607.ko kernel module (default)"
	@echo "  install  - Build and install module to system (requires sudo)"
	@echo "  clean    - Remove all build artifacts"
	@echo "  help     - Show this help message"
	@echo ""
	@echo "Current kernel: $(shell uname -r)"
	@echo "Kernel headers: $(KDIR)"
	@echo ""
	@echo "Testing commands:"
	@echo "  sudo insmod gc2607.ko          - Load the driver"
	@echo "  dmesg | grep gc2607            - Check driver messages"
	@echo "  sudo rmmod gc2607              - Unload the driver"
	@echo "  lsmod | grep gc2607            - Check if module is loaded"

.PHONY: all install clean help
