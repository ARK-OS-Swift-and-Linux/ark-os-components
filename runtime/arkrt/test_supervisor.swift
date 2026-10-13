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

        print("[TEST SUCCESS] All Service Supervisor unit/integration tests passed!")
    }
}
