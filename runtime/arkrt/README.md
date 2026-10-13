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
  - Installs minimal async-signal-safe handlers (`SIGCHLD`, `SIGTERM`, `SIGINT`).
  - Manages system services via `ServiceSupervisor`.
  - Performs non-blocking child process reaping (`waitpid(-1, &status, WNOHANG)`).
  - Enforces restart policies, backoff timers, and graceful shutdown.

---

## Service Supervision Foundation

The Swift main runtime provides service supervision using a strongly-typed lifecycle model implemented in [`Service.swift`](file:///home/aarav/repo/arkos/components/runtime/arkrt/Service.swift) and [`Supervisor.swift`](file:///home/aarav/repo/arkos/components/runtime/arkrt/Supervisor.swift).

### 1. Service Lifecycle States

Every managed service transitions through well-defined lifecycle states:

- **`configured`**: The service definition has been registered but not yet launched.
- **`starting`**: The service process is currently being spawned (`fork()` in flight).
- **`running(pid: pid_t)`**: The process is active and running under the given PID.
- **`exited(exitCode: Int32)`**: The process terminated normally with the specified exit code.
- **`failed(reason: String)`**: The process failed (e.g. fatal exit code, unexpected signal, or restart limit exceeded).
- **`restarting(attempt: Int, nextAttemptInSeconds: Int)`**: The process exited and is awaiting its scheduled restart attempt following the backoff delay.
- **`stopping(pid: pid_t)`**: A shutdown request was initiated (`SIGTERM` sent), awaiting process termination before timeout.

### 2. Restart Policies

- **`.never`**: The service runs once and is not restarted when it exits.
- **`.always(maxRestarts: Int, restartDelaySeconds: Int)`**: The service is always restarted upon termination until `maxRestarts` is exceeded.
- **`.onFailure(maxRestarts: Int, restartDelaySeconds: Int)`**: The service is restarted only if it terminates with a non-zero exit code or an unhandled signal, up to `maxRestarts`.

### 3. Termination & Child Reaping

- Non-blocking reaping via `waitpid(-1, &status, WNOHANG)` runs on every loop iteration, ensuring orphaned child processes are reaped without blocking supervisor progress.
- Clean shutdown is triggered via `SIGTERM` or `SIGINT`, giving processes their configured grace period (`stopTimeoutSeconds`) before escalating to `SIGKILL`.

---

## Compilation & Testing

```bash
# Build runtime starter and Swift runtime
make

# Run the host-side supervisor test suite
make test

# Clean build artifacts
make clean
```
