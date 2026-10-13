import Musl

/// Distinct states of the service lifecycle.
public enum ServiceState: Equatable, CustomStringConvertible {
    case configured
    case starting
    case running(pid: pid_t)
    case exited(exitCode: Int32)
    case failed(reason: String)
    case restarting(attempt: Int, nextAttemptInSeconds: Int)
    case stopping(pid: pid_t)

    public var description: String {
        switch self {
        case .configured:
            return "configured"
        case .starting:
            return "starting"
        case .running(let pid):
            return "running(pid: \(pid))"
        case .exited(let code):
            return "exited(code: \(code))"
        case .failed(let reason):
            return "failed(\(reason))"
        case .restarting(let attempt, let delay):
            return "restarting(attempt: \(attempt), delay: \(delay)s)"
        case .stopping(let pid):
            return "stopping(pid: \(pid))"
        }
    }
}

/// Restart policy configuration for managed services.
public enum ServiceRestartPolicy: Equatable {
    case never
    case always(maxRestarts: Int, restartDelaySeconds: Int)
    case onFailure(maxRestarts: Int, restartDelaySeconds: Int)

    public var maxRestarts: Int {
        switch self {
        case .never:
            return 0
        case .always(let max, _):
            return max
        case .onFailure(let max, _):
            return max
        }
    }

    public var delaySeconds: Int {
        switch self {
        case .never:
            return 0
        case .always(_, let delay):
            return delay
        case .onFailure(_, let delay):
            return delay
        }
    }
}

/// Immutable definition of a system service.
public struct ServiceDefinition: Equatable {
    public let name: String
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]
    public let restartPolicy: ServiceRestartPolicy
    public let stopTimeoutSeconds: Int

    public init(
        name: String,
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        restartPolicy: ServiceRestartPolicy = .never,
        stopTimeoutSeconds: Int = 5
    ) {
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.restartPolicy = restartPolicy
        self.stopTimeoutSeconds = stopTimeoutSeconds
    }
}

/// Runtime instance tracking a managed service through its lifecycle.
public final class ManagedService {
    public let definition: ServiceDefinition
    public private(set) var state: ServiceState = .configured
    public private(set) var restartCount: Int = 0
    public private(set) var pid: pid_t? = nil
    public private(set) var lastExitCode: Int32? = nil
    public private(set) var nextRestartTimestamp: time_t = 0
    public private(set) var stopInitiatedTimestamp: time_t = 0
    public private(set) var isStopRequested: Bool = false
    public private(set) var hasSentSigkill: Bool = false

    public init(definition: ServiceDefinition) {
        self.definition = definition
        self.state = .configured
    }

    public func transitionToStarting() {
        self.isStopRequested = false
        self.hasSentSigkill = false
        self.state = .starting
    }

    public func markStopRequested() {
        self.isStopRequested = true
    }

    public func transitionToRunning(pid: pid_t) {
        self.pid = pid
        self.state = .running(pid: pid)
    }

    public func transitionToStopping(pid: pid_t? = nil) {
        let targetPid = pid ?? self.pid
        if let currentPid = targetPid {
            self.pid = currentPid
            self.state = .stopping(pid: currentPid)
            self.stopInitiatedTimestamp = time(nil)
            self.hasSentSigkill = false
        }
    }

    public func markSigkillSent() {
        self.hasSentSigkill = true
    }

    public func transitionToExited(exitCode: Int32) {
        self.pid = nil
        self.isStopRequested = false
        self.hasSentSigkill = false
        self.lastExitCode = exitCode
        self.state = .exited(exitCode: exitCode)
    }

    public func transitionToFailed(reason: String, exitCode: Int32? = nil) {
        self.pid = nil
        self.isStopRequested = false
        self.hasSentSigkill = false
        if let code = exitCode {
            self.lastExitCode = code
        }
        self.state = .failed(reason: reason)
    }

    public func transitionToRestarting(delaySeconds: Int) {
        self.pid = nil
        self.isStopRequested = false
        self.hasSentSigkill = false
        self.restartCount += 1
        self.nextRestartTimestamp = time(nil) + time_t(delaySeconds)
        self.state = .restarting(attempt: self.restartCount, nextAttemptInSeconds: delaySeconds)
    }

    public func resetRestarts() {
        self.restartCount = 0
    }
}
