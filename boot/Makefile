CC ?= gcc
LD ?= ld
OBJCOPY ?= objcopy

BUILD_DIR ?= build
LOADER_DIR ?= loader
INCLUDE_DIR ?= include
KERNEL_DIR ?= $(BUILD_DIR)/kernel
KERNEL_SCRIPT ?= scripts/fetch_kernel.sh
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

.PHONY: all clean clean-kernel esp test test-qemu run initramfs kernel kernel-upgrade

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

$(BUILD_DIR)/initramfs.cpio: $(RUNTIME_DIR)/starter $(SERVICES_DIR)/arkdiag | $(BUILD_DIR)
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
	         $(BUILD_DIR)/initramfs_root/usr/lib
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
	(cd $(BUILD_DIR)/initramfs_root && find . | cpio -H newc -o > ../initramfs.cpio)

kernel:
	@chmod +x $(KERNEL_SCRIPT)
	@$(KERNEL_SCRIPT) $(KERNEL_DIR)

kernel-upgrade:
	@chmod +x $(KERNEL_SCRIPT)
	@FORCE_UPGRADE=1 $(KERNEL_SCRIPT) $(KERNEL_DIR)

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
