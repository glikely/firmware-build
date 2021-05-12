# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) Arm Limited, 2021

TFA_PLAT := imx8mm
OPTEE_PLATFORM := imx

OPTEE_EXTRA += PLATFORM_FLAVOR=mx8mmevk

FLASH_IMAGE := out_flash_imx8mm.bin

DDR_FW :=  firmware-imx-8.9


$(DDR_FW): $(DDR_FW).bin
#
# XXX: we need to check if $(DDR_FW) exists because after ./$(DDR_FW).bin the
# directory timestamp will be lower than its dependency ($(DDR_FW).bin)
#
ifeq (,$(wildcard ./$(DDR_FW) ))
	$(error Please execute $(DDR_FW).bin and accept the EULA)
endif

$(DDR_FW).bin:
	wget https://www.nxp.com/lgfiles/NMG/MAD/YOCTO/$(DDR_FW).bin
	chmod +x $(DDR_FW).bin

$(FLASH_IMAGE): tfa/all  ${FLASH_IMAGE_DEPS} | $(DDR_FW)
	cp u-boot/tools/mkimage imx-mkimage/iMX8M/mkimage_uboot
	cp u-boot/spl/u-boot-spl.bin  imx-mkimage/iMX8M/
	cp u-boot/u-boot-nodtb.bin  imx-mkimage/iMX8M/
	cp u-boot/dts/dt.dtb imx-mkimage/iMX8M/imx8mm-evk.dtb
	cp $(DDR_FW)/firmware/ddr/synopsys/lpddr4_pmu_train_* imx-mkimage/iMX8M/
	aarch64-linux-gnu-objcopy -v -O binary optee_os/out/arm-plat-imx/core/tee.elf imx-mkimage/iMX8M//tee.bin
	cp trusted-firmware-a/build/imx8mm/release/bl31.bin imx-mkimage/iMX8M/
	cd imx-mkimage && make SOC=iMX8MM flash_spl_uboot
	dd if=imx-mkimage/iMX8M/flash.bin of=$(FLASH_IMAGE) bs=1024 seek=33 conv=notrunc
