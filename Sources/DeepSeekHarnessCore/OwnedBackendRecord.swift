import Darwin
import Foundation

public struct BackendProcessIdentity: Codable, Equatable, Sendable {
    public let pid: pid_t
    public let uid: uid_t
    public let processGroupID: pid_t
    public let startTime: UInt64
    public let executablePath: String
    public let command: String

    public init(pid: pid_t, uid: uid_t, processGroupID: pid_t, startTime: UInt64, executablePath: String, command: String) {
        self.pid = pid
        self.uid = uid
        self.processGroupID = processGroupID
        self.startTime = startTime
        self.executablePath = executablePath
        self.command = command
    }
}

public struct OwnedBackendRecord: Codable, Equatable, Sendable {
    public let identity: BackendProcessIdentity

    public init(identity: BackendProcessIdentity) {
        self.identity = identity
    }

    public func matches(_ current: BackendProcessIdentity, supportDirectory: URL) -> Bool {
        let supportPath = supportDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        return current == identity
            && current.processGroupID == current.pid
            && current.command.contains(supportPath + "/")
            && current.command.contains("/node_modules/@deepseek-ai/dsh/lib/bin.js web ")
            && current.command.contains("--host 127.0.0.1")
            && current.command.contains("--port 0")
            && current.command.contains("--no-open")
    }
}

public enum BackendProcessInspector {
    public static func inspect(pid: pid_t) -> BackendProcessIdentity? {
        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout.size(ofValue: info))
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize else { return nil }
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else { return nil }
        guard let command = try? ProcessRunner.capture(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-ww", "-p", String(pid), "-o", "command="]
        ).trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else { return nil }
        let path = String(decoding: pathBuffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return BackendProcessIdentity(
            pid: pid,
            uid: info.pbi_uid,
            processGroupID: getpgid(pid),
            startTime: info.pbi_start_tvsec,
            executablePath: path,
            command: command
        )
    }
}

public final class OwnedBackendRegistry {
    private let recordURL: URL
    private let supportDirectory: URL
    private let inspect: (pid_t) -> BackendProcessIdentity?
    private let terminateGroup: (pid_t) -> Void
    private let fileManager: FileManager

    public init(
        recordURL: URL,
        supportDirectory: URL,
        fileManager: FileManager = .default,
        inspect: @escaping (pid_t) -> BackendProcessIdentity? = BackendProcessInspector.inspect,
        terminateGroup: @escaping (pid_t) -> Void = { pid in
            _ = kill(-pid, SIGTERM)
            _ = kill(-pid, SIGKILL)
        }
    ) {
        self.recordURL = recordURL
        self.supportDirectory = supportDirectory
        self.fileManager = fileManager
        self.inspect = inspect
        self.terminateGroup = terminateGroup
    }

    public func record(pid: pid_t) throws {
        guard let identity = inspect(pid) else { throw RuntimeError.processFailed("无法读取后台进程身份") }
        try fileManager.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(OwnedBackendRecord(identity: identity)).write(to: recordURL, options: .atomic)
    }

    @discardableResult
    public func reclaimStaleBackend() throws -> Bool {
        guard let data = try? Data(contentsOf: recordURL),
              let record = try? JSONDecoder().decode(OwnedBackendRecord.self, from: data) else {
            if fileManager.fileExists(atPath: recordURL.path) { try fileManager.removeItem(at: recordURL) }
            return false
        }
        defer { try? fileManager.removeItem(at: recordURL) }
        guard let current = inspect(record.identity.pid), record.matches(current, supportDirectory: supportDirectory) else { return false }
        terminateGroup(current.processGroupID)
        return true
    }

    public func clear() throws {
        if fileManager.fileExists(atPath: recordURL.path) { try fileManager.removeItem(at: recordURL) }
    }
}
