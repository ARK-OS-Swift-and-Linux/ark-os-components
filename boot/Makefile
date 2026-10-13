CC ?= gcc
LD ?= ld
OBJCOPY ?= objcopy

BUILD_DIR ?= build
LOADER_DIR ?= loader
INCLUDE_DIR ?= include

CFLAGS = -O2 -fpic -ffreestanding -fno-stack-protector -fno-stack-check \
         -fshort-wchar -mno-red-zone -mno-sse -mno-mmx \
         -Wall -Wextra -Werror \
         -I/usr/include/efi -I/usr/include/efi/x86_64 -I$(INCLUDE_DIR)

LDFLAGS = -nostdlib -znocombreloc -T /usr/lib/elf_x86_64_efi.lds -shared -Bsymbolic \
          -L /usr/lib /usr/lib/crt0-efi-x86_64.o

LIBS = -lgnuefi -lefi

OBJCOPY_FLAGS = -j .text -j .sdata -j .data -j .dynamic -j .dynsym \
                -j .rel -j .rela -j .reloc -j .rodata \
                -O efi-app-x86_64

OBJS = $(BUILD_DIR)/main.o $(BUILD_DIR)/graphics.o $(BUILD_DIR)/serial.o

TARGET = ARKBOOT.EFI

.PHONY: all clean esp test test-qemu run

all: $(TARGET)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.o: $(LOADER_DIR)/%.c $(INCLUDE_DIR)/ark_boot.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/arkboot.so: $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $@ $(LIBS)

$(TARGET): $(BUILD_DIR)/arkboot.so
	$(OBJCOPY) $(OBJCOPY_FLAGS) $< $@

esp: $(TARGET)
	mkdir -p $(BUILD_DIR)/esp/EFI/BOOT
	cp $(TARGET) $(BUILD_DIR)/esp/EFI/BOOT/BOOTX64.EFI

test: esp
	qemu-system-x86_64 \
		-bios /usr/share/edk2/x64/OVMF.4m.fd \
		-drive file=fat:rw:$(BUILD_DIR)/esp,format=raw \
		-net none \
		-serial stdio \
		-vga std

test-qemu: test

run: test

clean:
	rm -rf $(BUILD_DIR) $(TARGET)
