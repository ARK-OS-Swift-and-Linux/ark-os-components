# ARK-OS Runtime (`arkrt`)

`arkrt` is the initial userspace process and runtime supervisor for ARK-OS, executed by the Linux kernel as PID 1 (`rdinit=/sbin/arkrt`).

## Architecture: Two-Stage Boot Process

To balance robustness during early startup with Swift language features, `arkrt` implements a two-stage handoff:

### 1. Stage 1: C Starter (`/sbin/arkrt`)
- **Format:** Pure self-contained, statically linked ELF 64-bit binary with zero external dynamic dependencies.
- **Entry Contract:** Invoked directly by Linux at PID 1.
- **Responsibilities:**
  - Validates `getpid() == 1`.
  - Mounts essential virtual filesystems:
    - `/dev` (`devtmpfs`)
    - `/proc` (`procfs`)
    - `/sys` (`sysfs`)
    - `/run` (`tmpfs`)
    - `/dev/pts` (`devpts`)
    - `/dev/shm` (`tmpfs`)
  - Redirects standard I/O (descriptors 0, 1, 2) to `/dev/console` (with serial fallback).
  - Emits boot diagnostics.
  - Locates the Stage 2 Swift main runtime at `/sbin/arkrt-swift`.
  - Executes `execve("/sbin/arkrt-swift", argv, envp)` to replace the starter image while preserving PID 1.
  - **Fallback Mode:** If the Swift runtime is absent or `execve` returns an error, the starter explicitly reports the failure, marks the system in fallback mode, installs signal handlers, reaps terminated child processes asynchronously, and enters a supervisory loop (`pause()`).

### 2. Stage 2: Swift Main Runtime (`/sbin/arkrt-swift`)
- **Format:** Compiled with `swiftc -O -static-stdlib`, linking the Swift standard library statically while utilizing glibc shared libraries (`libc.so.6`, `libm.so.6`, `libgcc_s.so.1`, `libstdc++.so.6`, `/lib64/ld-linux-x86-64.so.2`) staged within the initramfs.
- **Responsibilities:**
  - Verifies PID 1 status.
  - Inspects kernel configuration and environment via `/proc`.
  - Configures child process reaping and signals.
  - Maintains the long-lived supervisor event loop.

## Compilation

```bash
make
```

Produces:
- `starter`: Statically linked C binary installed as `/sbin/arkrt`
- `arkrt-swift`: Swift runtime binary installed as `/sbin/arkrt-swift`
