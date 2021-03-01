# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) Arm Limited, 2020
#
# Build config for NXP LX2160A boards
# Inspired by https://github.com/SolidRun/lx2160a_build

RCW_PATH := $(CURDIR)/rcw
RCW_TARGET_PATH := $(RCW_PATH)/$(CONFIG_SYS_CONFIG_NAME)
TFA_PLAT := $(CONFIG_SYS_CONFIG_NAME)
TFA_EXTRA += RCW=$(RCW_TARGET_PATH)/RCW/template.bin
TFA_EXTRA += TRUSTED_BOARD_BOOT=0 GENERATE_COT=0 BOOT_MODE=auto SECURE_BOOT=false
OPTEE_EXTRA += CFG_RPMB_FS_DEV_ID=1
OPTEE_PLATFORM := ls
OPTEE_PLATFORM_FLAVOR := lx2160ardb
# In TF-A for LX2, the option for parsing header on optee is not supported.
# It expects a binary which can be loaded in memory and where execution can 
# start from.
# This option forces an objcopy which converts elf into bin and the header 
# gets removed.
USE_TEE_BIN = TRUE

FLASH_IMAGE := $(CONFIG_SYS_CONFIG_NAME)-sdcard.img

tfa/all tfa/fip: $(RCW_TARGET_PATH)/RCW/template.bin
tfa/pbl: tfa/fip

all: tfa/pbl $(FLASH_IMAGE)

LX2160A_SPEED := 2000_700_3200
LX2160A_SERDES := 8_5_2
#LX2160A_SERDES := 13_5_2
#LX2160A_SERDES := 20_5_2
DPAA2_MC := $(CURDIR)/qoriq-mc-binary/lx2160a/mc_10.20.4_lx2160a.itb
DPAA2_DPL := $(CURDIR)/mc-utils/config/lx2160a/CEX7/dpl-eth.8x10g.19.dtb
DPAA2_DPC := $(CURDIR)/mc-utils/config/lx2160a/CEX7/dpc-8_x_usxgmii.dtb

fip_ddr_all.bin: tfa/fiptool
	$(TFA_PATH)/tools/fiptool/fiptool create \
		--ddr-immem-udimm-1d ddr-phy-binary/lx2160a/ddr4_pmu_train_imem.bin \
		--ddr-immem-udimm-2d ddr-phy-binary/lx2160a/ddr4_2d_pmu_train_imem.bin \
		--ddr-dmmem-udimm-1d ddr-phy-binary/lx2160a/ddr4_pmu_train_dmem.bin \
		--ddr-dmmem-udimm-2d ddr-phy-binary/lx2160a/ddr4_2d_pmu_train_dmem.bin \
		--ddr-immem-rdimm-1d ddr-phy-binary/lx2160a/ddr4_rdimm_pmu_train_imem.bin \
		--ddr-immem-rdimm-2d ddr-phy-binary/lx2160a/ddr4_rdimm2d_pmu_train_imem.bin \
		--ddr-dmmem-rdimm-1d ddr-phy-binary/lx2160a/ddr4_rdimm_pmu_train_dmem.bin \
		--ddr-dmmem-rdimm-2d ddr-phy-binary/lx2160a/ddr4_rdimm2d_pmu_train_dmem.bin \
		fip_ddr_all.bin

$(RCW_TARGET_PATH)/RCW/template.rcw:
	mkdir -p $(RCW_TARGET_PATH)/RCW
	echo "#include <configs/lx2160a_defaults.rcwi>" > $@
	echo "#include <configs/lx2160a_$(LX2160A_SPEED).rcwi>" >> $@
	echo "#include <configs/lx2160a_$(LX2160A_SERDES).rcwi>" >> $@

$(DPAA2_DPL) $(DPAA2_DPC):
	${MAKE} -C $(CURDIR)/mc-utils/config

rcw/%: $(RCW_TARGET_PATH)/RCW/template.rcw
	${MAKE} -C ${RCW_PATH}/$(CONFIG_SYS_CONFIG_NAME) $*

$(RCW_TARGET_PATH)/RCW/template.bin: rcw/all

$(FLASH_IMAGE): tfa/pbl fip_ddr_all.bin $(DPAA2_DPL) $(DPAA2_DPC)
	dd if=/dev/zero of=$(FLASH_IMAGE) count=$$((64*1024*1024>>9))
	dd if=$(TFA_OUTPUT)/$(TFA_PLAT)/release/bl2_auto.pbl of=$(FLASH_IMAGE) bs=512 seek=8 conv=notrunc
	dd if=$(TFA_OUTPUT)/$(TFA_PLAT)/release/fip.bin of=$(FLASH_IMAGE) bs=512 seek=2048 conv=notrunc
	dd if=fip_ddr_all.bin of=$(FLASH_IMAGE) bs=512 seek=16384 conv=notrunc
	# QORIQ Data Plane Acceleration Architecture MC
	dd if=$(DPAA2_MC) of=$(FLASH_IMAGE) bs=512 seek=20480 conv=notrunc
	dd if=$(DPAA2_DPL) of=$(FLASH_IMAGE) bs=512 seek=26624 conv=notrunc
	dd if=$(DPAA2_DPC) of=$(FLASH_IMAGE) bs=512 seek=28672 conv=notrunc
