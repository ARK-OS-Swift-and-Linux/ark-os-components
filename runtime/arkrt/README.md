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

## Declarative Service Definitions (`.serve`)

Services in ARK-OS are defined declaratively using `.serve` definition files located in `/etc/ark/services.d/`. The Swift supervisor automatically discovers, parses, validates, and topologically orders all services on startup.

### 1. File Grammar & Syntax

- Files are UTF-8 key-value configuration files.
- Lines with `#` or `;` as their first non-whitespace character are comments.
- Empty lines and leading/trailing whitespace around keys and values are ignored.
- Keys are case-insensitive and delimited from values by `=`.
- Duplicate keys within a file and unknown keys are strictly rejected as configuration errors.
- Configuration errors fail safely: invalid descriptors are rejected without crashing PID 1 or stalling other services.

Example (`/etc/ark/services.d/arkdiag.serve`):

```ini
# System Diagnostic Service Definition
name=arkdiag
exec=/sbin/arkdiag
restart=on-failure
max_restarts=3
restart_delay=2
stop_timeout=5
after=
requires=
```

### 2. Supported Fields & Defaults

| Field | Type | Bounds / Allowed Values | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `name` | String | 1..64 chars `[a-zA-Z0-9_-]` | *Required* | Unique service identifier. |
| `exec` | String | Absolute path starting with `/` | *Required* | Executable binary path. Must have `X_OK` permissions. |
| `restart` | String | `never`, `always`, `on-failure` | `never` | Service restart policy upon process exit. |
| `max_restarts` | Integer | `0`..`100` | `0` (`never`), `3` (other) | Maximum restart attempts before entering `.failed`. |
| `restart_delay`| Integer | `0`..`3600` seconds | `1` | Backoff delay before executing a scheduled restart. |
| `stop_timeout` | Integer | `1`..`300` seconds | `5` | Grace period after `SIGTERM` before escalating to `SIGKILL`. |
| `after` | List | Comma or whitespace separated names | `[]` | Ordering directive: services that must start before this service. |
| `requires` | List | Comma or whitespace separated names | `[]` | Hard dependency: services required for this service to run. |

### 3. Dependency Semantics & Topological Ordering

- **`after=A` (Ordering Directive):** If service A is present, A must start before this service. If service A is omitted or absent from the system, the directive is ignored and does not block startup.
- **`requires=A` (Hard Dependency):**
  - If service A is missing from the system, this service transitions to `.failed(reason: "Missing required dependency: 'A'")` and is never launched.
  - If service A fails to start (e.g. executable missing or fork error), this service is blocked and transitions to `.failed`.
  - If service A is stopped or fails later during runtime, any active dependent service that requires A is automatically stopped gracefully.
- **Cycle Detection:** Kahn's algorithm detects circular dependencies prior to execution. Services involved in or downstream of a cycle transition to `.failed(reason: "Dependency cycle detected")`, while independent services start normally.
- **Deterministic Ordering:** Ready services at every dependency level are processed in alphabetical order by name, guaranteeing identical boot order across boots.

### 4. How to Add a New Service

1. Create a service descriptor file `<service_name>.serve` specifying `name`, `exec`, and relevant lifecycle policies.
2. Package the compiled executable into the root filesystem (e.g. `/sbin/<service_name>`).
3. Place `<service_name>.serve` into `/etc/ark/services.d/` in the initramfs.
4. No edits to `main.swift` or PID 1 source code are necessary.

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
