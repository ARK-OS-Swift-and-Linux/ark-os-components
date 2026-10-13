CC ?= gcc
LD ?= ld
OBJCOPY ?= objcopy

BUILD_DIR ?= build
LOADER_DIR ?= loader
INCLUDE_DIR ?= include

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

.PHONY: all clean esp test test-qemu run initramfs

all: $(TARGET)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.o: $(LOADER_DIR)/%.c $(INCLUDE_DIR)/ark_boot.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/arkboot.so: $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $@ $(LIBS)

$(TARGET): $(BUILD_DIR)/arkboot.so
	$(OBJCOPY) $(OBJCOPY_FLAGS) $< $@

initramfs: $(BUILD_DIR)/initramfs.cpio

$(BUILD_DIR)/initramfs.cpio: | $(BUILD_DIR)
	rm -rf $(BUILD_DIR)/initramfs_root
	mkdir -p $(BUILD_DIR)/initramfs_root/dev \
	         $(BUILD_DIR)/initramfs_root/proc \
	         $(BUILD_DIR)/initramfs_root/sys \
	         $(BUILD_DIR)/initramfs_root/sbin \
	         $(BUILD_DIR)/initramfs_root/bin
	(cd $(BUILD_DIR)/initramfs_root && find . | cpio -H newc -o > ../initramfs.cpio)

esp: $(TARGET) $(BUILD_DIR)/initramfs.cpio
	mkdir -p $(BUILD_DIR)/esp/EFI/BOOT
	cp $(TARGET) $(BUILD_DIR)/esp/EFI/BOOT/BOOTX64.EFI
	@if [ -f $(BUILD_DIR)/kernel/boot/bzImage ]; then \
		cp $(BUILD_DIR)/kernel/boot/bzImage $(BUILD_DIR)/esp/EFI/BOOT/bzImage; \
		cp $(BUILD_DIR)/kernel/boot/bzImage $(BUILD_DIR)/esp/bzImage; \
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
