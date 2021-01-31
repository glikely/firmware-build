FW Update Qemu prototype
========================

This FW update prototype showcases the procedure, from the u-boot shell or Linux shell (after exitBootServices())
The prototype has been tested with Qemuv5.2.

The next sections describe how to reproduce the prototype and how to trigger capsule updates.

Prototype clone and build
-------------------------

repo init -u https://github.com/glikely/u-boot-manifest -m fwu_proto.xml
repo sync

# set CROSS_COMPILE
export CROSS_COMPILE=aarch64-linux-gnu-

make qemu_arm64_defconfig
make addcapsuleconfig

Start simulation
----------------

export VIRTDISK=disk.img

# The proto has been tested with qemu v5.2. see the "Build Qemu" section below for instructions to build qemu v5.2
make qemu-fip


Triggering a capsule update
===========================


U-boot shell
------------
virtio scan; load virtio 0 0x70000000 fip.capsule
efidebug tup

# request a warm reset
efidebug psci_reset

# qemu should reset in the Trial state

# explicitly accept the new images (terminate the Trial state)
efidebug ctr

Linux shell
-----------
setenv bootargs ttyAMA0,115200 earlycon=pl011,mmio32,0x9000000 debug=7 default_hugepagesz=1024m hugepagesz=1024m hugepages=2 pci=pcie_bus_perf root=/dev/vda rw fstype=ext4 init=/bin/sh
virtio scan; load virtio 0 $fdt_addr qemu_arm64.dtb; load virtio 0 0x70000000 Image; bootefi 0x70000000 $fdt_addr

# Linux boots up

mount -n -t sysfs none /sys
cat /sys/firmware/efi/esrt/entries/entry0/is_trial_state

cat fip.capsule > dev/efi_capsule_loader

reboot -f

# Qemu will reset

setenv bootargs ttyAMA0,115200 earlycon=pl011,mmio32,0x9000000 debug=7 default_hugepagesz=1024m hugepagesz=1024m hugepages=2 pci=pcie_bus_perf root=/dev/vda rw fstype=ext4 init=/bin/sh
virtio scan; load virtio 0 $fdt_addr qemu_arm64.dtb; load virtio 0 0x70000000 Image; bootefi 0x70000000 $fdt_addr

# Linux boots up

mount -n -t sysfs none /sys
cat /sys/firmware/efi/esrt/entries/entry0/is_trial_state





Auxiliar steps
==============

Clone and build Qemuv5.2
------------------------

git clone git@github.com:qemu/qemu.git

cd qemu
git checkout tags/v5.2.0

mkdir build
cd build
../configure --target-list=aarch64-softmmu
make

# Note: to use the built qemu set QEMU_BIN=$(QEMU_CHECKOUT_DIR)/build/qemu-system-aarch64


Crete Capsule disk image
------------------------

mkdir -p staging

./edk2/BaseTools/BinWrappers/PosixLike/GenerateCapsule -e -o fip.capsule --fw-version 11 --lsv 12 --guid fb90808a-ba9a-4d42-a2b9-eea41437a9a7 --verbose --update-image-index 0 --verbose trusted-firmware-a/build/qemu/release/fip.bin
cp fip.capsule staging

sudo virt-make-fs -s 20M -t ext4 staging disk.img



Create Rootfs (only required to boot Linux)
-------------------------------------------

# clone and build buildroot
git clone git@github.com:buildroot/buildroot.git
cd buildroot
make aarch64_efi_defconfig
make

mkdir staging
cp output/images/rootfs.tar staging
cd staging
tar -xvvf rootfs.tar
cd -

#copy kernel to staging and capsules

sudo virt-make-fs -s 100M -t ext4 staging disk.img
sudo chown $USER:$USER disk.img
rm -rf staging



