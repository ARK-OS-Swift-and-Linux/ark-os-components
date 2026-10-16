#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#endif
import CSignals

// Unbuffer stdout and stderr for immediate console diagnostic output
setbuf(stdout, nil)
setbuf(stderr, nil)

let myPid = getpid()
print("[arkdiag] ARK-OS System Diagnostic Service active (PID: \(myPid))")
fflush(stdout)

// Initialize async-signal-safe POSIX signal handlers in pure C
arkrt_init_signals()

func stripWhitespace(_ str: String) -> String {
    var s = str
    while s.first?.isWhitespace == true || s.first?.isNewline == true {
        s.removeFirst()
    }
    while s.last?.isWhitespace == true || s.last?.isNewline == true {
        s.removeLast()
    }
    return s
}

func readFirstLine(_ path: String) -> String? {
    guard let fp = fopen(path, "r") else { return nil }
    defer { fclose(fp) }
    var buffer = [CChar](repeating: 0, count: 512)
    if fgets(&buffer, Int32(buffer.count), fp) != nil {
        return stripWhitespace(String(cString: buffer))
    }
    return nil
}

func getMemorySummary() -> String {
    guard let fp = fopen("/proc/meminfo", "r") else { return "meminfo: N/A" }
    defer { fclose(fp) }

    var total = "N/A"
    var available = "N/A"
    var buffer = [CChar](repeating: 0, count: 256)

    while fgets(&buffer, Int32(buffer.count), fp) != nil {
        let line = String(cString: buffer)
        if line.hasPrefix("MemTotal:") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count > 1 {
                total = stripWhitespace(String(parts[1]))
            }
        } else if line.hasPrefix("MemAvailable:") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count > 1 {
                available = stripWhitespace(String(parts[1]))
            }
        }
    }
    return "Total: \(total), Avail: \(available)"
}

// Parse command line arguments for testability
var failAfterHeartbeats: Int? = nil
var oneshotMode = false

let args = CommandLine.arguments
for i in 1..<args.count {
    if args[i] == "--fail-after" && i + 1 < args.count {
        failAfterHeartbeats = Int(args[i + 1])
    } else if args[i] == "--oneshot" {
        oneshotMode = true
    }
}

var heartbeatCount = 0

// Main diagnostic monitoring loop
while arkrt_is_shutdown_requested() == 0 {
    heartbeatCount += 1

    let uptime = readFirstLine("/proc/uptime")?.split(separator: " ").first.map(String.init) ?? "unknown"
    let loadavg = readFirstLine("/proc/loadavg") ?? "unknown"
    let memSummary = getMemorySummary()

    print("[arkdiag] Heartbeat #\(heartbeatCount): Uptime: \(uptime)s | Load: \(loadavg) | Mem: [\(memSummary)] | Status: OK")
    fflush(stdout)

    if oneshotMode {
        print("[arkdiag] Oneshot diagnostic complete. Exiting cleanly.")
        fflush(stdout)
        exit(0)
    }

    if let max = failAfterHeartbeats, heartbeatCount >= max {
        print("[arkdiag] Diagnostic deliberate failure triggered after \(heartbeatCount) heartbeats (exit code: 42).")
        fflush(stdout)
        exit(42)
    }

    // Sleep for 2 seconds in small increments to respond quickly to signals
    for _ in 0..<20 {
        if arkrt_is_shutdown_requested() != 0 {
            break
        }
        usleep(100000) // 100ms
    }
}

print("[arkdiag] Termination signal received. Performing clean shutdown...")
print("[arkdiag] Diagnostic monitors released. Exiting cleanly (code: 0).")
fflush(stdout)
exit(0)
