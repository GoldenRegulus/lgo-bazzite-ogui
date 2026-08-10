# SPDX-License-Identifier: GPL-2.0-or-later
KERNEL_BUILD ?= /usr/lib/modules/$(shell uname -r)/build

ccflags-y += -Werror
obj-m += hid-lenovo-go.o

.PHONY: all clean
all:
	$(MAKE) -C $(KERNEL_BUILD) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KERNEL_BUILD) M=$(CURDIR) clean
