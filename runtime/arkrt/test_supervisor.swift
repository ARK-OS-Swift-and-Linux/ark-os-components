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

        print("[TEST SUCCESS] All Service Supervisor unit/integration tests passed!")
    }
}
