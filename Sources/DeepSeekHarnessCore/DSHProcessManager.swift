import Foundation
import Darwin

@MainActor
public final class DSHProcessManager {
    private var process: Process?
    private var outputHandle: FileHandle?
    private var processGroupID: pid_t?
    private let logURL: URL

    public init(logURL: URL? = nil) {
        self.logURL = logURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DeepSeek Harness Desktop/dsh.log")
    }

    public func start(using runtime: NodeRuntime) async throws -> URL {
        stop()
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        outputHandle = handle
        let process = Process()
        process.executableURL = runtime.npxURL
        process.arguments = ["--yes", "@deepseek-ai/dsh@0.1.0-rc.6", "web", "--host", "127.0.0.1", "--port", "0"]
        process.environment = ProcessInfo.processInfo.environment.merging(["PATH": runtime.nodeURL.deletingLastPathComponent().path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "")]) { _, new in new }
        let npmCache = logURL.deletingLastPathComponent().appendingPathComponent("npm-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: npmCache, withIntermediateDirectories: true)
        process.environment?["npm_config_cache"] = npmCache.path
        process.environment?["NPM_CONFIG_CACHE"] = npmCache.path
        process.standardOutput = handle
        process.standardError = handle
        do { try process.run() } catch { throw RuntimeError.processFailed(error.localizedDescription) }
        self.process = process
        let pid = process.processIdentifier
        if setpgid(pid, pid) == 0 { processGroupID = pid }

        // The first launch can install several hundred MB of DSH dependencies
        // into the app-local npm cache. Keep the process alive long enough for
        // that one-time provisioning to finish.
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            if let output = try? String(contentsOf: logURL, encoding: .utf8), let url = DSHOutputParser.url(from: output) {
                if try await Self.waitUntilHealthy(url: url, timeout: 30) { return url }
            }
            if !process.isRunning { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        stop()
        let detail = output.isEmpty ? "首次启动可能仍在下载 DSH 依赖，请点击“重试”。" : output.suffix(600).description
        throw RuntimeError.dshDidNotStart(detail)
    }

    public func stop() {
        if let processGroupID { _ = kill(-processGroupID, SIGTERM) }
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        if let processGroupID { _ = kill(-processGroupID, SIGKILL) }
        try? outputHandle?.close()
        outputHandle = nil
        process = nil
        self.processGroupID = nil
    }

    public var isRunning: Bool { process?.isRunning == true }
    public var logFileURL: URL { logURL }
    public var latestLog: String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    }

    private static func waitUntilHealthy(url: URL, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 { return true }
            } catch { }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }
}
