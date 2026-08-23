import Foundation

@MainActor
public final class DSHProcessManager {
    public static let marketPackage = "dshmarket@1.13.1"
    public static let legacyAdvisorPackageName = "dsh-agent-preset-advisor"
    private var process: ManagedProcess?
    private var provisioningProcess: ManagedProcess?
    private var outputHandle: FileHandle?
    private let logURL: URL
    private let backendRegistry: OwnedBackendRegistry
    private let healthChecker: DSHHealthChecker
    private var suppressedPluginBundles: Set<String> = []

    public init(logURL: URL? = nil, healthChecker: DSHHealthChecker = DSHHealthChecker()) {
        self.logURL = logURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DeepSeek Harness Desktop/dsh.log")
        self.healthChecker = healthChecker
        let supportURL = self.logURL.deletingLastPathComponent()
        backendRegistry = OwnedBackendRegistry(recordURL: supportURL.appendingPathComponent("backend.json"), supportDirectory: supportURL)
    }

    public func start(using runtime: NodeRuntime, dshPackage: String = "@deepseek-ai/dsh@0.1.0-rc.6", localDSHCLI: URL? = nil) async throws -> URL {
        stop()
        if try backendRegistry.reclaimStaleBackend() {
            appendDiagnostic("已验证并回收 Desktop 遗留的 DSH 后台进程。")
        }
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.truncate(atOffset: 0)
        outputHandle = handle
        let environment: [String: String]
        do {
            environment = try installEnvironment(using: runtime)
            try await ensureRequiredPlugins(using: runtime, environment: environment, output: handle, dshPackage: dshPackage, localDSHCLI: localDSHCLI)
        } catch {
            stop()
            throw error
        }
        let executable: URL
        let arguments: [String]
        if let localDSHCLI {
            executable = runtime.nodeURL
            arguments = [localDSHCLI.path, "web", "--host", "127.0.0.1", "--port", "0", "--no-open"]
        } else {
            executable = runtime.npxURL
            arguments = ["--yes", dshPackage, "web", "--host", "127.0.0.1", "--port", "0", "--no-open"]
        }
        let process: ManagedProcess
        do {
            process = try ManagedProcess.spawn(executable: executable, arguments: arguments, environment: environment, currentDirectory: logURL.deletingLastPathComponent(), output: handle)
        } catch {
            stop()
            throw RuntimeError.processFailed(error.localizedDescription)
        }
        self.process = process
        do {
            try backendRegistry.record(pid: process.processIdentifier)
            appendDiagnostic("DSH 后台 PID \(process.processIdentifier) 已记录。")
        } catch {
            process.terminateImmediately()
            self.process = nil
            throw error
        }

        // The first launch can install several hundred MB of DSH dependencies
        // into the app-local npm cache. Keep the process alive long enough for
        // that one-time provisioning to finish.
        // Do not leave the desktop shell apparently frozen while npm resolves
        // a fresh prerelease graph. A later retry can resume from the cache,
        // and SelfHealingStartup will fall back to the last verified DSH.
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            try Task.checkCancellation()
            if let output = try? String(contentsOf: logURL, encoding: .utf8), let url = DSHOutputParser.url(from: output) {
                do {
                    if try await waitUntilHealthy(url: url, timeout: 30) {
                        appendDiagnostic("领域健康检查通过：agentPreset.list, settings.describe。")
                        return url
                    }
                } catch let error as RuntimeError {
                    stop()
                    throw error
                }
            }
            if !process.isRunning { break }
            try await Task.sleep(for: .milliseconds(200))
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
        let ownedProcessWasPresent = process != nil
        provisioningProcess?.terminateImmediately()
        self.provisioningProcess = nil
        process?.terminateImmediately()
        try? outputHandle?.close()
        outputHandle = nil
        process = nil
        if ownedProcessWasPresent { try? backendRegistry.clear() }
    }

    public var isRunning: Bool { process?.isRunning == true }
    public func suppressPluginForCurrentApplicationRun(_ bundleIdentifier: String) {
        suppressedPluginBundles.insert(bundleIdentifier)
    }
    public func isHealthy(at url: URL) async -> Bool {
        guard isRunning else { return false }
        return (try? await healthChecker.check(baseURL: url)) != nil
    }
    public var logFileURL: URL { logURL }
    public var latestLog: String {
        var parts: [String] = []
        let desktopLogURL = logURL.deletingLastPathComponent().appendingPathComponent("desktop.log")
        if let desktopLog = try? String(contentsOf: desktopLogURL, encoding: .utf8), !desktopLog.isEmpty {
            parts.append("[Desktop 自修复日志]\n" + String(desktopLog.suffix(12000)))
        }
        let updateLogURL = logURL.deletingLastPathComponent().appendingPathComponent("update.log")
        if let updateLog = try? String(contentsOf: updateLogURL, encoding: .utf8), !updateLog.isEmpty {
            parts.append("[DSH / 插件更新日志]\n" + String(updateLog.suffix(12000)))
        }
        if let log = try? String(contentsOf: logURL, encoding: .utf8), !log.isEmpty { parts.append(log) }
        let npmLogDirectory = logURL.deletingLastPathComponent().appendingPathComponent("npm-cache/_logs", isDirectory: true)
        if let newest = (try? FileManager.default.contentsOfDirectory(at: npmLogDirectory, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter({ $0.pathExtension == "log" })
            .sorted(by: { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) })
            .first,
           let npmLog = try? String(contentsOf: newest, encoding: .utf8), !npmLog.isEmpty {
            parts.append("[npm 调试日志]\n" + String(npmLog.suffix(12000)))
        }
        return parts.joined(separator: "\n\n")
    }

    public func appendDiagnostic(_ message: String) {
        let desktopLogURL = logURL.deletingLastPathComponent().appendingPathComponent("desktop.log")
        try? FileManager.default.createDirectory(at: desktopLogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: desktopLogURL.path) { FileManager.default.createFile(atPath: desktopLogURL.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: desktopLogURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        try? handle.write(contentsOf: Data(line.utf8))
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

    private func ensureRequiredPlugins(using runtime: NodeRuntime, environment: [String: String], output: FileHandle, dshPackage: String, localDSHCLI: URL?) async throws {
        let supportURL = logURL.deletingLastPathComponent()
        let profileDirectory = supportURL.appendingPathComponent("dsh-home/profiles/web", isDirectory: true)
        let market = BundledPluginDescriptor(packageName: "dshmarket", packageSpec: Self.marketPackage, expectedVersion: nil, bundleIdentifier: "dshmarket")
        try await installPluginIfNeeded(market, profileDirectory: profileDirectory, runtime: runtime, environment: environment, output: output, dshPackage: dshPackage, localDSHCLI: localDSHCLI)
        try await removeLegacyAdvisorIfNeeded(profileDirectory: profileDirectory, runtime: runtime, environment: environment, output: output, dshPackage: dshPackage, localDSHCLI: localDSHCLI)

        let bundledPlugins = Bundle.main.resourceURL?.appendingPathComponent("Plugins", isDirectory: true)
        let developmentPlugins = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Plugins", isDirectory: true)
        guard let pluginsDirectory = [bundledPlugins, developmentPlugins].compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("plugins.lock.json").path)
        }) else {
            throw RuntimeError.pluginInstallFailed("应用中缺少捆绑插件目录或 plugins.lock.json。")
        }
        for descriptor in try DesktopBundledPluginCatalog.descriptors(pluginsDirectory: pluginsDirectory) {
            try await installPluginIfNeeded(descriptor, profileDirectory: profileDirectory, runtime: runtime, environment: environment, output: output, dshPackage: dshPackage, localDSHCLI: localDSHCLI)
        }
    }

    private func installPluginIfNeeded(_ descriptor: BundledPluginDescriptor, profileDirectory: URL, runtime: NodeRuntime, environment: [String: String], output: FileHandle, dshPackage: String, localDSHCLI: URL?) async throws {
        if !BundledPluginReadiness.needsInstall(descriptor, in: profileDirectory, excludingBundles: suppressedPluginBundles) { return }

        let executable: URL
        let arguments: [String]
        if let localDSHCLI {
            executable = runtime.nodeURL
            arguments = [localDSHCLI.path, "plugin", "--profile", "web", "add", descriptor.packageSpec]
        } else {
            executable = runtime.npxURL
            arguments = ["--yes", dshPackage, "plugin", "--profile", "web", "add", descriptor.packageSpec]
        }
        if descriptor.packageSpec.hasPrefix("file:"), BundledPluginReadiness.hasInstallation(descriptor, in: profileDirectory) {
            let removeArguments: [String]
            if let localDSHCLI {
                removeArguments = [localDSHCLI.path, "plugin", "--profile", "web", "remove", descriptor.packageName]
            } else {
                removeArguments = ["--yes", dshPackage, "plugin", "--profile", "web", "remove", descriptor.packageName]
            }
            var offlineEnvironment = environment
            offlineEnvironment["npm_config_offline"] = "true"
            offlineEnvironment["NPM_CONFIG_OFFLINE"] = "true"
            do {
                let removal = try ManagedProcess.spawn(executable: executable, arguments: removeArguments, environment: offlineEnvironment, currentDirectory: profileDirectory, output: output)
                provisioningProcess = removal
                let status = try await removal.wait(timeout: .seconds(20))
                provisioningProcess = nil
                guard status == 0 else {
                    throw RuntimeError.pluginInstallFailed("移除旧版 \(descriptor.packageName) 失败，pnpm 退出码 \(status)。")
                }
                appendDiagnostic("已移除不完整或旧版 \(descriptor.packageName)，准备安装内置版本。")
            } catch {
                provisioningProcess = nil
                if error is CancellationError { throw error }
                if let runtimeError = error as? RuntimeError { throw runtimeError }
                throw RuntimeError.pluginInstallFailed("移除旧版 \(descriptor.packageName) 失败：\(error.localizedDescription)")
            }
        }
        let attempts = BundledPluginInstallPolicy.attempts(baseEnvironment: environment, packageSpec: descriptor.packageSpec)
        for (index, attempt) in attempts.enumerated() {
            do {
                let process = try ManagedProcess.spawn(executable: executable, arguments: arguments, environment: attempt.environment, currentDirectory: profileDirectory, output: output)
                provisioningProcess = process
                let status = try await process.wait(timeout: .seconds(attempt.timeoutSeconds))
                provisioningProcess = nil
                guard status == 0 else {
                    throw RuntimeError.pluginInstallFailed("pnpm 退出码 \(status)")
                }
                break
            } catch {
                provisioningProcess = nil
                if error is CancellationError { throw error }
                if index + 1 < attempts.count {
                    appendDiagnostic("\(descriptor.packageName) 未能从本地缓存安装，正在回退联网安装。")
                    continue
                }
                let detail = (error as? RuntimeError)?.errorDescription ?? error.localizedDescription
                throw RuntimeError.pluginInstallFailed("安装 \(descriptor.packageName) 失败：\(detail)。请查看上方内嵌日志后重试。")
            }
        }
        guard !BundledPluginReadiness.needsInstall(descriptor, in: profileDirectory) else {
            throw RuntimeError.pluginInstallFailed("\(descriptor.packageName) 命令已结束，但清单、已安装包或 bundle 激活状态仍不完整。")
        }
    }

    private func removeLegacyAdvisorIfNeeded(profileDirectory: URL, runtime: NodeRuntime, environment: [String: String], output: FileHandle, dshPackage: String, localDSHCLI: URL?) async throws {
        guard LegacyPluginMigration.needsRemoval(packageName: Self.legacyAdvisorPackageName, bundleIdentifier: Self.legacyAdvisorPackageName, in: profileDirectory) else { return }
        let executable: URL
        let arguments: [String]
        if let localDSHCLI {
            executable = runtime.nodeURL
            arguments = [localDSHCLI.path, "plugin", "--profile", "web", "remove", Self.legacyAdvisorPackageName]
        } else {
            executable = runtime.npxURL
            arguments = ["--yes", dshPackage, "plugin", "--profile", "web", "remove", Self.legacyAdvisorPackageName]
        }
        do {
            let status = try await ManagedProcess.run(executable: executable, arguments: arguments, environment: environment, currentDirectory: profileDirectory, output: output, timeout: .seconds(120))
            if status == 0,
               !LegacyPluginMigration.needsRemoval(packageName: Self.legacyAdvisorPackageName, bundleIdentifier: Self.legacyAdvisorPackageName, in: profileDirectory) {
                appendDiagnostic("已移除旧版 dsh-agent-preset-advisor。")
                return
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            appendDiagnostic("旧版 advisor 卸载命令失败：\(error.localizedDescription)")
        }
        let disabled = try LegacyPluginMigration.disableBundle(Self.legacyAdvisorPackageName, in: profileDirectory)
        appendDiagnostic(disabled
            ? "旧版 advisor 未能完整卸载，已从 bundle 激活列表禁用；下次启动继续迁移。"
            : "旧版 advisor 未能完整卸载且当前未激活；下次启动继续迁移。")
    }

    private func waitUntilHealthy(url: URL, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            do {
                _ = try await healthChecker.check(baseURL: url)
                return true
            } catch let error as RuntimeError {
                if case .pluginConflict = error { throw error }
            } catch { }
            try await Task.sleep(for: .milliseconds(250))
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
