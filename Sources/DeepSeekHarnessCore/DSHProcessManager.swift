import Foundation
import Darwin

@MainActor
public final class DSHProcessManager {
    public static let marketPackage = "dshmarket@1.13.1"
    public static let presetAdvisorPackage = "dsh-agent-preset-advisor@0.1.0"
    private var process: Process?
    private var provisioningProcess: Process?
    private var outputHandle: FileHandle?
    private var processGroupID: pid_t?
    private let logURL: URL

    public init(logURL: URL? = nil) {
        self.logURL = logURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DeepSeek Harness Desktop/dsh.log")
    }

    public func start(using runtime: NodeRuntime, dshPackage: String = "@deepseek-ai/dsh@0.1.0-rc.6") async throws -> URL {
        stop()
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.truncate(atOffset: 0)
        outputHandle = handle
        let environment: [String: String]
        do {
            environment = try installEnvironment(using: runtime)
        try await ensureMarketPlugin(using: runtime, environment: environment, output: handle, dshPackage: dshPackage)
        } catch {
            stop()
            throw error
        }
        let process = Process()
        process.executableURL = runtime.npxURL
        process.arguments = ["--yes", dshPackage, "web", "--host", "127.0.0.1", "--port", "0"]
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        do { try process.run() } catch {
            stop()
            throw RuntimeError.processFailed(error.localizedDescription)
        }
        self.process = process
        let pid = process.processIdentifier
        if setpgid(pid, pid) == 0 { processGroupID = pid }

        // The first launch can install several hundred MB of DSH dependencies
        // into the app-local npm cache. Keep the process alive long enough for
        // that one-time provisioning to finish.
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            if let output = try? String(contentsOf: logURL, encoding: .utf8), let url = DSHOutputParser.url(from: output) {
                do {
                    if try await Self.waitUntilHealthy(url: url, timeout: 30) { return url }
                } catch let error as RuntimeError {
                    stop()
                    throw error
                }
            }
            if !process.isRunning { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        stop()
        if let conflict = Self.pluginConflictDetail(in: output) {
            throw RuntimeError.pluginConflict(conflict)
        }
        let detail = output.isEmpty ? "首次启动可能仍在下载 DSH 依赖，请点击“重试”。" : output.suffix(600).description
        throw RuntimeError.dshDidNotStart(detail)
    }

    public func stop() {
        if let provisioningProcess, provisioningProcess.isRunning {
            provisioningProcess.terminate()
            provisioningProcess.waitUntilExit()
        }
        self.provisioningProcess = nil
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

    private func installEnvironment(using runtime: NodeRuntime) throws -> [String: String] {
        let supportURL = logURL.deletingLastPathComponent()
        let npmCache = supportURL.appendingPathComponent("npm-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: npmCache, withIntermediateDirectories: true)
        let nodeDirectory = runtime.nodeURL.deletingLastPathComponent().path
        let pnpmDirectory = ["/opt/homebrew/bin", "/usr/local/bin", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/pnpm").path]
            .first { FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: $0).appendingPathComponent("pnpm").path) }
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let path = ([pnpmDirectory, nodeDirectory] + inheritedPath.split(separator: ":").map(String.init)).compactMap { $0 }.joined(separator: ":")
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        environment["DSH_HOME"] = supportURL.appendingPathComponent("dsh-home", isDirectory: true).path
        environment["npm_config_cache"] = npmCache.path
        environment["NPM_CONFIG_CACHE"] = npmCache.path
        return environment
    }

    private func ensureMarketPlugin(using runtime: NodeRuntime, environment: [String: String], output: FileHandle, dshPackage: String) async throws {
        let supportURL = logURL.deletingLastPathComponent()
        let profileDirectory = supportURL.appendingPathComponent("dsh-home/profiles/web", isDirectory: true)
        try await installPluginIfNeeded(Self.marketPackage, packageName: "dshmarket", profileDirectory: profileDirectory, runtime: runtime, environment: environment, output: output, dshPackage: dshPackage)
        let bundledAdvisor = Bundle.main.resourceURL?.appendingPathComponent("dsh-agent-preset-advisor", isDirectory: true)
        let developmentAdvisor = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/dsh-agent-preset-advisor", isDirectory: true)
        guard let advisorURL = [bundledAdvisor, developmentAdvisor].compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("package.json").path)
        }) else { return }
        try await installPluginIfNeeded("file:\(advisorURL.path)", packageName: "dsh-agent-preset-advisor", profileDirectory: profileDirectory, runtime: runtime, environment: environment, output: output, dshPackage: dshPackage)
    }

    private func installPluginIfNeeded(_ packageSpec: String, packageName: String, profileDirectory: URL, runtime: NodeRuntime, environment: [String: String], output: FileHandle, dshPackage: String) async throws {
        let manifestURL = profileDirectory.appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: manifestURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dependencies = json["dependencies"] as? [String: Any],
           let installedSpec = dependencies[packageName] as? String,
           (!packageSpec.hasPrefix("file:") || installedSpec == packageSpec),
           FileManager.default.fileExists(atPath: profileDirectory.appendingPathComponent("node_modules/\(packageName)").path) { return }

        let process = Process()
        process.executableURL = runtime.npxURL
        process.arguments = ["--yes", dshPackage, "plugin", "--profile", "web", "add", packageSpec]
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        provisioningProcess = process
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            provisioningProcess = nil
            throw RuntimeError.pluginInstallFailed(error.localizedDescription)
        }
        provisioningProcess = nil
        guard process.terminationStatus == 0 else {
            throw RuntimeError.pluginInstallFailed("安装 \(packageName) 失败，pnpm 退出码 \(process.terminationStatus)。请查看上方内嵌日志后重试。")
        }
    }

    private static func waitUntilHealthy(url: URL, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    if body.contains("Failed to load plugins") || body.contains("web boot:") {
                        let detail = body.split(separator: "\n").first(where: { $0.contains("dsh-") || $0.contains("plugin") }) ?? "Web 插件启动失败"
                        throw RuntimeError.pluginConflict(String(detail).trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    return true
                }
            } catch let error as RuntimeError {
                // Preserve the structured conflict signal for the self-healing
                // coordinator; swallowing it would turn a repairable plugin
                // failure into an opaque timeout.
                throw error
            } catch { }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private static func pluginConflictDetail(in output: String) -> String? {
        guard output.contains("Failed to load plugins") || output.contains("web boot:") else { return nil }
        return output.split(separator: "\n")
            .first(where: { $0.contains("dsh-") || $0.localizedCaseInsensitiveContains("plugin") })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? "Web 插件启动失败"
    }
}
