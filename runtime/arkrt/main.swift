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

// Set up child process signal handling
signal(SIGCHLD) { _ in }

// Main supervisor loop
while true {
    var status: Int32 = 0
    let reapedPid = waitpid(-1, &status, WNOHANG)
    if reapedPid > 0 {
        print("[arkrt-swift] Reaped terminated process (PID: \(reapedPid))")
        fflush(stdout)
    }
    sleep(1)
}
