import Foundation

public protocol CodexUsageFetching {
    func fetchSnapshot() async throws -> CodexUsageSnapshot
}

public enum CodexRPCError: LocalizedError, Equatable {
    case codexNotFound
    case startFailed(String)
    case requestFailed(String)
    case malformed(String)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "Codex CLI was not found on PATH."
        case let .startFailed(message):
            return "Codex app-server failed to start: \(message)"
        case let .requestFailed(message):
            return "Codex RPC request failed: \(message)"
        case let .malformed(message):
            return "Codex RPC returned invalid data: \(message)"
        case let .timeout(method):
            return "Codex RPC timed out waiting for \(method)."
        }
    }
}

public struct CodexRPCUsageFetcher: CodexUsageFetching, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var initializeTimeout: TimeInterval
    public var requestTimeout: TimeInterval

    public init(
        executable: String = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"] ?? "codex",
        arguments: [String] = ["-s", "read-only", "-a", "never", "app-server"],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        initializeTimeout: TimeInterval = 8,
        requestTimeout: TimeInterval = 3)
    {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.initializeTimeout = initializeTimeout
        self.requestTimeout = requestTimeout
    }

    public func fetchSnapshot() async throws -> CodexUsageSnapshot {
        let client = try CodexRPCClient(
            executable: self.executable,
            arguments: self.arguments,
            environment: self.environment,
            initializeTimeout: self.initializeTimeout,
            requestTimeout: self.requestTimeout)
        defer { client.shutdown() }

        try await client.initialize()
        let rateLimits: CodexRateLimitsRPCResult = try await client.request(method: "account/rateLimits/read")
        let account: CodexAccountRPCResult? = try? await client.request(method: "account/read")
        return CodexRPCMapper.snapshot(rateLimits: rateLimits, account: account, updatedAt: Date())
    }
}

/// Keeps a single Codex `app-server` process alive across refreshes instead of
/// spawning, initializing, and killing a fresh one every cycle. Reconnects
/// automatically when the connection drops or a request fails.
///
/// Calls are expected to be serialized by the caller (the menu bar app already
/// guards refreshes); this type does not coalesce concurrent `fetchSnapshot`s.
public actor CodexRPCConnectionFetcher: CodexUsageFetching {
    private let executable: String
    private let arguments: [String]
    private let environment: [String: String]
    private let initializeTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private var client: CodexRPCClient?

    public init(
        executable: String = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"] ?? "codex",
        arguments: [String] = ["-s", "read-only", "-a", "never", "app-server"],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        initializeTimeout: TimeInterval = 8,
        requestTimeout: TimeInterval = 3)
    {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.initializeTimeout = initializeTimeout
        self.requestTimeout = requestTimeout
    }

    public func fetchSnapshot() async throws -> CodexUsageSnapshot {
        let client = try await self.connectedClient()
        do {
            let rateLimits: CodexRateLimitsRPCResult = try await client.request(method: "account/rateLimits/read")
            let account: CodexAccountRPCResult? = try? await client.request(method: "account/read")
            return CodexRPCMapper.snapshot(rateLimits: rateLimits, account: account, updatedAt: Date())
        } catch {
            // The connection is suspect — drop it so the next fetch reconnects.
            self.teardown()
            throw error
        }
    }

    /// Tears down the live connection (e.g. on quit) so the child process exits.
    public func disconnect() {
        self.teardown()
    }

    private func connectedClient() async throws -> CodexRPCClient {
        if let client = self.client, client.isAlive {
            return client
        }
        self.teardown()
        let client = try CodexRPCClient(
            executable: self.executable,
            arguments: self.arguments,
            environment: self.environment,
            initializeTimeout: self.initializeTimeout,
            requestTimeout: self.requestTimeout)
        do {
            try await client.initialize()
        } catch {
            client.shutdown()
            throw error
        }
        self.client = client
        return client
    }

    private func teardown() {
        self.client?.shutdown()
        self.client = nil
    }
}

public enum CodexRPCPayload {
    public static func request(id: Int, method: String, params: [String: Any] = [:]) throws -> Data {
        let payload: [String: Any] = [
            "id": id,
            "method": method,
            "params": params
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public static func notification(method: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["method": method, "params": [:]], options: [.sortedKeys])
    }
}

final class CodexRPCClient {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdoutStream: AsyncStream<Data>
    private let stdoutContinuation: AsyncStream<Data>.Continuation
    private let initializeTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private var nextID = 1
    private let stderrLock = NSLock()
    private var stderrTail: [String] = []

    private final class LineBuffer {
        private let lock = NSLock()
        private var buffer = Data()

        func append(_ data: Data) -> [Data] {
            self.lock.lock()
            defer { self.lock.unlock() }

            self.buffer.append(data)
            var lines: [Data] = []
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                let line = Data(self.buffer[..<newline])
                self.buffer.removeSubrange(...newline)
                if !line.isEmpty {
                    lines.append(line)
                }
            }
            return lines
        }
    }

    init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        initializeTimeout: TimeInterval,
        requestTimeout: TimeInterval) throws
    {
        self.initializeTimeout = initializeTimeout
        self.requestTimeout = requestTimeout

        guard Self.canLaunch(executable: executable, environment: environment) else {
            throw CodexRPCError.codexNotFound
        }

        var continuation: AsyncStream<Data>.Continuation!
        self.stdoutStream = AsyncStream<Data> { continuation = $0 }
        self.stdoutContinuation = continuation

        var env = environment
        env["PATH"] = Self.expandedPath(from: env)

        self.process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        self.process.arguments = [executable] + arguments
        self.process.environment = env
        self.process.standardInput = self.stdinPipe
        self.process.standardOutput = self.stdoutPipe
        self.process.standardError = self.stderrPipe

        do {
            try self.process.run()
        } catch {
            throw CodexRPCError.startFailed(error.localizedDescription)
        }

        self.installStdoutHandler()
        self.installStderrHandler()
    }

    deinit {
        self.shutdown()
    }

    func initialize() async throws {
        let id = self.nextRequestID()
        try self.send(CodexRPCPayload.request(
            id: id,
            method: "initialize",
            params: ["clientInfo": ["name": "codexhud", "version": "0.1.0"]]))
        try await self.waitForEmptyResult(id: id, method: "initialize", timeout: self.initializeTimeout)
        try self.send(CodexRPCPayload.notification(method: "initialized"))
    }

    func request<T: Decodable>(method: String) async throws -> T {
        let id = self.nextRequestID()
        try self.send(CodexRPCPayload.request(id: id, method: method))
        return try await self.waitForResult(id: id, method: method, timeout: self.requestTimeout)
    }

    var isAlive: Bool {
        self.process.isRunning
    }

    func shutdown() {
        self.stdoutPipe.fileHandleForReading.readabilityHandler = nil
        self.stderrPipe.fileHandleForReading.readabilityHandler = nil
        self.stdoutContinuation.finish()
        if self.process.isRunning {
            self.process.terminate()
        }
    }

    private func nextRequestID() -> Int {
        let id = self.nextID
        self.nextID += 1
        return id
    }

    private func send(_ data: Data) throws {
        guard self.process.isRunning else {
            throw CodexRPCError.requestFailed("app-server process is not running")
        }
        let handle = self.stdinPipe.fileHandleForWriting
        do {
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
        } catch {
            throw CodexRPCError.requestFailed("failed writing to app-server stdin: \(error.localizedDescription)")
        }
    }

    private func waitForEmptyResult(id: Int, method: String, timeout: TimeInterval) async throws {
        let _: EmptyRPCResult = try await self.waitForResult(id: id, method: method, timeout: timeout)
    }

    private func waitForResult<T: Decodable>(id: Int, method: String, timeout: TimeInterval) async throws -> T {
        try await self.withTimeout(seconds: timeout, method: method) {
            let decoder = JSONDecoder()
            for await line in self.stdoutStream {
                let envelope = try decoder.decode(RPCEnvelope<T>.self, from: line)
                guard envelope.id == id else { continue }
                if let error = envelope.error {
                    throw CodexRPCError.requestFailed(error.message)
                }
                guard let result = envelope.result else {
                    throw CodexRPCError.malformed("missing result for \(method)")
                }
                return result
            }
            throw CodexRPCError.malformed(self.decorated("stdout closed while waiting for \(method)"))
        }
    }

    /// Appends the recently captured app-server stderr to a failure message so
    /// auth/setup problems (which Codex reports on stderr, not over RPC) are
    /// visible instead of just "timed out".
    private func decorated(_ message: String) -> String {
        let stderr = self.recentStderr()
        return stderr.isEmpty ? message : "\(message) — codex stderr: \(stderr)"
    }

    private func timeoutFailure(method: String) -> CodexRPCError {
        let stderr = self.recentStderr()
        if stderr.isEmpty {
            return .timeout(method)
        }
        return .requestFailed("timed out waiting for \(method) — codex stderr: \(stderr)")
    }

    private func recentStderr() -> String {
        self.stderrLock.lock()
        defer { self.stderrLock.unlock() }
        return self.stderrTail.joined(separator: "\n")
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        method: String,
        operation: @escaping () async throws -> T) async throws -> T
    {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self.shutdown()
                throw self.timeoutFailure(method: method)
            }

            do {
                guard let result = try await group.next() else {
                    throw CodexRPCError.timeout(method)
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func installStdoutHandler() {
        let buffer = LineBuffer()
        let continuation = self.stdoutContinuation
        self.stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                continuation.finish()
                handle.readabilityHandler = nil
                return
            }
            for line in buffer.append(data) {
                continuation.yield(line)
            }
        }
    }

    private func installStderrHandler() {
        self.stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8) else { return }
            self?.appendStderr(text)
        }
    }

    private func appendStderr(_ text: String) {
        self.stderrLock.lock()
        defer { self.stderrLock.unlock() }
        for line in text.split(whereSeparator: \.isNewline) {
            self.stderrTail.append(String(line))
        }
        if self.stderrTail.count > 10 {
            self.stderrTail.removeFirst(self.stderrTail.count - 10)
        }
    }

    private static func expandedPath(from environment: [String: String]) -> String {
        let current = environment["PATH"] ?? ""
        let extras = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        return ([current] + extras)
            .filter { !$0.isEmpty }
            .joined(separator: ":")
    }

    private static func canLaunch(executable: String, environment: [String: String]) -> Bool {
        if executable.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executable)
        }

        return Self.expandedPath(from: environment)
            .split(separator: ":")
            .contains { directory in
                FileManager.default.isExecutableFile(atPath: "\(directory)/\(executable)")
            }
    }
}

private struct EmptyRPCResult: Decodable {}

private struct RPCEnvelope<T: Decodable>: Decodable {
    let id: Int?
    let result: T?
    let error: RPCErrorBody?
}

private struct RPCErrorBody: Decodable {
    let message: String
}
