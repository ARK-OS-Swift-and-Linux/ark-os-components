# ARK-OS Bootloader (Stage A)

This directory contains the first-party x86_64 UEFI bootloader for ARK-OS (`ARKBOOT.EFI`), implemented in C using the GNU-EFI toolchain.

## Status

- **Stage A (Visual Milestone):** Implemented and verified.
- **Stage B (Kernel and Initramfs Loading):** Planned.

## Scope of Stage A

Stage A implements a genuine standalone x86_64 UEFI application meeting the following requirements:
- Enters through standard UEFI application entry point (`efi_main`).
- Queries and initializes the UEFI Graphics Output Protocol (GOP).
- Clears the active display framebuffer to solid black (`#000000`).
- Renders exactly one stationary, solid white dot (`#FFFFFF`) with a radius of 15 pixels at the exact center of the display.
- Accurately accounts for framebuffer dimensions, stride (`PixelsPerScanLine`), and pixel formats (`RGBX`, `BGRX`, and bitmask).
- Maintains a graphical screen free of text, logos, cursors, progress indicators, or animations.
- Outputs diagnostic messages headlessly over serial port COM1 (I/O port `0x3F8`) without polluting the display.
- Safely stalls on completion without exiting or rebooting.

Kernel handoff, `ExitBootServices`, initramfs loading, and memory map translation are intentionally deferred to subsequent stages.

## Directory Layout

```
components/boot/
├── Makefile            # Build orchestration and test automation
├── README.md           # Component documentation
├── include/
│   └── ark_boot.h      # Bootloader prototypes and definitions
└── loader/
    ├── graphics.c      # GOP discovery, framebuffer clearing, dot rasterization
    ├── main.c          # UEFI entry point (efi_main) and stage workflow
    └── serial.c        # Low-level COM1 serial diagnostics
```

## Build Requirements

- `gcc` with x86_64 freestanding support
- `gnu-efi` development headers and libraries (`/usr/include/efi`, `/usr/lib/crt0-efi-x86_64.o`, `/usr/lib/libgnuefi.a`, `/usr/lib/libefi.a`)
- `binutils` (`ld`, `objcopy` with `efi-app-x86_64` support)
- `qemu-system-x86_64` and OVMF firmware (`OVMF.4m.fd`) for emulation testing

## Compilation

To compile `ARKBOOT.EFI`:

```bash
make
```

## Visual Testing

To launch the bootloader in QEMU with a graphical window for visual inspection:

```bash
make test
```

(or `make run` / `make test-qemu`)
