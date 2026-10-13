# ARK-OS Diagnostic Service (`arkdiag`)

`arkdiag` is a first-party system diagnostic daemon for ARK-OS. It monitors early system health, verifies pseudo-filesystem accessibility, inspects resource usage, and emits periodic heartbeat reports.

## Role & Responsibilities

1. **System Health Probes:**
   - Samples kernel uptime (`/proc/uptime`).
   - Reads system load averages (`/proc/loadavg`).
   - Parses system memory utilization (`/proc/meminfo`).
2. **Lifecycle & Signal Handling:**
   - Handles `SIGTERM` and `SIGINT` asynchronously.
   - Cleans up state and terminates with exit code `0` on signal receipt.
3. **Verification Modes:**
   - Supports `--oneshot` to run a single diagnostic check and exit `0`.
   - Supports `--fail-after <N>` to simulate a controlled crash after $N$ heartbeats, allowing verification of the runtime supervisor's restart policies.

## Compilation

```bash
make
```

Outputs the statically-bundled Swift executable `arkdiag`.
