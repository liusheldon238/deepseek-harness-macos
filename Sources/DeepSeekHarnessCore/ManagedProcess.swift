import Darwin
import Foundation

public final class ManagedProcess: @unchecked Sendable {
    public let processIdentifier: pid_t
    private let terminationTask: Task<Int32, Never>

    private init(processIdentifier: pid_t) {
        self.processIdentifier = processIdentifier
        terminationTask = Task.detached(priority: .utility) {
            var status: Int32 = 0
            while waitpid(processIdentifier, &status, 0) == -1 && errno == EINTR { }
            if (status & 0x7f) == 0 { return (status >> 8) & 0xff }
            return 128 + (status & 0x7f)
        }
    }

    public static func spawn(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL,
        output: FileHandle?
    ) throws -> ManagedProcess {
        var attributes: posix_spawnattr_t?
        var actions: posix_spawn_file_actions_t?
        guard posix_spawnattr_init(&attributes) == 0,
              posix_spawn_file_actions_init(&actions) == 0 else {
            throw RuntimeError.processFailed("posix_spawn 初始化失败")
        }
        defer {
            posix_spawnattr_destroy(&attributes)
            posix_spawn_file_actions_destroy(&actions)
        }

        let flags = Int16(POSIX_SPAWN_SETPGROUP)
        guard posix_spawnattr_setflags(&attributes, flags) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, currentDirectory.path) == 0 else {
            throw RuntimeError.processFailed("posix_spawn 进程组设置失败")
        }
        if let output {
            guard posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDOUT_FILENO) == 0,
                  posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDERR_FILENO) == 0 else {
                throw RuntimeError.processFailed("posix_spawn 日志重定向失败")
            }
        }

        let argumentStrings = [executable.path] + arguments
        let environmentStrings = environment.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }
        let argv = argumentStrings.map { strdup($0) } + [nil]
        let envp = environmentStrings.map { strdup($0) } + [nil]
        defer {
            for case let pointer? in argv { free(UnsafeMutableRawPointer(pointer)) }
            for case let pointer? in envp { free(UnsafeMutableRawPointer(pointer)) }
        }

        var pid: pid_t = 0
        let result = argv.withUnsafeBufferPointer { argvBuffer in
            envp.withUnsafeBufferPointer { envBuffer in
                posix_spawn(
                    &pid,
                    executable.path,
                    &actions,
                    &attributes,
                    UnsafeMutablePointer(mutating: argvBuffer.baseAddress),
                    UnsafeMutablePointer(mutating: envBuffer.baseAddress)
                )
            }
        }
        guard result == 0 else {
            throw RuntimeError.processFailed(String(cString: strerror(result)))
        }
        return ManagedProcess(processIdentifier: pid)
    }

    public var isRunning: Bool {
        kill(processIdentifier, 0) == 0 || errno == EPERM
    }

    public func wait() async -> Int32 {
        await terminationTask.value
    }

    public func terminate(grace: Duration = .seconds(1)) async {
        _ = kill(-processIdentifier, SIGTERM)
        try? await Task.sleep(for: grace)
        _ = kill(-processIdentifier, SIGKILL)
        _ = await terminationTask.value
    }

    public func terminateImmediately() {
        _ = kill(-processIdentifier, SIGTERM)
        _ = kill(-processIdentifier, SIGKILL)
    }

    private func cancelImmediately() {
        _ = kill(-processIdentifier, SIGTERM)
        let group = processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
            _ = kill(-group, SIGKILL)
        }
    }

    public static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL,
        output: FileHandle?,
        timeout: Duration
    ) async throws -> Int32 {
        let process = try spawn(executable: executable, arguments: arguments, environment: environment, currentDirectory: currentDirectory, output: output)
        return try await process.wait(timeout: timeout)
    }

    public func wait(timeout: Duration) async throws -> Int32 {
        return try await withTaskCancellationHandler {
            let outcome = await withTaskGroup(of: ProcessOutcome.self) { group in
                group.addTask { .exited(await self.wait()) }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return .timedOut
                }
                let first = await group.next() ?? .timedOut
                if case .timedOut = first { await self.terminate(grace: .milliseconds(100)) }
                group.cancelAll()
                return first
            }
            try Task.checkCancellation()
            switch outcome {
            case .exited(let status): return status
            case .timedOut: throw RuntimeError.processTimedOut
            }
        } onCancel: {
            self.cancelImmediately()
        }
    }
}

private enum ProcessOutcome: Sendable {
    case exited(Int32)
    case timedOut
}
