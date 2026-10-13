# ==============================================================================
# ARK-OS Components Root Makefile
# Orchestrates building runtime and bootloader components together.
# ==============================================================================

BOOT_DIR ?= boot
RUNTIME_DIR ?= runtime/arkrt

.PHONY: all runtime boot initramfs esp test test-qemu run kernel kernel-upgrade clean clean-kernel clean-all help

# Default target: build the runtime, bootloader, initramfs, and assemble the ESP boot directory
all: runtime boot esp

# Build the ARK-OS userspace init runtime (starter and arkrt-swift)
runtime:
	$(MAKE) -C $(RUNTIME_DIR)

# Build the ARK-OS UEFI bootloader (ARKBOOT.EFI) and verify the kernel
boot:
	$(MAKE) -C $(BOOT_DIR)

# Assemble the initramfs containing the PID 1 starter and Swift main runtime
initramfs: runtime
	$(MAKE) -C $(BOOT_DIR) initramfs

# Verify or download the Linux kernel binary
kernel:
	$(MAKE) -C $(BOOT_DIR) kernel

# Check for and interactively upgrade the Linux kernel from GitHub releases
kernel-upgrade:
	$(MAKE) -C $(BOOT_DIR) kernel-upgrade

# Assemble the full EFI System Partition (ESP) image with bootloader, kernel, and initramfs
esp: runtime
	$(MAKE) -C $(BOOT_DIR) esp

# Launch the end-to-end boot in QEMU with OVMF firmware
test: esp
	$(MAKE) -C $(BOOT_DIR) test

test-qemu: test

run: test

# Clean build artifacts in both runtime and boot components
clean:
	$(MAKE) -C $(RUNTIME_DIR) clean
	$(MAKE) -C $(BOOT_DIR) clean

# Remove cached kernel binaries
clean-kernel:
	$(MAKE) -C $(BOOT_DIR) clean-kernel

# Deep clean including kernel cache
clean-all: clean clean-kernel

help:
	@echo "ARK-OS Components Build Targets:"
	@echo "  all            - Build runtime, bootloader, initramfs, and assemble ESP (default)"
	@echo "  runtime        - Build C PID 1 starter and Swift main runtime in $(RUNTIME_DIR)"
	@echo "  boot           - Build UEFI bootloader (ARKBOOT.EFI) in $(BOOT_DIR)"
	@echo "  initramfs      - Build initramfs.cpio staging runtime binaries and dependencies"
	@echo "  kernel         - Verify and download kernel if needed"
	@echo "  kernel-upgrade - Check for kernel updates and prompt to upgrade"
	@echo "  esp            - Build all components and stage to $(BOOT_DIR)/build/esp"
	@echo "  test / run     - Build ESP and launch QEMU/OVMF virtual machine"
	@echo "  clean          - Clean build artifacts in runtime and boot"
	@echo "  clean-all      - Clean all build artifacts including kernel cache"
