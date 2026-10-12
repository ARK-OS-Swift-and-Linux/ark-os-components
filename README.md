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

## License

This repository is licensed under the Apache License, Version 2.0. See [LICENSE](file:///home/aarav/repo/arkos/components/LICENSE) for details.
