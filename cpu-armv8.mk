ifeq ($(CROSS_COMPILE),)
  export CROSS_COMPILE=aarch64-linux-gnu-
endif
LINUX_ARCH=arm64
