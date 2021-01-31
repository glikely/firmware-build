# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) Arm Limited, 2020
#
# Makefile Conventions:
# Variable names:
# *_PATH:   Full path to project source directories or other assets
# *_OUTPUT: Build directories for each of the sub projects
# *_EXTRA:  Extra parameters to the make call. Gets added to make targets, e.g.
#           "$(MAKE) -C ${PROJECT_PATH} ... ${PROJECT_EXTRA} ..."

SHELL := /bin/bash

# Set some defaults that can be overridden by the target  makefile include
DT_PATH    := $(CURDIR)/devicetree-rebasing
DT_OUTPUT  := $(DT_PATH)
EDK2_PATH  := $(CURDIR)/edk2
EDK2_PLATFORMS_PATH := $(CURDIR)/edk2-platforms
OPTEE_PATH := $(CURDIR)/optee_os
TFA_PATH   := $(CURDIR)/trusted-firmware-a
UBOOT_PATH := $(CURDIR)/u-boot

# Give the option of building in a separate directory
ifneq ($(BUILD_OUTPUT),)
  __BUILD := $(realpath $(BUILD_OUTPUT))
  EDK2_OUTPUT := $(__BUILD)/Build
  OPTEE_OUTPUT := $(__BUILD)/optee_os
  OPTEE_EXTRA += O=$(OPTEE_OUTPUT)
  TFA_OUTPUT := $(__BUILD)/tfa
  TFA_EXTRA += BUILD_BASE=$(TFA_OUTPUT)
  UBOOT_OUTPUT := $(__BUILD)/u-boot
  UBOOT_EXTRA += KBUILD_OUTPUT=$(UBOOT_OUTPUT)
else
  EDK2_OUTPUT := $(CURDIR)/Build
  OPTEE_OUTPUT := $(OPTEE_PATH)/out
  TFA_OUTPUT := $(TFA_PATH)/build
  UBOOT_OUTPUT := $(UBOOT_PATH)
endif

# Default target when none provided on command line
all: flashimage

help:
	@echo  'Cleaning targets:'
	@echo  '  clean		  - Remove most generated files but keep the config'
	@echo  '  mrproper	  - Remove all generated files + config + various backup files'
	@echo  ''
	@echo  'Configuration targets:'
	@$(MAKE) -C $(UBOOT_PATH) -f $(UBOOT_PATH)/scripts/kconfig/Makefile --no-print-directory help
	@echo  ''
	@echo  '  Only a subset of U-Boot defconfigs will work with this tool. For this tool'
	@echo  '  to work, $$TFA_PLAT needs to be set. See scripts/*.mk for examples. Adding'
	@echo  '  support for a new platform requires inspecting the U-Boot configuration and'
	@echo  '  choosing the correct $$TFA_PLAT value.'
	@echo  ''
	@echo  'Project targets:'
	@echo  ''
	@echo  '  u-boot/<name>		  - Build U-Boot target <name>'
	@echo  '  tfa/<name>		  - Build Trusted Firmware target <name> *'
	@echo  '  devicetree/<name>	  - Build Devicetree target <name> *'
	@echo  '    * Can only be called if U-Boot is configured'
	@echo  ''
	@echo  'Emulation targets (if available for given u-boot configuration:'
	@echo  ''
	@echo  '  qemu-fip:		  - Boot in QEMU using FIP image as -bios'
	@echo  '  qemu-semihosting:	  - Boot in QEMU with semihosting'
	@echo  ''
	@echo  '  QEMU configuration can be manipulated with environmental variables:'
	@echo  '  VIRTDISK	Path to a raw disk image. Could be an ISO, or a GPT or MBR'
	@echo  '		partitioned disk image. The image will be passed to QEMU as a'
	@echo  '		virtio block device'
	@echo  '  QEMU_EXTRA	List of extra command line options passed to QEMU'
	@echo  ''
	@echo  'Other targets:'
	@echo  ''
	@echo  '  help		  - This help text'
	@echo  '  info		  - Display details about the build configuration'

# ===========================================================================
# Rules shared between *config targets and build targets

# To make sure we do not include .config for any of the *config targets
# catch them early
# It is allowed to specify more targets when calling make, including
# mixing *config targets and build targets.
# For example 'make oldconfig all'.
# Detect when mixed targets is specified, and make a second invocation
# of make so .config is not included in this case either (for *config).

no-dot-config-targets := clean mrproper distclean u-boot/%clean u-boot/mrproper u-boot/%config tfa/%clean devicetree/clean help

config-targets := 0
mixed-targets  := 0
dot-config     := 1

ifneq ($(filter $(no-dot-config-targets), $(MAKECMDGOALS)),)
	ifeq ($(filter-out $(no-dot-config-targets), $(MAKECMDGOALS)),)
		dot-config := 0
	endif
endif

ifneq ($(filter %config,$(MAKECMDGOALS)),)
        config-targets := 1
        ifneq ($(words $(MAKECMDGOALS)),1)
                mixed-targets := 1
        endif
endif

ifeq ($(mixed-targets),1)
# ===========================================================================
# We're called with mixed targets (*config and build targets).
# Handle them one by one.
PHONY += $(MAKECMDGOALS) __build_one_by_one

$(filter-out __build_one_by_one, $(MAKECMDGOALS)): __build_one_by_one
	@:

__build_one_by_one:
	$(Q)set -e; \
	for i in $(MAKECMDGOALS); do \
		$(MAKE) $$i; \
	done

else
ifeq ($(config-targets),1)
# ===========================================================================
# *config targets only - make sure prerequisites are updated, and descend
# in scripts/kconfig to make the *config target

addcapsuleconfig:
	$(UBOOT_PATH)/scripts/kconfig/merge_config.sh -m -O $(UBOOT_OUTPUT) $(UBOOT_OUTPUT)/.config scripts/capsule.config
	$(MAKE) -C $(UBOOT_PATH) $(UBOOT_EXTRA) olddefconfig

addstmmconfig:
	$(UBOOT_PATH)/scripts/kconfig/merge_config.sh -m -O $(UBOOT_OUTPUT) $(UBOOT_OUTPUT)/.config scripts/stmm.config
	$(MAKE) -C $(UBOOT_PATH) $(UBOOT_EXTRA) olddefconfig

ebbrconfig:
	$(UBOOT_PATH)/scripts/kconfig/merge_config.sh -m -O $(UBOOT_OUTPUT) $(UBOOT_OUTPUT)/.config scripts/ebbr.config
	$(MAKE) -C $(UBOOT_PATH) $(UBOOT_EXTRA) olddefconfig

%config: u-boot/%config;

PHONY += defconfig
defconfig: rockpro64-rk3399_defconfig ;

else
# ===========================================================================
# Build targets only
# In general all targets that make use of the selected configuration

ifeq ($(dot-config),1)
# Read in config
-include $(UBOOT_OUTPUT)/.config

# ===================================
# Platform/SOC specific configuration
#
# Try including platform specific configs
# Platform specific config could be SOC, Vendor, or config

INCLUDE_MK := scripts/cpu-$(subst ",,$(CONFIG_SYS_CPU)).mk
INCLUDE_MK += scripts/vendor-$(subst ",,$(CONFIG_SYS_VENDOR)).mk
INCLUDE_MK += scripts/soc-$(subst ",,$(CONFIG_SYS_SOC)).mk
INCLUDE_MK += scripts/board-$(subst ",,$(CONFIG_SYS_BOARD)).mk
INCLUDE_MK += scripts/config-$(subst ",,$(CONFIG_SYS_CONFIG_NAME)).mk
include $(wildcard $(INCLUDE_MK))

ifeq ($(MAKECMDGOALS),info)
info:
	@echo 'U-Boot Config:'
	@echo '  CONFIG_SYS_CPU=$(subst ",,$(CONFIG_SYS_CPU))'
	@echo '  CONFIG_SYS_VENDOR=$(subst ",,$(CONFIG_SYS_VENDOR))'
	@echo '  CONFIG_SYS_SOC=$(subst ",,$(CONFIG_SYS_SOC))'
	@echo '  CONFIG_SYS_BOARD=$(subst ",,$(CONFIG_SYS_BOARD))'
	@echo '  CONFIG_SYS_CONFIG_NAME=$(subst ",,$(CONFIG_SYS_CONFIG_NAME))'
	@echo '  CONFIG_OPTEE=$(subst ",,$(CONFIG_OPTEE))'
	@echo '  CONFIG_EFI_MM_COMM_TEE=$(subst ",,$(CONFIG_EFI_MM_COMM_TEE))'
	@echo 'Derived Config:'
	@echo '  TFA_PLAT=$(TFA_PLAT)'
	@echo '  FLASH_IMAGE=$(FLASH_IMAGE)'
	@echo 'Included platform configuration files:'
	@$(foreach inc, $(wildcard $(INCLUDE_MK)), echo '  $(inc)';)
else
ifeq ($(TFA_PLAT),)
  $(info $$TFA_PLAT is not set. Either U-Boot is not configured, the platform is not)
  $(info yet supported, or there is a bug. Use \'make info\' to see the current)
  $(info configuration)
  $(info )
  $(error Invalid configuration)
endif
ifeq ($(CONFIG_OPTEE)$(OPTEE_PLATFORM),y)
  $(info OPTEE is enabled, but $$OPTEE_PLATFORM is not set. Either the platform is not)
  $(info yet supported, or there is a bug. Use \'make info\' to see the current)
  $(info configuration)
  $(info )
  $(error Invalid configuration)
endif
endif

ifeq ($(CONFIG_OPTEE),y)
# ----------------------------------------------------------------------
# Standalone-MM build configuration
#ifeq ($(CONFIG_EFI_MM_COMM_TEE),y)

# EDK2 Environmental variables; easiest to export these
export WORKSPACE=$(CURDIR)
export PACKAGES_PATH=$(EDK2_PATH):$(EDK2_PLATFORMS_PATH)
export GCC5_AARCH64_PREFIX=$(CROSS_COMPILE)
export ACTIVE_PLATFORM ?= Platform/StMMRpmb/PlatformStandaloneMm.dsc

STMM_FD := $(EDK2_OUTPUT)/MmStandaloneRpmb/DEBUG_GCC5/FV/BL32_AP_MM.fd

PHONY += edk2-basetools edk2-stmm
edk2-basetools:
	source $(EDK2_PATH)/edksetup.sh && $(MAKE) -C $(EDK2_PATH)/BaseTools

edk2-stmm: edk2-basetools
	source $(EDK2_PATH)/edksetup.sh && build -p $(ACTIVE_PLATFORM) -b DEBUG -a AARCH64 -t GCC5 -D DO_X86EMU=TRUE \
 -D MM_SECURE_STORAGE_ENABLE=TRUE -DUART_ENABLE=TRUE

# Tell optee where to find StMM and add it as a dependency
OPTEE_EXTRA += CFG_STMM_PATH=$(STMM_FD)
optee_os/all: edk2-stmm

#endif # ifeq($(CONFIG_EFI_MM_COMM_TEE),y)

# ----------------------------------------------------------------------
# OP-TEE build configuration
OPTEE_EXTRA += ARCH=arm
OPTEE_EXTRA += CROSS_COMPILE32=arm-linux-gnueabihf-
OPTEE_EXTRA += PLATFORM=$(OPTEE_PLATFORM)
OPTEE_EXTRA += CFG_ARM64_core=y
OPTEE_EXTRA += CFG_RPMB_FS=y
OPTEE_EXTRA += CFG_RPMB_WRITE_KEY=1
OPTEE_EXTRA += CFG_CORE_HEAP_SIZE=524288
OPTEE_EXTRA += CFG_TEE_CORE_LOG_LEVEL=3
OPTEE_EXTRA += CFG_CORE_ASLR=n
OPTEE_EXTRA += CFG_TA_ASLR=n
OPTEE_EXTRA += CFG_WITH_STMM_SP=y

# Tell TFA where to find the OP-TEE binaries
TFA_EXTRA += BL32=$(OPTEE_OUTPUT)/arm-plat-vexpress/core/tee-header_v2.bin
TFA_EXTRA += BL32_EXTRA1=$(OPTEE_OUTPUT)/arm-plat-vexpress/core/tee-pager_v2.bin
TFA_EXTRA += BL32_EXTRA2=$(OPTEE_OUTPUT)/arm-plat-vexpress/core/tee-pageable_v2.bin
TFA_EXTRA += BL32_RAM_LOCATION=tdram
TFA_EXTRA += SPD=opteed

FIP_DEPS += optee_os/all

endif # ifeq($(CONFIG_OPTEE),y)

# Default Trusted Firmware configuration settings
TFA_EXTRA += PLAT=$(TFA_PLAT)
TFA_EXTRA += LOG_LEVEL=20
TFA_EXTRA += BL33=$(UBOOT_OUTPUT)/u-boot.bin

FLASH_IMAGE ?= $(TFA_OUTPUT)/$(TFA_PLAT)/release/flash-image.bin
SD_IMAGE := $(subst ",,$(CONFIG_SYS_CONFIG_NAME))-sdcard.img
ESP_SIZE ?= $$((64*1024*1024))
ESP_OFFSET ?= $$((4*1024*1024))

# Choose who provides BL2. If CONFIG_SPL is enabled, then U-Boot is acting as
# BL2. Otherwise TF-A BL2 will be used. Set up the dependencies for the
# selected approach
# FIP_DEPS are the targets requried to create the FIP or FIT
ifeq ($(CONFIG_SPL),y)
u-boot/all: $(FIP_DEPS) tfa/bl31		# U-Boot SPL BL2
FLASH_IMAGE_DEPS := u-boot/all
else
tfa/fip: $(FIP_DEPS) u-boot/all tfa/all		# TF-A BL2
FLASH_IMAGE_DEPS := tfa/fip
endif # ifeq($(CONFIG_SPL),y)

endif # ifeq ($(dot-config),1)

ifneq ($(DTB_TARGET),)
PHONY += dtb
dtb: ${DTB_TARGET}
	fdtput ${DT_OUTPUT}/${DTB_TARGET} -t s / u-boot-ver `cd ${UBOOT_PATH} && git describe`
	fdtput ${DT_OUTPUT}/${DTB_TARGET} -t s / tfa-ver `cd ${TFA_PATH} && git describe`
	fdtput ${DT_OUTPUT}/${DTB_TARGET} -t s / dt-ver `cd ${DT_PATH} && git describe`
endif

PHONY += flashimage sdimage

flashimage ${FLASH_IMAGE}: ${FLASH_IMAGE_DEPS}

sdimage: flashimage

PHONY += clean mrproper distclean
clean: u-boot/clean tfa/distclean devicetree/clean optee_os/clean edk2-clean
mrproper: u-boot/mrproper tfa/distclean devicetree/clean optee_os/clean
distclean: u-boot/distclean tfa/distclean devicetree/clean optee_os/clean

# ===========================================================================
# Common targets - Mostly delegates to the individual project build systems

# ================================================
# Delegate to devicetree-rebasing build
#
devicetree/%:
	${MAKE} -C ${DT_PATH} $*

# ================================================
# EDK2 Targets
PHONY += edk2-clean
edk2-clean:
	rm -rf $(EDK2_OUTPUT)

# ================================================
# Delegate optee targets to optee Makefile
optee_os/%:
	${MAKE} -C ${OPTEE_PATH} ${OPTEE_EXTRA} $*

# ================================================
# Delegate to trusted-firmware-a build
tfa/%:
	${MAKE} -C ${TFA_PATH} ${TFA_EXTRA} $*

endif #ifeq,else ($(config-targets),1)

# ================================================
# Delegate to u-boot build
# 	(This target is outside the $(config-targets) 'else'
# 	clause so that u-boot/%config targets can use it)
u-boot/%:
	$(MAKE) -C $(UBOOT_PATH) $(UBOOT_EXTRA) $*

endif #ifeq ($(mixed-targets),1)

# Declare the contents of the PHONY variable as phony.  We keep that
# information in a variable so we can use it in if_changed and friends.
.PHONY: $(PHONY)
