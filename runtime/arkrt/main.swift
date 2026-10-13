import Musl

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

// Async-signal-safe shutdown request flag
var g_shutdownRequested: sig_atomic_t = 0

// Minimal, async-signal-safe signal handlers
signal(SIGCHLD) { _ in }
signal(SIGTERM) { _ in
    g_shutdownRequested = 1
}
signal(SIGINT) { _ in
    g_shutdownRequested = 1
}

// Initialize the system service supervisor
let supervisor = ServiceSupervisor()

// Register the first-party system diagnostic service if present
let diagPath = "/sbin/arkdiag"
if access(diagPath, X_OK) == 0 {
    let diagService = ServiceDefinition(
        name: "arkdiag",
        executablePath: diagPath,
        arguments: [],
        restartPolicy: .onFailure(maxRestarts: 3, restartDelaySeconds: 2),
        stopTimeoutSeconds: 5
    )
    supervisor.registerService(diagService)
    supervisor.startService(named: "arkdiag")
} else {
    print("[arkrt-swift] Diagnostic service '\(diagPath)' not present on root filesystem.")
    fflush(stdout)
}

var shutdownInitiated = false

// Non-blocking PID 1 supervisor event loop
while true {
    // 1. Non-blocking reaping of any terminated child processes
    supervisor.reapChildren()

    // 2. Timer ticks for scheduled restarts and graceful stop grace periods
    supervisor.tick()

    // 3. Handle shutdown requests cleanly
    if g_shutdownRequested != 0 {
        if !shutdownInitiated {
            shutdownInitiated = true
            print("[arkrt-swift] Termination signal received. Initiating orderly shutdown...")
            fflush(stdout)
            supervisor.stopAllServices()
        }

        if supervisor.areAllServicesStopped {
            print("[arkrt-swift] All managed services stopped cleanly. Halting PID 1.")
            fflush(stdout)
            break
        }
    }

    // 4. Tick interval: 250ms prevents CPU spinning while maintaining responsiveness
    usleep(250000)
}
