# ARK-OS System Components

## Overview

The `components/` repository houses the first-party userspace software modules and core operating system components that comprise ARK-OS.

ARK-OS utilizes a Swift-first userspace architecture per [ADR-0002](file:///home/aarav/repo/arkos/docs/decisions/ADR-0002-swift-first-userspace.md), built upon the Linux kernel foundation ([ADR-0001](file:///home/aarav/repo/arkos/docs/decisions/ADR-0001-linux-kernel-foundation.md)).

---

## Component Organization

- `runtime/` - Early system initialization and process management:
  - `runtime/arkrt`: The first-party init process (PID 1) and userspace runtime engine.
- `shell/` - System shell environments:
  - `shell/sash`: The Swift-implemented system administrative and interactive shell.
- `libraries/` - Shared foundation and native interop libraries:
  - `libraries/libark`: Core platform library, system abstractions, and kernel C API bindings.
- `boot/` - Bootloader assets, kernel command line configurations, and initramfs blueprints.
- `services/` - System daemons, device managers, and background service frameworks.
- `apps/` - Core system user applications and management utilities.

---

## Architectural Rules

- **Strict Component Isolation:** Components must not introduce circular dependencies. Higher-level services and apps depend on `libark`, but `libark` remains strictly decoupled from upper layers.
- **Fail-Safe Diagnostics:** Early boot components (`arkrt`, `sash`) must provide deterministic diagnostic outputs over serial interfaces before complex logging services exist.

---

## Build System & Root Makefile

The root [Makefile](file:///home/aarav/repo/arkos/components/Makefile) provides unified build orchestration across the core system components, linking the userspace init runtime in [`runtime/arkrt`](file:///home/aarav/repo/arkos/components/runtime/arkrt) and the UEFI bootloader in [`boot`](file:///home/aarav/repo/arkos/components/boot).

### Available Targets

| Target | Description |
| :--- | :--- |
| `make` / `make all` | Builds the runtime (`starter` and `arkrt-swift`), compiles the UEFI bootloader (`ARKBOOT.EFI`), verifies the kernel, stages the initramfs, and prepares the ESP boot directory (`boot/build/esp`). |
| `make runtime` | Builds the Stage 1 static C starter (`starter`) and Stage 2 Swift main runtime (`arkrt-swift`) under `runtime/arkrt/`. |
| `make boot` | Compiles the UEFI bootloader application (`ARKBOOT.EFI`) under `boot/`. |
| `make initramfs` | Packs `initramfs.cpio` containing `/sbin/arkrt`, `/sbin/arkrt-swift`, and required dynamic runtime libraries. |
| `make kernel` | Verifies and downloads the target precompiled kernel release from GitHub if not already cached. |
| `make kernel-upgrade` | Checks for newer kernel releases and prompts for an interactive upgrade. |
| `make esp` | Assembles the complete EFI System Partition (`BOOTX64.EFI`, `bzImage`, and `initramfs.cpio`). |
| `make test` / `make run` | Assembles the ESP volume and boots the entire system end-to-end in QEMU with OVMF firmware. |
| `make clean` | Cleans build artifacts across both `runtime/arkrt/` and `boot/`. |
| `make clean-all` | Cleans all build artifacts and purges the cached kernel image. |
| `make help` | Displays a concise reference of all build targets. |

---

## License

This repository is licensed under the Apache License, Version 2.0. See [LICENSE](file:///home/aarav/repo/arkos/components/LICENSE) for details.

