import Musl

@main
struct SupervisorTests {
    static func assertCondition(_ condition: Bool, _ message: String) {
        if !condition {
            print("[TEST FAILED] \(message)")
            exit(1)
        }
    }

    static func main() {
        if CommandLine.arguments.contains("--stubborn-child") {
            arkrt_ignore_sigterm()
            while true {
                pause()
            }
        }

        setbuf(stdout, nil)
        setbuf(stderr, nil)

        print("[TEST] Running Service Supervisor test harness...")

        let supervisor = ServiceSupervisor()

        // Test 1: Service Registration
        let testService1 = ServiceDefinition(
            name: "true-service",
            executablePath: "/bin/true",
            arguments: [],
            restartPolicy: .never,
            stopTimeoutSeconds: 2
        )
        supervisor.registerService(testService1)

        guard let s1 = supervisor.service(named: "true-service") else {
            print("[TEST FAILED] Service not found after registration")
            exit(1)
        }
        assertCondition(s1.state == .configured, "Service should initially be in .configured state")
        print("[TEST PASSED] Test 1: Registration and initial state")

        // Test 2: Successful execution and normal exit (code 0)
        let startOk = supervisor.startService(named: "true-service")
        assertCondition(startOk, "startService should succeed")

        // Wait for child to exit and reap
        var reaped = false
        for _ in 0..<20 {
            supervisor.reapChildren()
            if case .exited(let code) = s1.state {
                assertCondition(code == 0, "Expected exit code 0")
                reaped = true
                break
            }
            usleep(50000)
        }
        assertCondition(reaped, "Service should transition to .exited(0)")
        print("[TEST PASSED] Test 2: Normal execution and exit status tracking")

        // Test 3: Failure and Restart Policy enforcement (.onFailure, maxRestarts: 2)
        let failService = ServiceDefinition(
            name: "fail-service",
            executablePath: "/bin/false",
            arguments: [],
            restartPolicy: .onFailure(maxRestarts: 2, restartDelaySeconds: 1),
            stopTimeoutSeconds: 2
        )
        supervisor.registerService(failService)
        guard let sFail = supervisor.service(named: "fail-service") else {
            exit(1)
        }

        supervisor.startService(named: "fail-service")

        // First failure: should transition to .restarting(attempt: 1)
        var sawRestart1 = false
        for _ in 0..<20 {
            supervisor.reapChildren()
            if case .restarting(let attempt, _) = sFail.state, attempt == 1 {
                sawRestart1 = true
                break
            }
            usleep(50000)
        }
        assertCondition(sawRestart1, "Service should transition to .restarting(attempt: 1)")

        // Advance timer / wait for scheduled restart
        sleep(2)
        supervisor.tick()
        assertCondition(sFail.pid != nil, "Service should have restarted and received a PID")

        // Second failure: should transition to .restarting(attempt: 2)
        var sawRestart2 = false
        for _ in 0..<20 {
            supervisor.reapChildren()
            if case .restarting(let attempt, _) = sFail.state, attempt == 2 {
                sawRestart2 = true
                break
            }
            usleep(50000)
        }
        assertCondition(sawRestart2, "Service should transition to .restarting(attempt: 2)")

        // Advance timer / wait for scheduled restart
        sleep(2)
        supervisor.tick()

        // Third failure: maxRestarts exceeded -> should transition to .failed
        var sawFailed = false
        for _ in 0..<20 {
            supervisor.reapChildren()
            if case .failed = sFail.state {
                sawFailed = true
                break
            }
            usleep(50000)
        }
        assertCondition(sawFailed, "Service should transition to .failed when max restarts are exceeded")
        print("[TEST PASSED] Test 3: Failure detection and restart limit enforcement")

        // Test 4: Graceful stop via SIGTERM
        let sleepService = ServiceDefinition(
            name: "sleep-service",
            executablePath: "/bin/sleep",
            arguments: ["30"],
            restartPolicy: .never,
            stopTimeoutSeconds: 2
        )
        supervisor.registerService(sleepService)
        guard let sSleep = supervisor.service(named: "sleep-service") else {
            exit(1)
        }

        supervisor.startService(named: "sleep-service")
        assertCondition(sSleep.pid != nil, "Sleep service should be running")

        supervisor.stopService(named: "sleep-service")
        if case .stopping = sSleep.state {
            // Expected intermediate state
        } else {
            print("[TEST FAILED] Expected .stopping state")
            exit(1)
        }

        var sawStopped = false
        for _ in 0..<20 {
            supervisor.reapChildren()
            if case .exited = sSleep.state {
                sawStopped = true
                break
            }
            usleep(50000)
        }
        assertCondition(sawStopped, "Sleep service should terminate and transition to .exited")
        print("[TEST PASSED] Test 4: Graceful shutdown with SIGTERM and child reaping")

        // Test 5: Immediate stop right after start
        let quickService = ServiceDefinition(
            name: "quick-service",
            executablePath: "/bin/sleep",
            arguments: ["60"],
            restartPolicy: .never,
            stopTimeoutSeconds: 2
        )
        supervisor.registerService(quickService)
        guard let sQuick = supervisor.service(named: "quick-service") else {
            exit(1)
        }

        supervisor.startService(named: "quick-service")
        supervisor.stopService(named: "quick-service")
        assertCondition(sQuick.state == .stopping(pid: sQuick.pid ?? 0), "Expected .stopping state")

        var sawQuickStopped = false
        for _ in 0..<20 {
            supervisor.reapChildren()
            if case .exited = sQuick.state {
                sawQuickStopped = true
                break
            }
            usleep(50000)
        }
        assertCondition(sawQuickStopped, "Service should terminate cleanly after stop")
        print("[TEST PASSED] Test 5: Immediate stop handling verified")

        // Test 6: Policy .always restarts clean exits up to limit
        let alwaysDef = ServiceDefinition(
            name: "always-service",
            executablePath: "/bin/true",
            arguments: [],
            restartPolicy: .always(maxRestarts: 2, restartDelaySeconds: 1),
            stopTimeoutSeconds: 2
        )
        supervisor.registerService(alwaysDef)
        guard let sAlways = supervisor.service(named: "always-service") else {
            exit(1)
        }

        supervisor.startService(named: "always-service")
        assertCondition(sAlways.pid != nil, "Service should start with a valid PID")

        // First exit (code 0) -> should transition to .restarting(attempt: 1)
        var sawAlwaysRestart1 = false
        for _ in 0..<20 {
            supervisor.reapChildren()
            if case .restarting(let attempt, _) = sAlways.state, attempt == 1 {
                sawAlwaysRestart1 = true
                break
            }
            usleep(50000)
        }
        assertCondition(sawAlwaysRestart1, "Service should transition to .restarting(attempt: 1) after clean exit")
        assertCondition(sAlways.restartCount == 1, "restartCount should be 1")

        // Advance timer for first restart
        sleep(2)
        supervisor.tick()
        assertCondition(sAlways.pid != nil, "Service should have restarted (attempt 1) with new PID")

        // Second exit (code 0) -> should transition to .restarting(attempt: 2)
        var sawAlwaysRestart2 = false
        for _ in 0..<20 {
            supervisor.reapChildren()
            if case .restarting(let attempt, _) = sAlways.state, attempt == 2 {
                sawAlwaysRestart2 = true
                break
            }
            usleep(50000)
        }
        assertCondition(sawAlwaysRestart2, "Service should transition to .restarting(attempt: 2) after second clean exit")
        assertCondition(sAlways.restartCount == 2, "restartCount should be 2")

        // Advance timer for second restart
        sleep(2)
        supervisor.tick()
        assertCondition(sAlways.pid != nil, "Service should have restarted (attempt 2) with new PID")

        // Third exit (code 0) -> maxRestarts (2) exhausted -> should transition to .exited(0)
        var sawAlwaysExited = false
        for _ in 0..<20 {
            supervisor.reapChildren()
            if case .exited(let code) = sAlways.state, code == 0 {
                sawAlwaysExited = true
                break
            }
            usleep(50000)
        }
        assertCondition(sawAlwaysExited, "Service should reach terminal .exited(0) after exhausting restart limit")
        assertCondition(sAlways.restartCount == 2, "Final restartCount must match configured limit (2)")
        print("[TEST PASSED] Test 6: Policy .always restarts clean exits and exhausts limit")

        // Test 7: SIGKILL escalation for uncooperative processes
        let myExe = CommandLine.arguments.first ?? "./test_supervisor"
        let stubbornDef = ServiceDefinition(
            name: "stubborn-service",
            executablePath: myExe,
            arguments: ["--stubborn-child"],
            restartPolicy: .never,
            stopTimeoutSeconds: 1
        )
        supervisor.registerService(stubbornDef)
        guard let sStubborn = supervisor.service(named: "stubborn-service") else {
            exit(1)
        }

        var cleanupTargetPid: pid_t? = nil
        defer {
            // Guardrail: Ensure uncooperative test process is reaped even if an assertion fails
            if let pidToClean = cleanupTargetPid {
                kill(-pidToClean, SIGKILL)
                kill(pidToClean, SIGKILL)
                var status: Int32 = 0
                waitpid(pidToClean, &status, WNOHANG)
            }
        }

        supervisor.startService(named: "stubborn-service")
        guard let targetPid = sStubborn.pid else {
            print("[TEST FAILED] Stubborn service failed to start")
            exit(1)
        }
        cleanupTargetPid = targetPid

        // Verify the actual PID and process group arrangement
        let actualPgid = getpgid(targetPid)
        assertCondition(actualPgid == targetPid, "Verified process group (PGID: \(actualPgid)) must equal PID (\(targetPid))")

        // Allow child process to finish execve and install SIG_IGN
        usleep(100000) // 100ms

        // Request shutdown with SIGTERM
        supervisor.stopService(named: "stubborn-service")
        assertCondition(sStubborn.state == .stopping(pid: targetPid), "Expected .stopping state")

        // Verify the process ignored SIGTERM and remains alive
        usleep(100000) // 100ms
        assertCondition(kill(targetPid, 0) == 0, "Stubborn process must remain alive after SIGTERM")
        assertCondition(!sStubborn.hasSentSigkill, "SIGKILL should not be sent prior to grace period expiry")

        // Wait for grace period (1s) to expire
        sleep(2)

        // Trigger tick to escalate to SIGKILL
        supervisor.tick()
        assertCondition(sStubborn.hasSentSigkill, "Supervisor must record that SIGKILL was dispatched")

        // Reap the killed process
        var sawKillReaped = false
        for _ in 0..<30 {
            supervisor.reapChildren()
            if case .exited(let code) = sStubborn.state {
                // Signal 9 (SIGKILL) exit status is typically 128 + 9 = 137
                assertCondition(code == 137, "Expected termination exit code 137 (SIGKILL), got \(code)")
                sawKillReaped = true
                break
            }
            usleep(50000)
        }
        assertCondition(sawKillReaped, "Service should be reaped and transition to .exited after SIGKILL escalation")
        cleanupTargetPid = nil // Process has been cleanly reaped

        print("[TEST PASSED] Test 7: SIGKILL escalation for uncooperative processes")

        // Test 8: Valid .serve parsing, comments, whitespace, and defaults
        let validServeContent = """
        # This is a comment
        ; Another comment style

        name = diag_svc
        exec = /bin/true
        restart = on-failure
        max_restarts = 5
        restart_delay = 3
        stop_timeout = 10
        after = svc_a, svc_b
        requires = svc_c svc_d
        """
        do {
            let def = try ServiceParser.parse(content: validServeContent)
            assertCondition(def.name == "diag_svc", "Name must match")
            assertCondition(def.executablePath == "/bin/true", "Exec path must match")
            assertCondition(def.restartPolicy == .onFailure(maxRestarts: 5, restartDelaySeconds: 3), "Policy must match")
            assertCondition(def.stopTimeoutSeconds == 10, "Stop timeout must match")
            assertCondition(def.after == ["svc_a", "svc_b"], "After list must match: got \(def.after)")
            assertCondition(def.requires == ["svc_c", "svc_d"], "Requires list must match: got \(def.requires)")
        } catch {
            print("[TEST FAILED] Unexpected error parsing valid content: \(error)")
            exit(1)
        }

        // Test defaults
        let minimalContent = """
        name=minimal
        exec=/bin/true
        """
        do {
            let def = try ServiceParser.parse(content: minimalContent)
            assertCondition(def.name == "minimal", "Name must match")
            assertCondition(def.executablePath == "/bin/true", "Exec path must match")
            assertCondition(def.restartPolicy == .never, "Default policy must be .never")
            assertCondition(def.stopTimeoutSeconds == 5, "Default stop timeout must be 5")
            assertCondition(def.after.isEmpty, "Default after list must be empty")
            assertCondition(def.requires.isEmpty, "Default requires list must be empty")
        } catch {
            print("[TEST FAILED] Unexpected error parsing minimal content: \(error)")
            exit(1)
        }
        print("[TEST PASSED] Test 8: Valid .serve parsing, comments, whitespace, and defaults")

        // Test 9: Malformed syntax and invalid configurations
        // 9a. Line without '='
        do {
            _ = try ServiceParser.parse(content: "invalid_line_without_equal")
            print("[TEST FAILED] Expected malformedLine error")
            exit(1)
        } catch ServiceParseError.malformedLine {
            // Expected
        } catch {
            print("[TEST FAILED] Wrong error for missing equal sign: \(error)")
            exit(1)
        }

        // 9b. Duplicate key
        do {
            _ = try ServiceParser.parse(content: "name=foo\nexec=/bin/true\nname=bar")
            print("[TEST FAILED] Expected duplicateKey error")
            exit(1)
        } catch ServiceParseError.duplicateKey {
            // Expected
        } catch {
            print("[TEST FAILED] Wrong error for duplicate key: \(error)")
            exit(1)
        }

        // 9c. Unknown key
        do {
            _ = try ServiceParser.parse(content: "name=foo\nexec=/bin/true\nunknown_key=123")
            print("[TEST FAILED] Expected unknownKey error")
            exit(1)
        } catch ServiceParseError.unknownKey {
            // Expected
        } catch {
            print("[TEST FAILED] Wrong error for unknown key: \(error)")
            exit(1)
        }

        // 9d. Missing required fields
        do {
            _ = try ServiceParser.parse(content: "exec=/bin/true")
            print("[TEST FAILED] Expected missingRequiredField error for name")
            exit(1)
        } catch ServiceParseError.missingRequiredField(let field) where field == "name" {
            // Expected
        } catch {
            print("[TEST FAILED] Wrong error for missing name: \(error)")
            exit(1)
        }

        do {
            _ = try ServiceParser.parse(content: "name=foo")
            print("[TEST FAILED] Expected missingRequiredField error for exec")
            exit(1)
        } catch ServiceParseError.missingRequiredField(let field) where field == "exec" {
            // Expected
        } catch {
            print("[TEST FAILED] Wrong error for missing exec: \(error)")
            exit(1)
        }

        // 9e. Relative executable path
        do {
            _ = try ServiceParser.parse(content: "name=foo\nexec=bin/true")
            print("[TEST FAILED] Expected invalidExecutablePath error")
            exit(1)
        } catch ServiceParseError.invalidExecutablePath {
            // Expected
        } catch {
            print("[TEST FAILED] Wrong error for relative executable path: \(error)")
            exit(1)
        }

        // 9f. Invalid restart policy
        do {
            _ = try ServiceParser.parse(content: "name=foo\nexec=/bin/true\nrestart=maybe")
            print("[TEST FAILED] Expected invalidRestartPolicy error")
            exit(1)
        } catch ServiceParseError.invalidRestartPolicy {
            // Expected
        } catch {
            print("[TEST FAILED] Wrong error for invalid restart policy: \(error)")
            exit(1)
        }

        // 9g. Out of bounds numeric values
        do {
            _ = try ServiceParser.parse(content: "name=foo\nexec=/bin/true\nmax_restarts=101")
            print("[TEST FAILED] Expected invalidNumericValue for max_restarts > 100")
            exit(1)
        } catch ServiceParseError.invalidNumericValue {
            // Expected
        } catch {
            print("[TEST FAILED] Wrong error for out-of-bounds max_restarts: \(error)")
            exit(1)
        }

        do {
            _ = try ServiceParser.parse(content: "name=foo\nexec=/bin/true\nstop_timeout=0")
            print("[TEST FAILED] Expected invalidNumericValue for stop_timeout < 1")
            exit(1)
        } catch ServiceParseError.invalidNumericValue {
            // Expected
        } catch {
            print("[TEST FAILED] Wrong error for stop_timeout 0: \(error)")
            exit(1)
        }
        print("[TEST PASSED] Test 9: Syntax validation and error rejection")

        // Test 10: Deterministic topological dependency ordering
        let supOrdering = ServiceSupervisor()
        let defC = ServiceDefinition(name: "service_c", executablePath: "/bin/true", after: ["service_b"])
        let defB = ServiceDefinition(name: "service_b", executablePath: "/bin/true", after: ["service_a"])
        let defA = ServiceDefinition(name: "service_a", executablePath: "/bin/true")
        let defE = ServiceDefinition(name: "service_e", executablePath: "/bin/true")
        let defD = ServiceDefinition(name: "service_d", executablePath: "/bin/true")

        supOrdering.registerService(defC)
        supOrdering.registerService(defB)
        supOrdering.registerService(defA)
        supOrdering.registerService(defE)
        supOrdering.registerService(defD)

        let startupOrder = supOrdering.resolveStartupOrder()
        let expectedOrder = ["service_a", "service_b", "service_c", "service_d", "service_e"]
        assertCondition(startupOrder == expectedOrder, "Expected deterministic startup order \(expectedOrder), got \(startupOrder)")
        print("[TEST PASSED] Test 10: Deterministic topological dependency ordering")

        // Test 11: after versus requires semantics
        let supSemantics = ServiceSupervisor()
        // 11a: 'after' with nonexistent service is non-fatal: service still starts
        let defAfterNonexistent = ServiceDefinition(
            name: "after_nonexistent",
            executablePath: "/bin/true",
            after: ["nonexistent_svc"]
        )
        supSemantics.registerService(defAfterNonexistent)
        let orderAfter = supSemantics.resolveStartupOrder()
        assertCondition(orderAfter.contains("after_nonexistent"), "Service with after=nonexistent must start")
        assertCondition(supSemantics.service(named: "after_nonexistent")?.state == .configured, "Must remain .configured before start")

        // 11b: 'requires' with nonexistent service fails validation immediately
        let defRequiresNonexistent = ServiceDefinition(
            name: "requires_nonexistent",
            executablePath: "/bin/true",
            requires: ["absent_dependency"]
        )
        supSemantics.registerService(defRequiresNonexistent)
        let orderReq = supSemantics.resolveStartupOrder()
        assertCondition(!orderReq.contains("requires_nonexistent"), "Service requiring missing dependency must not be in startup order")
        guard let sReqMissing = supSemantics.service(named: "requires_nonexistent") else { exit(1) }
        if case .failed(let reason) = sReqMissing.state {
            assertCondition(reason.contains("Missing required dependency"), "Failure reason must note missing dependency: \(reason)")
        } else {
            print("[TEST FAILED] Expected .failed state for missing requirement, got \(sReqMissing.state)")
            exit(1)
        }

        // 11c: 'requires' with a dependency that fails to start blocks dependent
        let supCascade = ServiceSupervisor()
        let defBaseFails = ServiceDefinition(name: "base_fails", executablePath: "/nonexistent/binary/path")
        let defDep = ServiceDefinition(name: "dependent_on_failed", executablePath: "/bin/true", requires: ["base_fails"])
        supCascade.registerService(defBaseFails)
        supCascade.registerService(defDep)
        supCascade.startAllServices()

        guard let sBase = supCascade.service(named: "base_fails"),
              let sDep = supCascade.service(named: "dependent_on_failed") else { exit(1) }
        assertCondition(sBase.state != .running(pid: sBase.pid ?? 0), "base_fails must not be running")
        if case .failed = sDep.state {
            // Expected
        } else {
            print("[TEST FAILED] Expected dependent service to be in .failed state, got \(sDep.state)")
            exit(1)
        }
        print("[TEST PASSED] Test 11: after versus requires semantics verified")

        // Test 12: Dependency cycle detection and isolation
        let supCycle = ServiceSupervisor()
        let defCyc1 = ServiceDefinition(name: "cyc_1", executablePath: "/bin/true", requires: ["cyc_2"])
        let defCyc2 = ServiceDefinition(name: "cyc_2", executablePath: "/bin/true", requires: ["cyc_1"])
        let defIndep = ServiceDefinition(name: "indep", executablePath: "/bin/true")

        supCycle.registerService(defCyc1)
        supCycle.registerService(defCyc2)
        supCycle.registerService(defIndep)

        let cycleOrder = supCycle.resolveStartupOrder()
        assertCondition(cycleOrder == ["indep"], "Only independent service must be in startup order, got \(cycleOrder)")

        guard let sCyc1 = supCycle.service(named: "cyc_1"),
              let sCyc2 = supCycle.service(named: "cyc_2"),
              let sIndep = supCycle.service(named: "indep") else { exit(1) }

        if case .failed(let reason) = sCyc1.state {
            assertCondition(reason.contains("cycle"), "Must indicate dependency cycle: \(reason)")
        } else {
            print("[TEST FAILED] cyc_1 should be in .failed state, got \(sCyc1.state)")
            exit(1)
        }
        if case .failed(let reason) = sCyc2.state {
            assertCondition(reason.contains("cycle"), "Must indicate dependency cycle: \(reason)")
        } else {
            print("[TEST FAILED] cyc_2 should be in .failed state, got \(sCyc2.state)")
            exit(1)
        }
        assertCondition(sIndep.state == .configured, "Independent service must remain configured and startable")

        // Self-cycle
        let supSelf = ServiceSupervisor()
        let defSelf = ServiceDefinition(name: "self_cyc", executablePath: "/bin/true", requires: ["self_cyc"])
        supSelf.registerService(defSelf)
        let selfOrder = supSelf.resolveStartupOrder()
        assertCondition(selfOrder.isEmpty, "Self-cycle service must not be in startup order")
        guard let sSelf = supSelf.service(named: "self_cyc") else { exit(1) }
        assertCondition(sSelf.state != .configured, "Self-cycle must transition to failed")
        print("[TEST PASSED] Test 12: Dependency cycle detection and isolation")

        // Test 13: Directory scanning resilience (loadServices)
        var template = [CChar]("/tmp/ark_serve_test_XXXXXX".utf8CString)
        guard let tmpDirPtr = mkdtemp(&template) else {
            print("[TEST FAILED] mkdtemp failed")
            exit(1)
        }
        let tmpDir = String(cString: tmpDirPtr)

        func writeTestFile(_ name: String, _ content: String) {
            let path = "\(tmpDir)/\(name)"
            guard let fp = fopen(path, "wb") else { return }
            defer { fclose(fp) }
            _ = content.utf8CString.withUnsafeBufferPointer { buf in
                fwrite(buf.baseAddress, 1, buf.count - 1, fp)
            }
        }

        writeTestFile("10-svc_a.serve", "name=svc_a\nexec=/bin/true\nrestart=never\n")
        writeTestFile("20-svc_b.serve", "name=svc_b\nexec=/bin/true\nafter=svc_a\n")
        writeTestFile("99-malformed.serve", "this is not valid\n")
        writeTestFile("ignore.txt", "name=ignored\nexec=/bin/true\n")
        writeTestFile("duplicate.serve", "name=svc_a\nexec=/bin/true\n")

        let supDir = ServiceSupervisor()
        let loaded = supDir.loadServices(fromDirectory: tmpDir)

        assertCondition(loaded == ["svc_a", "svc_b"], "Expected ['svc_a', 'svc_b'] loaded, got \(loaded)")
        assertCondition(supDir.service(named: "svc_a") != nil, "svc_a should be registered")
        assertCondition(supDir.service(named: "svc_b") != nil, "svc_b should be registered")
        assertCondition(supDir.service(named: "ignored") == nil, "non-.serve file must be ignored")

        // Cleanup temp directory
        unlink("\(tmpDir)/10-svc_a.serve")
        unlink("\(tmpDir)/20-svc_b.serve")
        unlink("\(tmpDir)/99-malformed.serve")
        unlink("\(tmpDir)/ignore.txt")
        unlink("\(tmpDir)/duplicate.serve")
        rmdir(tmpDir)

        print("[TEST PASSED] Test 13: Directory scanning resilience and duplicate handling")

        // Test 14: Cascading stop when a required dependency is stopped
        let supCascadeStop = ServiceSupervisor()
        let defBaseSleep = ServiceDefinition(
            name: "base_sleep",
            executablePath: "/bin/sleep",
            arguments: ["30"],
            restartPolicy: .never,
            stopTimeoutSeconds: 2
        )
        let defDepSleep = ServiceDefinition(
            name: "dep_sleep",
            executablePath: "/bin/sleep",
            arguments: ["30"],
            restartPolicy: .never,
            stopTimeoutSeconds: 2,
            requires: ["base_sleep"]
        )

        supCascadeStop.registerService(defBaseSleep)
        supCascadeStop.registerService(defDepSleep)
        supCascadeStop.startAllServices()

        guard let sBaseSleep = supCascadeStop.service(named: "base_sleep"),
              let sDepSleep = supCascadeStop.service(named: "dep_sleep") else { exit(1) }

        assertCondition(sBaseSleep.pid != nil, "base_sleep must be running")
        assertCondition(sDepSleep.pid != nil, "dep_sleep must be running")

        // Stop base_sleep -> dep_sleep should also be stopped
        supCascadeStop.stopService(named: "base_sleep")

        if case .stopping = sBaseSleep.state {} else {
            print("[TEST FAILED] Expected base_sleep in stopping state")
            exit(1)
        }
        if case .stopping = sDepSleep.state {} else {
            print("[TEST FAILED] Expected dep_sleep in stopping state due to cascade")
            exit(1)
        }

        // Reap both
        for _ in 0..<20 {
            supCascadeStop.reapChildren()
            if case .exited = sBaseSleep.state, case .exited = sDepSleep.state {
                break
            }
            usleep(50000)
        }
        assertCondition(sBaseSleep.state != .running(pid: sBaseSleep.pid ?? 0), "base_sleep must have exited")
        assertCondition(sDepSleep.state != .running(pid: sDepSleep.pid ?? 0), "dep_sleep must have exited")
        print("[TEST PASSED] Test 14: Cascading stop of dependent services")

        print("[TEST SUCCESS] All Service Supervisor unit/integration tests passed!")
    }
}
