CC ?= gcc
LD ?= ld
OBJCOPY ?= objcopy

BUILD_DIR ?= build
LOADER_DIR ?= loader
INCLUDE_DIR ?= include
KERNEL_DIR ?= $(BUILD_DIR)/kernel
SYSROOT_DIR ?= $(BUILD_DIR)/sysroot
SYNC_SCRIPT ?= scripts/sync.sh
KERNEL_SCRIPT ?= $(SYNC_SCRIPT)
KERNEL_IMAGE ?= $(KERNEL_DIR)/boot/bzImage

CFLAGS = -O2 -fpic -ffreestanding -fno-stack-protector -fno-stack-check \
         -fshort-wchar -mno-red-zone -mno-sse -mno-mmx \
         -Wall -Wextra -Werror \
         -DHAVE_USE_MS_ABI \
         -I/usr/include/efi -I/usr/include/efi/x86_64 -I$(INCLUDE_DIR)

LDFLAGS = -nostdlib -znocombreloc -T /usr/lib/elf_x86_64_efi.lds -shared -Bsymbolic \
          -L /usr/lib /usr/lib/crt0-efi-x86_64.o

LIBS = -lgnuefi -lefi

OBJCOPY_FLAGS = -j .text -j .sdata -j .data -j .dynamic -j .dynsym \
                -j .rel -j .rela -j .reloc -j .rodata \
                -O efi-app-x86_64

OBJS = $(BUILD_DIR)/main.o \
       $(BUILD_DIR)/graphics.o \
       $(BUILD_DIR)/serial.o \
       $(BUILD_DIR)/fs.o \
       $(BUILD_DIR)/linux.o

TARGET = ARKBOOT.EFI

.PHONY: all clean clean-kernel clean-sysroot esp test test-qemu run initramfs initramfs-target validate-initramfs-target esp-target kernel kernel-upgrade sysbuilts sysbuilts-upgrade sync

all: $(TARGET) kernel

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.o: $(LOADER_DIR)/%.c $(INCLUDE_DIR)/ark_boot.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/arkboot.so: $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $@ $(LIBS)

$(TARGET): $(BUILD_DIR)/arkboot.so
	$(OBJCOPY) $(OBJCOPY_FLAGS) $< $@

RUNTIME_DIR ?= ../runtime/arkrt
SERVICES_DIR ?= ../services/arkdiag

$(RUNTIME_DIR)/starter:
	$(MAKE) -C $(RUNTIME_DIR)

$(SERVICES_DIR)/arkdiag:
	$(MAKE) -C $(SERVICES_DIR)

initramfs: $(BUILD_DIR)/initramfs.cpio

$(BUILD_DIR)/initramfs.cpio: $(RUNTIME_DIR)/starter $(SERVICES_DIR)/arkdiag $(SERVICES_DIR)/arkdiag.serve | $(BUILD_DIR)
	$(MAKE) -C $(RUNTIME_DIR)
	$(MAKE) -C $(SERVICES_DIR)
	rm -rf $(BUILD_DIR)/initramfs_root
	mkdir -p $(BUILD_DIR)/initramfs_root/dev \
	         $(BUILD_DIR)/initramfs_root/proc \
	         $(BUILD_DIR)/initramfs_root/sys \
	         $(BUILD_DIR)/initramfs_root/run \
	         $(BUILD_DIR)/initramfs_root/sbin \
	         $(BUILD_DIR)/initramfs_root/bin \
	         $(BUILD_DIR)/initramfs_root/lib64 \
	         $(BUILD_DIR)/initramfs_root/usr/lib \
	         $(BUILD_DIR)/initramfs_root/etc/ark/services.d
	ln -sf usr/lib $(BUILD_DIR)/initramfs_root/lib
	cp $(RUNTIME_DIR)/starter $(BUILD_DIR)/initramfs_root/sbin/arkrt
	chmod 755 $(BUILD_DIR)/initramfs_root/sbin/arkrt
	@if [ -f $(RUNTIME_DIR)/arkrt-swift ]; then \
		cp $(RUNTIME_DIR)/arkrt-swift $(BUILD_DIR)/initramfs_root/sbin/arkrt-swift; \
		chmod 755 $(BUILD_DIR)/initramfs_root/sbin/arkrt-swift; \
		cp /lib64/ld-linux-x86-64.so.2 $(BUILD_DIR)/initramfs_root/lib64/; \
		cp /usr/lib/libc.so.6 $(BUILD_DIR)/initramfs_root/usr/lib/; \
		cp /usr/lib/libm.so.6 $(BUILD_DIR)/initramfs_root/usr/lib/; \
		cp /usr/lib/libgcc_s.so.1 $(BUILD_DIR)/initramfs_root/usr/lib/; \
		cp -d /usr/lib/libstdc++.so.6* $(BUILD_DIR)/initramfs_root/usr/lib/; \
	fi
	@if [ -f $(SERVICES_DIR)/arkdiag ]; then \
		cp $(SERVICES_DIR)/arkdiag $(BUILD_DIR)/initramfs_root/sbin/arkdiag; \
		chmod 755 $(BUILD_DIR)/initramfs_root/sbin/arkdiag; \
	fi
	@if [ -f $(SERVICES_DIR)/arkdiag.serve ]; then \
		cp $(SERVICES_DIR)/arkdiag.serve $(BUILD_DIR)/initramfs_root/etc/ark/services.d/arkdiag.serve; \
		chmod 644 $(BUILD_DIR)/initramfs_root/etc/ark/services.d/arkdiag.serve; \
	fi
	(cd $(BUILD_DIR)/initramfs_root && find . | cpio -H newc -o > ../initramfs.cpio)

# ==============================================================================
# Target Static Initramfs Configuration (x86_64-swift-linux-musl)
# Packages fully static userspace binaries (starter.target, arkrt-swift-target, arkdiag.target).
# All paths configurable via environment or make arguments.
# ==============================================================================
TARGET_TRIPLE ?= x86_64-swift-linux-musl
SWIFT_SDKS_DIR ?= $(HOME)/.swiftpm/swift-sdks
SWIFT_SDK_BUNDLE ?= $(firstword $(wildcard $(SWIFT_SDKS_DIR)/*static-linux*.artifactbundle))
TARGET_SYSROOT ?= $(firstword $(wildcard $(SWIFT_SDK_BUNDLE)/*/swift-linux-musl/musl-1.2.5.sdk/x86_64))
MIMALLOC_OBJ ?= $(SYSROOT_DIR)/lib/mimalloc.o

INITRAMFS_TARGET_CPIO = $(BUILD_DIR)/initramfs-target.cpio
INITRAMFS_TARGET_ROOT = $(BUILD_DIR)/initramfs_target_root

$(RUNTIME_DIR)/starter.target:
	$(MAKE) -C $(RUNTIME_DIR) starter.target TARGET_SYSROOT="$(TARGET_SYSROOT)"

$(RUNTIME_DIR)/arkrt-swift-target:
	$(MAKE) -C $(RUNTIME_DIR) target TARGET_SYSROOT="$(TARGET_SYSROOT)" MIMALLOC_OBJ="$(MIMALLOC_OBJ)"

$(SERVICES_DIR)/arkdiag.target:
	$(MAKE) -C $(SERVICES_DIR) target TARGET_SYSROOT="$(TARGET_SYSROOT)" MIMALLOC_OBJ="$(MIMALLOC_OBJ)"

initramfs-target: $(INITRAMFS_TARGET_CPIO)

$(INITRAMFS_TARGET_CPIO): $(SERVICES_DIR)/arkdiag.serve | $(BUILD_DIR)
	@test -d "$(TARGET_SYSROOT)" || { \
		echo "Error: Swift Static Linux SDK musl sysroot not found at '$(TARGET_SYSROOT)'."; \
		echo "Install the official Swift Static Linux SDK or specify TARGET_SYSROOT=<path>."; \
		exit 1; \
	}
	@test -f "$(MIMALLOC_OBJ)" || { \
		echo "Error: Verified mimalloc object not found at '$(MIMALLOC_OBJ)'."; \
		echo "Build or sync sysbuilts or specify MIMALLOC_OBJ=<path>."; \
		exit 1; \
	}
	$(MAKE) -C $(RUNTIME_DIR) starter.target target TARGET_SYSROOT="$(TARGET_SYSROOT)" MIMALLOC_OBJ="$(MIMALLOC_OBJ)"
	$(MAKE) -C $(SERVICES_DIR) target TARGET_SYSROOT="$(TARGET_SYSROOT)" MIMALLOC_OBJ="$(MIMALLOC_OBJ)"
	rm -rf $(INITRAMFS_TARGET_ROOT)
	mkdir -p $(INITRAMFS_TARGET_ROOT)/dev \
	         $(INITRAMFS_TARGET_ROOT)/proc \
	         $(INITRAMFS_TARGET_ROOT)/sys \
	         $(INITRAMFS_TARGET_ROOT)/run \
	         $(INITRAMFS_TARGET_ROOT)/sbin \
	         $(INITRAMFS_TARGET_ROOT)/bin \
	         $(INITRAMFS_TARGET_ROOT)/etc/ark/services.d
	cp $(RUNTIME_DIR)/starter.target $(INITRAMFS_TARGET_ROOT)/sbin/arkrt
	chmod 755 $(INITRAMFS_TARGET_ROOT)/sbin/arkrt
	ln -sf sbin/arkrt $(INITRAMFS_TARGET_ROOT)/init
	cp $(RUNTIME_DIR)/arkrt-swift-target $(INITRAMFS_TARGET_ROOT)/sbin/arkrt-swift
	chmod 755 $(INITRAMFS_TARGET_ROOT)/sbin/arkrt-swift
	cp $(SERVICES_DIR)/arkdiag.target $(INITRAMFS_TARGET_ROOT)/sbin/arkdiag
	chmod 755 $(INITRAMFS_TARGET_ROOT)/sbin/arkdiag
	cp $(SERVICES_DIR)/arkdiag.serve $(INITRAMFS_TARGET_ROOT)/etc/ark/services.d/arkdiag.serve
	chmod 644 $(INITRAMFS_TARGET_ROOT)/etc/ark/services.d/arkdiag.serve
	(cd $(INITRAMFS_TARGET_ROOT) && find . | cpio -H newc -o > ../initramfs-target.cpio)
	@echo "[ARK-OS] Static musl initramfs created at $(INITRAMFS_TARGET_CPIO)"

validate-initramfs-target: $(INITRAMFS_TARGET_CPIO)
	@echo "=================================================================="
	@echo "[VALIDATION] Inspecting static initramfs: $(INITRAMFS_TARGET_CPIO)"
	@echo "=================================================================="
	@test -f $(INITRAMFS_TARGET_CPIO) || { echo "Error: $(INITRAMFS_TARGET_CPIO) does not exist."; exit 1; }
	@echo "Archive size: $$(stat -c %s $(INITRAMFS_TARGET_CPIO)) bytes"
	@echo ""
	@echo "--- Archive File Listing (cpio -itv) ---"
	@cpio -itv < $(INITRAMFS_TARGET_CPIO)
	@echo ""
	@echo "--- Validating Required Files and Permissions ---"
	@cpio -it < $(INITRAMFS_TARGET_CPIO) | grep -q "^sbin/arkrt$$" || { echo "FAIL: missing sbin/arkrt"; exit 1; }
	@cpio -it < $(INITRAMFS_TARGET_CPIO) | grep -q "^sbin/arkrt-swift$$" || { echo "FAIL: missing sbin/arkrt-swift"; exit 1; }
	@cpio -it < $(INITRAMFS_TARGET_CPIO) | grep -q "^sbin/arkdiag$$" || { echo "FAIL: missing sbin/arkdiag"; exit 1; }
	@cpio -it < $(INITRAMFS_TARGET_CPIO) | grep -q "^etc/ark/services.d/arkdiag.serve$$" || { echo "FAIL: missing etc/ark/services.d/arkdiag.serve"; exit 1; }
	@cpio -it < $(INITRAMFS_TARGET_CPIO) | grep -q "^init$$" || { echo "FAIL: missing init symlink"; exit 1; }
	@echo "PASS: All required files and symlinks present."
	@echo ""
	@echo "--- Validating Static Linkage (Zero Dynamic Dependencies) ---"
	@test -f $(INITRAMFS_TARGET_ROOT)/sbin/arkrt || { echo "FAIL: staged sbin/arkrt not found"; exit 1; }
	@file $(INITRAMFS_TARGET_ROOT)/sbin/arkrt | grep -q "statically linked" || { echo "FAIL: sbin/arkrt is not statically linked"; exit 1; }
	@file $(INITRAMFS_TARGET_ROOT)/sbin/arkrt-swift | grep -q "statically linked" || { echo "FAIL: sbin/arkrt-swift is not statically linked"; exit 1; }
	@file $(INITRAMFS_TARGET_ROOT)/sbin/arkdiag | grep -q "statically linked" || { echo "FAIL: sbin/arkdiag is not statically linked"; exit 1; }
	@readelf -l $(INITRAMFS_TARGET_ROOT)/sbin/arkrt-swift | grep -q "INTERP" && { echo "FAIL: sbin/arkrt-swift contains PT_INTERP"; exit 1; } || true
	@readelf -l $(INITRAMFS_TARGET_ROOT)/sbin/arkdiag | grep -q "INTERP" && { echo "FAIL: sbin/arkdiag contains PT_INTERP"; exit 1; } || true
	@echo "PASS: All packaged binaries are confirmed statically linked with no dynamic interpreter."
	@echo ""
	@echo "--- Validating Allocator Integration ---"
	@nm $(INITRAMFS_TARGET_ROOT)/sbin/arkrt-swift | grep -q "mi_malloc" || { echo "FAIL: mimalloc not present in sbin/arkrt-swift"; exit 1; }
	@nm $(INITRAMFS_TARGET_ROOT)/sbin/arkdiag | grep -q "mi_malloc" || { echo "FAIL: mimalloc not present in sbin/arkdiag"; exit 1; }
	@echo "PASS: mimalloc symbols present and active in all Swift binaries."
	@echo "=================================================================="
	@echo "[VALIDATION SUCCESS] Target static initramfs structure verified."
	@echo "=================================================================="

esp-target: $(TARGET) $(INITRAMFS_TARGET_CPIO) kernel
	mkdir -p $(BUILD_DIR)/esp/EFI/BOOT
	cp $(TARGET) $(BUILD_DIR)/esp/EFI/BOOT/BOOTX64.EFI
	@if [ -f $(KERNEL_IMAGE) ]; then \
		cp $(KERNEL_IMAGE) $(BUILD_DIR)/esp/EFI/BOOT/bzImage; \
		cp $(KERNEL_IMAGE) $(BUILD_DIR)/esp/bzImage; \
	else \
		echo "[ARKBOOT] Error: $(KERNEL_IMAGE) not found!"; exit 1; \
	fi
	cp $(INITRAMFS_TARGET_CPIO) $(BUILD_DIR)/esp/EFI/BOOT/initramfs.cpio
	cp $(INITRAMFS_TARGET_CPIO) $(BUILD_DIR)/esp/initramfs.cpio
	@echo "[ARKBOOT] Target ESP assembled with static initramfs at $(BUILD_DIR)/esp"

kernel:
	@chmod +x $(SYNC_SCRIPT)
	@$(SYNC_SCRIPT) kernel $(KERNEL_DIR)

kernel-upgrade:
	@chmod +x $(SYNC_SCRIPT)
	@FORCE_UPGRADE=1 $(SYNC_SCRIPT) kernel $(KERNEL_DIR)

sysbuilts:
	@chmod +x $(SYNC_SCRIPT)
	@$(SYNC_SCRIPT) sysbuilts $(SYSROOT_DIR)

sysbuilts-upgrade:
	@chmod +x $(SYNC_SCRIPT)
	@FORCE_UPGRADE=1 $(SYNC_SCRIPT) sysbuilts $(SYSROOT_DIR)

sync:
	@chmod +x $(SYNC_SCRIPT)
	@$(SYNC_SCRIPT) all

esp: $(TARGET) $(BUILD_DIR)/initramfs.cpio kernel
	mkdir -p $(BUILD_DIR)/esp/EFI/BOOT
	cp $(TARGET) $(BUILD_DIR)/esp/EFI/BOOT/BOOTX64.EFI
	@if [ -f $(KERNEL_IMAGE) ]; then \
		cp $(KERNEL_IMAGE) $(BUILD_DIR)/esp/EFI/BOOT/bzImage; \
		cp $(KERNEL_IMAGE) $(BUILD_DIR)/esp/bzImage; \
	else \
		echo "[ARKBOOT] Error: $(KERNEL_IMAGE) not found!"; exit 1; \
	fi
	cp $(BUILD_DIR)/initramfs.cpio $(BUILD_DIR)/esp/EFI/BOOT/initramfs.cpio
	cp $(BUILD_DIR)/initramfs.cpio $(BUILD_DIR)/esp/initramfs.cpio

test: esp
	qemu-system-x86_64 \
		-bios /usr/share/edk2/x64/OVMF.4m.fd \
		-drive file=fat:rw:$(BUILD_DIR)/esp,format=raw \
		-m 1024M \
		-net none \
		-serial stdio \
		-vga std

test-qemu: test

run: test

clean:
	rm -rf $(BUILD_DIR)/*.o $(BUILD_DIR)/*.so $(BUILD_DIR)/esp $(BUILD_DIR)/initramfs* $(TARGET)

clean-kernel:
	rm -rf $(KERNEL_DIR)

clean-sysroot:
	rm -rf $(SYSROOT_DIR)
