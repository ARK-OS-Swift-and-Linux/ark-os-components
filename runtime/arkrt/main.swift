#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#endif
import CSignals

// Unbuffer stdout and stderr for immediate output to the console
setbuf(stdout, nil)
setbuf(stderr, nil)

let myPid = getpid()
print("[arkrt-swift] ARK-OS Swift Main Runtime active (PID: \(myPid))")

if myPid != 1 {
    print("[arkrt-swift] Warning: Process is running as PID \(myPid), expected PID 1.")
}

func readLineFromFile(_ path: String) -> String? {
    guard let fp = fopen(path, "r") else { return nil }
    defer { fclose(fp) }
    var buffer = [CChar](repeating: 0, count: 512)
    if fgets(&buffer, Int32(buffer.count), fp) != nil {
        var str = String(cString: buffer)
        while str.last?.isWhitespace == true || str.last?.isNewline == true {
            str.removeLast()
        }
        return str
    }
    return nil
}

// Display kernel release from /proc/sys/kernel/osrelease
if let kernelRelease = readLineFromFile("/proc/sys/kernel/osrelease") {
    print("[arkrt-swift] Verified active kernel: \(kernelRelease)")
}

// Display boot command line from /proc/cmdline
if let cmdline = readLineFromFile("/proc/cmdline") {
    print("[arkrt-swift] Boot command line: \"\(cmdline)\"")
}

print("[arkrt-swift] Early userspace initialization verified.")
print("[arkrt-swift] Entering PID 1 service lifecycle supervisor event loop.")
fflush(stdout)

// Initialize async-signal-safe POSIX signal handlers in pure C
arkrt_init_signals()

// Initialize the system service supervisor
let supervisor = ServiceSupervisor()

// Discover and launch system services from declarative definitions
let serviceDefinitionsDir = "/etc/ark/services.d"
supervisor.loadServices(fromDirectory: serviceDefinitionsDir)
supervisor.startAllServices()

var shutdownInitiated = false
var shutdownStartTime: time_t = 0
let maxShutdownGracePeriod: time_t = 15

// Non-blocking PID 1 supervisor event loop
while true {
    // 1. Non-blocking reaping of any terminated child processes (with EINTR resilience)
    supervisor.reapChildren()

    // 2. Timer ticks for scheduled restarts and graceful stop grace periods
    supervisor.tick()

    // 3. Handle shutdown requests cleanly via async-signal-safe C query
    if arkrt_is_shutdown_requested() != 0 {
        if !shutdownInitiated {
            shutdownInitiated = true
            shutdownStartTime = time(nil)
            print("[arkrt-swift] Termination signal received. Initiating orderly shutdown...")
            fflush(stdout)
            supervisor.stopAllServices()
        }

        if supervisor.areAllServicesStopped {
            print("[arkrt-swift] All managed services stopped cleanly. Halting PID 1.")
            fflush(stdout)
            break
        }

        // Hard deadline fallback: ensure PID 1 never hangs indefinitely during shutdown
        let elapsed = time(nil) - shutdownStartTime
        if elapsed >= maxShutdownGracePeriod {
            print("[arkrt-swift] Warning: Shutdown deadline (\(maxShutdownGracePeriod)s) reached with remaining services. Halting PID 1.")
            fflush(stdout)
            break
        }
    }

    // 4. Tick interval: 250ms prevents CPU spinning while maintaining responsiveness
    usleep(250000)
}
