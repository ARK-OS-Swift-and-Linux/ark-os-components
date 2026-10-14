import Musl

/// Service supervisor responsible for process launching, monitoring,
/// restart policy enforcement, and orderly shutdown.
public final class ServiceSupervisor {
    private var services: [String: ManagedService] = [:]

    private var currentErrno: Int32 {
        return __errno_location().pointee
    }

    public init() {}

    /// Registers a service definition with the supervisor.
    public func registerService(_ definition: ServiceDefinition) {
        let service = ManagedService(definition: definition)
        services[definition.name] = service
        print("[arkrt-swift] Registered service '\(definition.name)' [path: \(definition.executablePath)]")
        fflush(stdout)
    }

    /// Retrieves the managed service instance by name.
    public func service(named name: String) -> ManagedService? {
        return services[name]
    }

    /// All currently managed services.
    public var allServices: [ManagedService] {
        return Array(services.values)
    }

    /// Loads and registers all declarative '.serve' service definition files from a directory.
    ///
    /// - Parameter dirPath: Path to the directory containing '.serve' files.
    /// - Returns: List of registered service names in alphabetical order.
    @discardableResult
    public func loadServices(fromDirectory dirPath: String) -> [String] {
        guard let dirPtr = opendir(dirPath) else {
            let err = currentErrno
            if err == ENOENT {
                print("[arkrt-swift] Notice: Service directory '\(dirPath)' does not exist.")
            } else {
                print("[arkrt-swift] Warning: Unable to open service directory '\(dirPath)' (errno \(err)).")
            }
            fflush(stdout)
            return []
        }
        defer { closedir(dirPtr) }

        var fileNames: [String] = []
        while let entry = readdir(dirPtr) {
            let nameStr: String = withUnsafeBytes(of: entry.pointee.d_name) { rawBuf in
                guard let base = rawBuf.baseAddress else { return "" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
            if nameStr.hasSuffix(".serve") && !nameStr.hasPrefix(".") {
                fileNames.append(nameStr)
            }
        }

        // Deterministic lexicographical file ordering
        fileNames.sort()

        var loadedNames: [String] = []
        for fileName in fileNames {
            let fullPath = dirPath.hasSuffix("/") ? "\(dirPath)\(fileName)" : "\(dirPath)/\(fileName)"
            do {
                let definition = try ServiceParser.parseFile(atPath: fullPath)
                if services[definition.name] != nil {
                    print("[arkrt-swift] Error: Duplicate service name '\(definition.name)' defined in '\(fullPath)'. Ignoring duplicate.")
                    fflush(stdout)
                    continue
                }
                registerService(definition)
                loadedNames.append(definition.name)
            } catch {
                print("[arkrt-swift] Error: Failed to load service definition from '\(fullPath)': \(error)")
                fflush(stdout)
            }
        }

        return loadedNames
    }

    /// Resolves dependency ordering and cycles for all unstarted (.configured) services.
    ///
    /// Uses Kahn's topological sort algorithm with alphabetical tie-breaking
    /// to guarantee 100% deterministic boot order across all boots.
    ///
    /// - Returns: Deterministic ordered list of service names ready to start, or empty if none.
    public func resolveStartupOrder() -> [String] {
        let eligible = services.values.filter { $0.state == .configured }

        // 1. Validate dependencies against available services and detect self-referential cycles
        var validNames: Set<String> = []
        for service in eligible {
            let name = service.definition.name
            var hasMissingRequirement = false

            for req in service.definition.requires {
                if req == name {
                    service.transitionToFailed(reason: "Self-referential required dependency")
                    print("[arkrt-swift] Error: Service '\(name)' has self-referential requirement on itself.")
                    fflush(stdout)
                    hasMissingRequirement = true
                    break
                }
                if services[req] == nil {
                    service.transitionToFailed(reason: "Missing required dependency: '\(req)'")
                    print("[arkrt-swift] Error: Service '\(name)' requires missing service '\(req)'.")
                    fflush(stdout)
                    hasMissingRequirement = true
                    break
                }
            }

            for aft in service.definition.after {
                if aft == name {
                    service.transitionToFailed(reason: "Self-referential after dependency")
                    print("[arkrt-swift] Error: Service '\(name)' is configured to start after itself.")
                    fflush(stdout)
                    hasMissingRequirement = true
                    break
                }
            }

            if !hasMissingRequirement {
                validNames.insert(name)
            }
        }

        // 2. Build dependency graph: predecessor -> [dependents]
        // An edge U -> V means U must start before V.
        var inDegree: [String: Int] = [:]
        var dependents: [String: [String]] = [:]

        for name in validNames {
            inDegree[name] = 0
            dependents[name] = []
        }

        for name in validNames {
            let def = services[name]!.definition
            var predecessors: Set<String> = []

            for req in def.requires {
                if validNames.contains(req) {
                    predecessors.insert(req)
                }
            }
            for aft in def.after {
                if validNames.contains(aft) {
                    predecessors.insert(aft)
                }
            }

            inDegree[name] = predecessors.count
            for pred in predecessors {
                dependents[pred]?.append(name)
            }
        }

        // 3. Kahn's algorithm with deterministic alphabetical tie-breaking
        var ready: [String] = validNames.filter { inDegree[$0] == 0 }
        ready.sort()

        var ordered: [String] = []

        while !ready.isEmpty {
            let current = ready.removeFirst()
            ordered.append(current)

            if let deps = dependents[current] {
                for dep in deps {
                    guard let currentDeg = inDegree[dep] else { continue }
                    let newDeg = currentDeg - 1
                    inDegree[dep] = newDeg
                    if newDeg == 0 {
                        ready.append(dep)
                        ready.sort() // Alphabetical deterministic tie-breaking
                    }
                }
            }
        }

        // 4. Any valid service not in ordered list is in or blocked by a cycle
        if ordered.count < validNames.count {
            for name in validNames {
                if !ordered.contains(name) {
                    services[name]?.transitionToFailed(reason: "Dependency cycle detected involving '\(name)'")
                    print("[arkrt-swift] Error: Service '\(name)' cannot be started due to a dependency cycle.")
                    fflush(stdout)
                }
            }
        }

        return ordered
    }

    /// Starts all configured services in deterministic dependency order.
    public func startAllServices() {
        let startupOrder = resolveStartupOrder()

        for name in startupOrder {
            guard let service = services[name] else { continue }

            // Ensure none of its hard required dependencies failed
            var blocked = false
            for req in service.definition.requires {
                if let reqService = services[req] {
                    switch reqService.state {
                    case .failed(let reason):
                        service.transitionToFailed(reason: "Required dependency '\(req)' failed (\(reason))")
                        print("[arkrt-swift] Error: Service '\(name)' blocked because required dependency '\(req)' failed.")
                        fflush(stdout)
                        blocked = true
                    case .exited(let code) where code != 0:
                        service.transitionToFailed(reason: "Required dependency '\(req)' exited with status \(code)")
                        print("[arkrt-swift] Error: Service '\(name)' blocked because required dependency '\(req)' failed.")
                        fflush(stdout)
                        blocked = true
                    default:
                        break
                    }
                }
                if blocked { break }
            }

            if !blocked {
                startService(named: name)
            }
        }
    }

    /// Starts a registered service by name.
    @discardableResult
    public func startService(named name: String) -> Bool {
        guard let service = services[name] else {
            print("[arkrt-swift] Error: Cannot start unknown service '\(name)'.")
            fflush(stdout)
            return false
        }

        switch service.state {
        case .running(let pid):
            print("[arkrt-swift] Notice: Service '\(name)' is already running (PID: \(pid)).")
            fflush(stdout)
            return true
        case .starting:
            print("[arkrt-swift] Notice: Service '\(name)' is already starting.")
            fflush(stdout)
            return true
        case .stopping:
            print("[arkrt-swift] Error: Cannot start service '\(name)' while it is stopping.")
            fflush(stdout)
            return false
        case .configured, .exited, .failed, .restarting:
            break
        }

        service.transitionToStarting()
        print("[arkrt-swift] Launching service '\(name)'...")
        fflush(stdout)

        let def = service.definition
        if access(def.executablePath, X_OK) != 0 {
            let err = currentErrno
            let reason = "Executable '\(def.executablePath)' not accessible or not executable (errno \(err))"
            service.transitionToFailed(reason: reason)
            print("[arkrt-swift] Error: Cannot start service '\(name)': \(reason).")
            fflush(stdout)
            return false
        }

        let cArgs: [String] = [def.executablePath] + def.arguments
        var argv: [UnsafeMutablePointer<CChar>?] = cArgs.map { strdup($0) }
        argv.append(nil)

        var envStrings: [String] = []
        if def.environment.isEmpty {
            envStrings = ["PATH=/sbin:/bin:/usr/bin", "TERM=linux", "HOME=/"]
        } else {
            for (k, v) in def.environment {
                envStrings.append("\(k)=\(v)")
            }
        }
        var envp: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) }
        envp.append(nil)

        let pid = fork()
        if pid < 0 {
            let err = currentErrno
            service.transitionToFailed(reason: "fork() failed with errno \(err)")
            print("[arkrt-swift] Error: Failed to fork process for service '\(name)' (errno: \(err)).")
            fflush(stdout)
            cleanupPointers(&argv)
            cleanupPointers(&envp)
            return false
        }

        if pid == 0 {
            // Child process execution path: isolate process group so PGID == PID.
            // If setpgid fails, abort immediately so the child never runs in the supervisor's process group.
            if setpgid(0, 0) < 0 {
                let err = __errno_location().pointee
                let errStr = "[arkrt-child] Fatal: setpgid(0, 0) failed (errno \(err))\n"
                _ = errStr.utf8CString.withUnsafeBufferPointer { buf in
                    write(STDERR_FILENO, buf.baseAddress, buf.count - 1)
                }
                _exit(127)
            }

            _ = argv.withUnsafeMutableBufferPointer { argvBuf in
                envp.withUnsafeMutableBufferPointer { envpBuf in
                    execve(def.executablePath, argvBuf.baseAddress, envpBuf.baseAddress)
                }
            }
            // If execve returns, execution failed
            let err = __errno_location().pointee
            let errStr = "[arkrt-child] Fatal: execve(\(def.executablePath)) failed (errno \(err))\n"
            _ = errStr.utf8CString.withUnsafeBufferPointer { buf in
                write(STDERR_FILENO, buf.baseAddress, buf.count - 1)
            }
            _exit(127)
        }

        // Parent process (PID 1) execution path
        // Synchronize process group assignment to eliminate race with immediate parent signals.
        var childAlreadyTerminated = false
        if setpgid(pid, pid) < 0 {
            let err = currentErrno
            if err == ESRCH {
                // The child process has already exited or failed during exec.
                // Reconcile lifecycle immediately rather than assuming success.
                var status: Int32 = 0
                let reapedPid = waitpid(pid, &status, WNOHANG)
                if reapedPid == pid {
                    childAlreadyTerminated = true
                    let isExited = ((status & 0x7f) == 0)
                    let exitCode = isExited ? ((status >> 8) & 0xff) : nil
                    let termSig = !isExited ? (status & 0x7f) : nil
                    handleChildTermination(service: service, reapedPid: pid, exitCode: exitCode, signal: termSig)
                } else {
                    service.transitionToFailed(reason: "Child process exited before process-group setup completed")
                    childAlreadyTerminated = true
                }
            } else if err == EACCES {
                // EACCES indicates the child already called execve().
                // Verify the child's actual process group rather than blindly assuming it is valid.
                let actualPgid = getpgid(pid)
                if actualPgid != pid && actualPgid > 0 {
                    print("[arkrt-swift] Warning: Service '\(name)' (PID: \(pid)) in unexpected process group \(actualPgid).")
                    fflush(stdout)
                }
            } else {
                print("[arkrt-swift] Error: Failed to synchronize process group for PID \(pid) (errno \(err)).")
                fflush(stdout)
            }
        }

        cleanupPointers(&argv)
        cleanupPointers(&envp)

        if childAlreadyTerminated {
            return false
        }

        if service.isStopRequested {
            service.transitionToStopping(pid: pid)
            deliverSignal(to: pid, signal: SIGTERM)
            print("[arkrt-swift] Service '\(name)' was marked to stop during launch; sent SIGTERM to PGID \(pid).")
            fflush(stdout)
        } else {
            service.transitionToRunning(pid: pid)
            print("[arkrt-swift] Service '\(name)' started successfully (PID: \(pid), PGID: \(pid)).")
            fflush(stdout)
        }
        return true
    }

    /// Reaps all terminated children without blocking.
    public func reapChildren() {
        var status: Int32 = 0
        while true {
            let reapedPid = waitpid(-1, &status, WNOHANG)
            if reapedPid < 0 {
                if currentErrno == EINTR {
                    continue
                }
                break // ECHILD or unrecoverable error
            }
            if reapedPid == 0 {
                break // No child has exited
            }

            // Decode POSIX termination status
            let isExited = ((status & 0x7f) == 0)
            let exitCode = isExited ? ((status >> 8) & 0xff) : nil
            let termSig = !isExited ? (status & 0x7f) : nil

            if let service = findService(byPid: reapedPid) {
                handleChildTermination(service: service, reapedPid: reapedPid, exitCode: exitCode, signal: termSig)
            } else {
                print("[arkrt-swift] Reaped adopted orphaned process (PID: \(reapedPid)).")
                fflush(stdout)
            }
        }
    }

    /// Ticks timers for delayed restarts and stop grace periods.
    public func tick() {
        let now = time(nil)

        for service in services.values {
            switch service.state {
            case .restarting(let attempt, _):
                if now >= service.nextRestartTimestamp {
                    print("[arkrt-swift] Executing scheduled restart for '\(service.definition.name)' (attempt \(attempt))...")
                    fflush(stdout)
                    startService(named: service.definition.name)
                }

            case .stopping(let pid):
                let elapsed = now - service.stopInitiatedTimestamp
                if elapsed >= time_t(service.definition.stopTimeoutSeconds) && !service.hasSentSigkill {
                    service.markSigkillSent()
                    print("[arkrt-swift] Warning: Service '\(service.definition.name)' (PGID: \(pid)) exceeded grace period (\(service.definition.stopTimeoutSeconds)s). Escalating to SIGKILL.")
                    fflush(stdout)
                    deliverSignal(to: pid, signal: SIGKILL)
                }

            case .configured, .starting, .running, .exited, .failed:
                break
            }
        }
    }

    /// Requests graceful shutdown of a named service with SIGTERM.
    public func stopService(named name: String) {
        guard let service = services[name] else { return }

        switch service.state {
        case .running(let pid):
            service.transitionToStopping()
            print("[arkrt-swift] Sending SIGTERM to service '\(name)' (PGID: \(pid))...")
            fflush(stdout)
            deliverSignal(to: pid, signal: SIGTERM)

        case .restarting:
            service.transitionToExited(exitCode: service.lastExitCode ?? 0)
            print("[arkrt-swift] Cancelled pending restart for service '\(name)'.")
            fflush(stdout)

        case .starting:
            service.markStopRequested()
            print("[arkrt-swift] Service '\(name)' is starting; marked for immediate stop upon launch.")
            fflush(stdout)

        case .configured, .exited, .failed, .stopping:
            break
        }

        // Stop any active services that hard-require this service
        for other in services.values {
            guard other.definition.name != name else { continue }
            if other.definition.requires.contains(name) {
                switch other.state {
                case .running, .starting, .restarting:
                    print("[arkrt-swift] Notice: Stopping dependent service '\(other.definition.name)' because required dependency '\(name)' is stopping.")
                    fflush(stdout)
                    stopService(named: other.definition.name)
                default:
                    break
                }
            }
        }
    }

    /// Requests shutdown of all managed services.
    public func stopAllServices() {
        print("[arkrt-swift] Requesting shutdown of all managed services...")
        fflush(stdout)
        for name in services.keys {
            stopService(named: name)
        }
    }

    /// Returns true if all services are completely stopped.
    public var areAllServicesStopped: Bool {
        for service in services.values {
            switch service.state {
            case .starting, .running, .stopping, .restarting:
                return false
            case .configured, .exited, .failed:
                break
            }
        }
        return true
    }

    // MARK: - Private Helpers

    private func findService(byPid pid: pid_t) -> ManagedService? {
        for service in services.values {
            if service.pid == pid {
                return service
            }
        }
        return nil
    }

    private func handleChildTermination(service: ManagedService, reapedPid: pid_t, exitCode: Int32?, signal: Int32?) {
        let name = service.definition.name
        let policy = service.definition.restartPolicy

        switch service.state {
        case .stopping:
            let code = exitCode ?? (128 + (signal ?? 0))
            service.transitionToExited(exitCode: code)
            print("[arkrt-swift] Service '\(name)' stopped cleanly (PID: \(reapedPid), code: \(code)).")
            fflush(stdout)

        case .running, .starting:
            if let code = exitCode {
                if code == 0 {
                    // Clean exit without error
                    if case .always(let maxRestarts, let delay) = policy, service.restartCount < maxRestarts {
                        service.transitionToRestarting(delaySeconds: delay)
                        print("[arkrt-swift] Service '\(name)' exited normally (0). Policy .always restarting (attempt \(service.restartCount)/\(maxRestarts)) in \(delay)s.")
                        fflush(stdout)
                    } else {
                        service.transitionToExited(exitCode: 0)
                        print("[arkrt-swift] Service '\(name)' finished execution and exited normally (0).")
                        fflush(stdout)
                    }
                } else {
                    // Non-zero exit code
                    let shouldRestart = (policy != .never) && (service.restartCount < policy.maxRestarts)
                    if shouldRestart {
                        service.transitionToRestarting(delaySeconds: policy.delaySeconds)
                        print("[arkrt-swift] Service '\(name)' exited with status \(code). Restarting (attempt \(service.restartCount)/\(policy.maxRestarts)) in \(policy.delaySeconds)s.")
                        fflush(stdout)
                    } else {
                        let reason = (service.restartCount >= policy.maxRestarts && policy != .never)
                            ? "Exited with code \(code) (max restarts \(policy.maxRestarts) exceeded)"
                            : "Exited with code \(code)"
                        service.transitionToFailed(reason: reason, exitCode: code)
                        print("[arkrt-swift] Error: Service '\(name)' failed [\(reason)].")
                        fflush(stdout)
                    }
                }
            } else if let sig = signal {
                // Terminated by unexpected signal
                let shouldRestart = (policy != .never) && (service.restartCount < policy.maxRestarts)
                if shouldRestart {
                    service.transitionToRestarting(delaySeconds: policy.delaySeconds)
                    print("[arkrt-swift] Service '\(name)' killed by signal \(sig). Restarting (attempt \(service.restartCount)/\(policy.maxRestarts)) in \(policy.delaySeconds)s.")
                    fflush(stdout)
                } else {
                    let reason = "Terminated by signal \(sig)"
                    service.transitionToFailed(reason: reason, exitCode: 128 + sig)
                    print("[arkrt-swift] Error: Service '\(name)' failed [\(reason)].")
                    fflush(stdout)
                }
            }

        case .configured, .exited, .failed, .restarting:
            break
        }

        if case .failed = service.state {
            for other in services.values {
                guard other.definition.name != name else { continue }
                if other.definition.requires.contains(name) {
                    switch other.state {
                    case .running, .starting, .restarting:
                        print("[arkrt-swift] Notice: Stopping dependent service '\(other.definition.name)' because required dependency '\(name)' failed.")
                        fflush(stdout)
                        stopService(named: other.definition.name)
                    default:
                        break
                    }
                }
            }
        }
    }

    private func cleanupPointers(_ array: inout [UnsafeMutablePointer<CChar>?]) {
        for ptr in array where ptr != nil {
            free(ptr)
        }
        array.removeAll()
    }

    /// Safely delivers a signal to a managed service's isolated process group.
    ///
    /// Architectural Note & Limitations:
    /// Each managed service is launched into its own process group (PGID == PID).
    /// Delivering signals to `-pid` broadcasts to the lead process and all descendants
    /// that remain in the service's process group.
    /// If a descendant process deliberately calls setsid() or setpgid() to detach from
    /// the service process group, POSIX process-group signaling cannot reach it. In ARK-OS,
    /// such orphaned descendants will be adopted by PID 1 upon parent termination and
    /// reaped by `reapChildren()`. Tracking across setsid requires cgroups v2, which is
    /// out of scope for early Stage 1 userspace prior to cgroupfs initialization.
    private func deliverSignal(to pid: pid_t, signal: Int32) {
        // Invariant 1: Strictly reject non-positive PIDs, PID 0, and PID 1 (self).
        // Calling kill(0, sig) signals the supervisor's own process group, kill(-1, sig)
        // signals all processes on the system, and kill(1, sig) targets PID 1 itself.
        guard pid > 1 else {
            print("[arkrt-swift] Error: Refusing to signal invalid or supervisor PID/PGID (\(pid)).")
            fflush(stdout)
            return
        }

        // Deliver signal to the service's verified process group (-pid)
        let ret = kill(-pid, signal)
        if ret < 0 {
            let err = currentErrno
            switch err {
            case ESRCH:
                // ESRCH: The process group is genuinely absent (already exited or reaped).
                // Do not blindly fall back to signaling single PID since ESRCH applies equally.
                break
            case EPERM:
                print("[arkrt-swift] Error: Permission denied delivering signal \(signal) to PGID \(pid).")
                fflush(stdout)
            case EINVAL:
                print("[arkrt-swift] Error: Invalid signal \(signal) specified for PGID \(pid).")
                fflush(stdout)
            default:
                print("[arkrt-swift] Error: kill(-\(pid), \(signal)) failed with errno \(err).")
                fflush(stdout)
            }
        }
    }
}
