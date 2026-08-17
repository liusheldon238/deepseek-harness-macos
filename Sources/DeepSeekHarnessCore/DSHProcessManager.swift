import Foundation

@MainActor
public final class DSHProcessManager {
    private var process: Process?
    private var outputHandle: FileHandle?
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
        process.standardOutput = handle
        process.standardError = handle
        do { try process.run() } catch { throw RuntimeError.processFailed(error.localizedDescription) }
        self.process = process

        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if let output = try? String(contentsOf: logURL, encoding: .utf8), let url = DSHOutputParser.url(from: output) {
                if try await Self.waitUntilHealthy(url: url, timeout: 30) { return url }
            }
            if !process.isRunning { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        stop()
        throw RuntimeError.dshDidNotStart(output.suffix(600).description)
    }

    public func stop() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? outputHandle?.close()
        outputHandle = nil
        process = nil
    }

    public var isRunning: Bool { process?.isRunning == true }
    public var logFileURL: URL { logURL }

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
