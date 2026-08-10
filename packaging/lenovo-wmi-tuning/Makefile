# SPDX-License-Identifier: MIT

ifneq ($(KERNELRELEASE),)
obj-m := lenovo-wmi-tuning.o
lenovo-wmi-tuning-objs := lenovo/wmi-other.o
ccflags-y := -I$(src)/include
else
KERNEL_BUILD ?= /lib/modules/$(shell uname -r)/build

.PHONY: all modules clean
all modules:
	$(MAKE) -C $(KERNEL_BUILD) M=$(CURDIR) W=1 KCFLAGS=-Werror modules

clean:
	$(MAKE) -C $(KERNEL_BUILD) M=$(CURDIR) clean
endif
