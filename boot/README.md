# ARK-OS Bootloader (Stage A & Stage B)

This directory contains the first-party x86_64 UEFI bootloader for ARK-OS (`ARKBOOT.EFI`), implemented in C using the GNU-EFI toolchain.

## Status

- **Stage A (Visual Milestone):** Implemented and verified (displays centered white dot of radius 15px on solid black background).
- **Stage B (Kernel and Initramfs Handoff):** Implemented.

## Architecture and Scope

The bootloader transitions the system from UEFI firmware to the ARK-OS Linux kernel while preserving the Stage A visual state:

1. **UEFI Entry & Graphics Initialization:**
   - Enters via `efi_main` using GNU-EFI conventions.
   - Queries and initializes the UEFI Graphics Output Protocol (GOP).
   - Clears the active display framebuffer to solid black (`#000000`).
   - Renders exactly one stationary, solid white dot (`#FFFFFF`) with a radius of 15 pixels at the center of the screen.
   - Maintains a graphical screen free of text, cursors, or logos.

2. **Artifact Discovery and File Loading:**
   - Obtains the boot volume filesystem via `EFI_LOADED_IMAGE_PROTOCOL` and `EFI_SIMPLE_FILE_SYSTEM_PROTOCOL`.
   - Locates and reads the Linux kernel artifact (`\EFI\BOOT\bzImage` or fallback `\bzImage`).
   - Locates and reads the initial ramdisk (`\EFI\BOOT\initramfs.cpio` or fallback `\initramfs.cpio`).
   - Validates bzImage headers (`0xAA55` boot flag, `'HdrS'` signature, boot protocol version >= 2.00, and `XLF_KERNEL_64`).

3. **Linux x86 64-bit Boot Protocol Handoff:**
   - Allocates 2MB-aligned memory for kernel protected-mode execution based on `setup_header.init_size`.
   - Allocates and copies `boot_params` (zero page, 4096 bytes) and kernel command line.
   - Populates `screen_info` with GOP linear framebuffer parameters (`VIDEO_TYPE_EFI`, `VIDEO_CAPABILITY_64BIT_BASE`, base, size, stride, depth, resolution, and color masks).
   - Queries the UEFI memory map, populating `efi_info` (`"EL64"`) and the `e820_table`.
   - Executes `ExitBootServices` with map key retry handling.
   - Disables interrupts (`cli`), loads a flat 64-bit Global Descriptor Table (CS=0x10, DS=0x18), sets `%rsi` to `boot_params`, and transfers control directly to `startup_64` (offset `0x200` from protected-mode base).

4. **Diagnostics and Visual Preservation:**
   - All diagnostic logs are routed exclusively to COM1 serial (I/O port `0x3F8`).
   - The graphical display remains black with the single white dot undisturbed throughout loading and kernel takeover.

## Directory Layout

```
components/boot/
├── Makefile            # Build orchestration and ESP assembly
├── README.md           # Component documentation
├── include/
│   └── ark_boot.h      # Bootloader structures, prototypes, and Linux ABI definitions
├── loader/
│   ├── fs.c            # UEFI Simple File System loader (kernel & initramfs)
│   ├── graphics.c      # GOP discovery, framebuffer clearing, dot rasterization
│   ├── linux.c         # Linux 64-bit boot protocol setup, memory mapping, and handoff
│   ├── main.c          # UEFI entry point (efi_main) and boot orchestrator
│   └── serial.c        # Low-level COM1 serial diagnostics
└── scripts/
    └── fetch_kernel.sh # Automated kernel release discovery, checksum verification, and upgrade

## Build Requirements

- `gcc` with x86_64 freestanding support
- `gnu-efi` development headers and libraries (`/usr/include/efi`, `/usr/lib/crt0-efi-x86_64.o`, `/usr/lib/libgnuefi.a`, `/usr/lib/libefi.a`)
- `binutils` (`ld`, `objcopy` with `efi-app-x86_64` support)
- `curl` and `jq` (or `python3`) for release checking
- `tar` and `sha256sum` for artifact verification and extraction
- `cpio` for minimal initramfs assembly
- `qemu-system-x86_64` and OVMF firmware (`OVMF.4m.fd`) for emulation testing

## Kernel Release Management

The Makefile automatically integrates with the [ARK-OS Kernel Compilation Station](https://github.com/ARK-OS-Swift-and-Linux/ark-os-kernel-compilation-station) GitHub repository:

- **Automatic Download:** If no kernel is present in `build/kernel/`, the latest release is automatically downloaded, verified with `SHA256SUMS.txt`, reassembled, and extracted.
- **Interactive Upgrade Prompt:** When a newer release is published, the build process automatically notifies you and prompts whether to upgrade (`[y/N]`).
- **Offline / Non-interactive:** If offline, existing local kernels are used seamlessly. Non-interactive environments default to preserving the current build.

Useful commands:
```bash
# Check for updates and download if needed
make kernel

# Force upgrade to the latest build
make kernel-upgrade

# Skip remote network check (pure offline build)
SKIP_KERNEL_CHECK=1 make esp

# Clean downloaded kernel artifacts
make clean-kernel
```

## Compilation and Packaging

To compile `ARKBOOT.EFI` and ensure the kernel is up to date:

```bash
make
```

To assemble the complete EFI System Partition (`build/esp/`) containing `BOOTX64.EFI`, `bzImage`, and `initramfs.cpio`:

```bash
make esp
```

## Testing under QEMU

To boot in an isolated QEMU/OVMF environment with both the graphical display window and serial console:

```bash
make test
```
