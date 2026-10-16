#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#endif
import CSignals

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
    public let after: [String]
    public let requires: [String]

    public init(
        name: String,
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        restartPolicy: ServiceRestartPolicy = .never,
        stopTimeoutSeconds: Int = 5,
        after: [String] = [],
        requires: [String] = []
    ) {
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.restartPolicy = restartPolicy
        self.stopTimeoutSeconds = stopTimeoutSeconds
        self.after = after
        self.requires = requires
    }
}

/// Errors occurring during declarative service definition parsing and validation.
public enum ServiceParseError: Error, Equatable, CustomStringConvertible {
    case fileNotFound(path: String)
    case unreadableFile(path: String)
    case malformedLine(line: Int, content: String)
    case duplicateKey(line: Int, key: String)
    case unknownKey(line: Int, key: String)
    case missingRequiredField(field: String)
    case invalidServiceName(name: String, reason: String)
    case invalidExecutablePath(path: String, reason: String)
    case invalidRestartPolicy(value: String)
    case invalidNumericValue(key: String, value: String, reason: String)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "File not found: '\(path)'"
        case .unreadableFile(let path):
            return "Unable to read file: '\(path)'"
        case .malformedLine(let line, let content):
            return "Malformed line \(line): expected 'key=value', found '\(content)'"
        case .duplicateKey(let line, let key):
            return "Duplicate key '\(key)' at line \(line)"
        case .unknownKey(let line, let key):
            return "Unknown key '\(key)' at line \(line)"
        case .missingRequiredField(let field):
            return "Missing required field: '\(field)'"
        case .invalidServiceName(let name, let reason):
            return "Invalid service name '\(name)': \(reason)"
        case .invalidExecutablePath(let path, let reason):
            return "Invalid executable path '\(path)': \(reason)"
        case .invalidRestartPolicy(let val):
            return "Invalid restart policy '\(val)' (expected 'never', 'always', or 'on-failure')"
        case .invalidNumericValue(let key, let val, let reason):
            return "Invalid numeric value for '\(key)': '\(val)' (\(reason))"
        }
    }
}

/// Pure Swift parser and validator for declarative `.serve` service files without Foundation.
public enum ServiceParser {
    /// Trims leading and trailing ASCII whitespace.
    public static func trimWhitespace(_ str: String) -> String {
        var start = str.startIndex
        var end = str.endIndex
        while start < end && (str[start].isWhitespace || str[start].isNewline) {
            start = str.index(after: start)
        }
        while end > start {
            let prev = str.index(before: end)
            if str[prev].isWhitespace || str[prev].isNewline {
                end = prev
            } else {
                break
            }
        }
        return String(str[start..<end])
    }

    /// Splits a string delimited by commas and/or whitespace into clean tokens.
    public static func parseList(_ str: String) -> [String] {
        var items: [String] = []
        var current = ""
        for ch in str {
            if ch == "," || ch.isWhitespace {
                let trimmed = trimWhitespace(current)
                if !trimmed.isEmpty {
                    items.append(trimmed)
                }
                current = ""
            } else {
                current.append(ch)
            }
        }
        let trimmed = trimWhitespace(current)
        if !trimmed.isEmpty {
            items.append(trimmed)
        }
        return items
    }

    /// Validates service identifier format: 1..64 alphanumeric, '-', or '_'.
    public static func isValidServiceName(_ name: String) -> Bool {
        guard !name.isEmpty && name.count <= 64 else { return false }
        for ch in name {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                continue
            }
            return false
        }
        return true
    }

    /// Validates absolute executable path: starts with '/', no whitespace or control characters.
    public static func isValidExecutablePath(_ path: String) -> Bool {
        guard !path.isEmpty && path.hasPrefix("/") && path.count >= 2 else { return false }
        for ch in path {
            if ch.isWhitespace || ch.isNewline || ch == "\0" {
                return false
            }
        }
        return true
    }

    /// Parses and range-validates an integer value.
    public static func parseNumeric(key: String, value: String, min: Int, max: Int) throws -> Int {
        guard let num = Int(value), num >= min && num <= max else {
            throw ServiceParseError.invalidNumericValue(
                key: key,
                value: value,
                reason: "Must be a valid integer between \(min) and \(max)"
            )
        }
        return num
    }

    /// Parses declarative `.serve` content from a string.
    public static func parse(content: String, sourcePath: String = "") throws -> ServiceDefinition {
        var seenKeys: [String: Int] = [:]

        var nameVal: String? = nil
        var execVal: String? = nil
        var restartStr: String = "never"
        var maxRestartsVal: Int? = nil
        var restartDelayVal: Int = 1
        var stopTimeoutVal: Int = 5
        var afterVal: [String] = []
        var requiresVal: [String] = []

        var lineNumber = 1
        var currentLine = ""

        func processLine(_ rawLine: String, lineNum: Int) throws {
            let line = trimWhitespace(rawLine)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                return
            }

            guard let eqIndex = line.firstIndex(of: "=") else {
                throw ServiceParseError.malformedLine(line: lineNum, content: line)
            }

            let rawKey = String(line[line.startIndex..<eqIndex])
            let rawValue = String(line[line.index(after: eqIndex)..<line.endIndex])

            let key = trimWhitespace(rawKey).lowercased()
            let value = trimWhitespace(rawValue)

            if let prevLine = seenKeys[key] {
                _ = prevLine
                throw ServiceParseError.duplicateKey(line: lineNum, key: key)
            }
            seenKeys[key] = lineNum

            switch key {
            case "name":
                guard isValidServiceName(value) else {
                    throw ServiceParseError.invalidServiceName(
                        name: value,
                        reason: "Service name must be 1-64 alphanumeric, '-', or '_' characters without slashes"
                    )
                }
                nameVal = value

            case "exec":
                guard isValidExecutablePath(value) else {
                    throw ServiceParseError.invalidExecutablePath(
                        path: value,
                        reason: "Must be a non-empty absolute path starting with '/'"
                    )
                }
                execVal = value

            case "restart":
                let normalized = value.lowercased()
                guard normalized == "never" || normalized == "always" || normalized == "on-failure" || normalized == "on_failure" else {
                    throw ServiceParseError.invalidRestartPolicy(value: value)
                }
                restartStr = normalized

            case "max_restarts":
                maxRestartsVal = try parseNumeric(key: "max_restarts", value: value, min: 0, max: 100)

            case "restart_delay":
                restartDelayVal = try parseNumeric(key: "restart_delay", value: value, min: 0, max: 3600)

            case "stop_timeout":
                stopTimeoutVal = try parseNumeric(key: "stop_timeout", value: value, min: 1, max: 300)

            case "after":
                let list = parseList(value)
                for item in list {
                    guard isValidServiceName(item) else {
                        throw ServiceParseError.invalidServiceName(
                            name: item,
                            reason: "Invalid service identifier in 'after' list"
                        )
                    }
                }
                afterVal = list

            case "requires":
                let list = parseList(value)
                for item in list {
                    guard isValidServiceName(item) else {
                        throw ServiceParseError.invalidServiceName(
                            name: item,
                            reason: "Invalid service identifier in 'requires' list"
                        )
                    }
                }
                requiresVal = list

            default:
                throw ServiceParseError.unknownKey(line: lineNum, key: key)
            }
        }

        for ch in content {
            if ch == "\n" {
                try processLine(currentLine, lineNum: lineNumber)
                currentLine = ""
                lineNumber += 1
            } else if ch == "\r" {
                // Ignore CR in CRLF
                continue
            } else {
                currentLine.append(ch)
            }
        }
        if !currentLine.isEmpty {
            try processLine(currentLine, lineNum: lineNumber)
        }

        guard let finalName = nameVal else {
            throw ServiceParseError.missingRequiredField(field: "name")
        }
        guard let finalExec = execVal else {
            throw ServiceParseError.missingRequiredField(field: "exec")
        }

        let finalMaxRestarts: Int
        if let explicitMax = maxRestartsVal {
            finalMaxRestarts = explicitMax
        } else {
            finalMaxRestarts = (restartStr == "never") ? 0 : 3
        }

        let policy: ServiceRestartPolicy
        switch restartStr {
        case "never":
            policy = .never
        case "always":
            policy = .always(maxRestarts: finalMaxRestarts, restartDelaySeconds: restartDelayVal)
        case "on-failure", "on_failure":
            policy = .onFailure(maxRestarts: finalMaxRestarts, restartDelaySeconds: restartDelayVal)
        default:
            throw ServiceParseError.invalidRestartPolicy(value: restartStr)
        }

        return ServiceDefinition(
            name: finalName,
            executablePath: finalExec,
            arguments: [],
            environment: [:],
            restartPolicy: policy,
            stopTimeoutSeconds: stopTimeoutVal,
            after: afterVal,
            requires: requiresVal
        )
    }

    /// Reads and parses a `.serve` definition file directly from the filesystem.
    public static func parseFile(atPath path: String) throws -> ServiceDefinition {
        guard let fp = fopen(path, "rb") else {
            let err = __errno_location().pointee
            if err == ENOENT {
                throw ServiceParseError.fileNotFound(path: path)
            } else {
                throw ServiceParseError.unreadableFile(path: path)
            }
        }
        defer { fclose(fp) }

        fseek(fp, 0, SEEK_END)
        let size = ftell(fp)
        fseek(fp, 0, SEEK_SET)

        guard size >= 0 && size <= 65536 else {
            throw ServiceParseError.unreadableFile(path: path)
        }

        if size == 0 {
            return try parse(content: "", sourcePath: path)
        }

        var buffer = [CChar](repeating: 0, count: size + 1)
        let readBytes = fread(&buffer, 1, size, fp)
        buffer[readBytes] = 0
        let content = String(cString: buffer)
        return try parse(content: content, sourcePath: path)
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
