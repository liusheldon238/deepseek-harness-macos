import Foundation

public enum StartupPhase: String, Sendable {
    case node = "正在检查 Node.js…"
    case dsh = "正在检查 DeepSeek Harness…"
    case plugins = "正在检查已安装插件…"
    case launching = "正在启动 DeepSeek Harness…"
    case repairing = "检测到插件冲突，正在隔离并修复…"
}

public struct StartupReport: Sendable {
    public let runtime: NodeRuntime
    public let dshPackage: String
    public let updatedPlugins: [String]
    public let disabledPlugins: [String]
    public let rolledBack: Bool

    public init(runtime: NodeRuntime, dshPackage: String, updatedPlugins: [String] = [], disabledPlugins: [String] = [], rolledBack: Bool = false) {
        self.runtime = runtime
        self.dshPackage = dshPackage
        self.updatedPlugins = updatedPlugins
        self.disabledPlugins = disabledPlugins
        self.rolledBack = rolledBack
    }
}

public struct StartupSnapshot: Sendable {
    public let directory: URL
    public let profileDirectory: URL
    public let manifestExisted: Bool
    public let lockfileExisted: Bool
    public let patchExisted: Bool

    public init(directory: URL, profileDirectory: URL, manifestExisted: Bool, lockfileExisted: Bool, patchExisted: Bool) {
        self.directory = directory
        self.profileDirectory = profileDirectory
        self.manifestExisted = manifestExisted
        self.lockfileExisted = lockfileExisted
        self.patchExisted = patchExisted
    }

    public func restore(using fileManager: FileManager = .default) throws {
        try Self.restoreFile("package.json", from: directory, to: profileDirectory, existed: manifestExisted, using: fileManager)
        try Self.restoreFile("pnpm-lock.yaml", from: directory, to: profileDirectory, existed: lockfileExisted, using: fileManager)
        try Self.restoreFile("cordis.patch.yml", from: directory, to: profileDirectory, existed: patchExisted, using: fileManager)
    }

    private static func restoreFile(_ name: String, from source: URL, to destination: URL, existed: Bool, using fileManager: FileManager) throws {
        let destinationURL = destination.appendingPathComponent(name)
        if fileManager.fileExists(atPath: destinationURL.path) { try fileManager.removeItem(at: destinationURL) }
        let sourceURL = source.appendingPathComponent(name)
        if existed && fileManager.fileExists(atPath: sourceURL.path) { try fileManager.copyItem(at: sourceURL, to: destinationURL) }
    }
}

public enum StartupSemVer {
    public static func latest(_ values: [String]) -> String? {
        values.compactMap { try? SemVer($0) }.max()?.description
    }
}

@MainActor
public final class SelfHealingStartup {
    public static let fallbackDSHPackage = "@deepseek-ai/dsh@0.1.0-rc.6"
    private static let corePluginPrefixes = ["@deepseek-ai/dsh-", "@deepseek-ai/cordis-"]
    private let fileManager: FileManager
    private let supportURL: URL
    private let runtimeManager: NodeRuntimeManager
    private let processManager: DSHProcessManager

    public init(supportURL: URL? = nil, runtimeManager: NodeRuntimeManager? = nil, processManager: DSHProcessManager? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.supportURL = supportURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DeepSeek Harness Desktop", isDirectory: true)
        self.runtimeManager = runtimeManager ?? NodeRuntimeManager(applicationSupportURL: self.supportURL)
        self.processManager = processManager ?? DSHProcessManager(logURL: self.supportURL.appendingPathComponent("dsh.log"))
    }

    public func start(progress: @escaping @MainActor (StartupPhase, String) -> Void = { _, _ in }) async throws -> (URL, StartupReport) {
        progress(.node, "只接受与主机架构匹配的 Node.js")
        let runtime = try await runtimeManager.resolve()
        progress(.dsh, "Node.js \(runtime.version)（\(runtime.architecture.rawValue)）")
        let profileDirectory = supportURL.appendingPathComponent("dsh-home/profiles/web", isDirectory: true)
        let snapshot = try makeSnapshot(profileDirectory: profileDirectory)
        let dshPackage = await latestDSHPackage() ?? Self.fallbackDSHPackage
        progress(.plugins, "目标 DSH：\(dshPackage)")
        var updated = try await updateRegistryPlugins(profileDirectory: profileDirectory, runtime: runtime, dshPackage: dshPackage)
        var disabled: [String] = []
        var candidatePackage = dshPackage
        for _ in 0..<8 {
            do {
                progress(.launching, candidatePackage)
                let url = try await processManager.start(using: runtime, dshPackage: candidatePackage)
                return (url, StartupReport(runtime: runtime, dshPackage: candidatePackage, updatedPlugins: updated, disabledPlugins: disabled))
            } catch let error as RuntimeError {
                guard case .pluginConflict(let detail) = error else {
                    processManager.stop()
                    try? snapshot.restore(using: fileManager)
                    if candidatePackage != Self.fallbackDSHPackage {
                        candidatePackage = Self.fallbackDSHPackage
                        updated = []
                        continue
                    }
                    throw error
                }
                progress(.repairing, detail)
                guard let candidate = try disableNextPlugin(profileDirectory: profileDirectory, detail: detail, excluding: disabled) else {
                    processManager.stop()
                    try? snapshot.restore(using: fileManager)
                    throw error
                }
                disabled.append(candidate)
            }
        }
        processManager.stop()
        try? snapshot.restore(using: fileManager)
        throw RuntimeError.dshDidNotStart("自动隔离插件后仍无法启动：\(disabled.joined(separator: ", "))")
    }

    private func latestDSHPackage() async -> String? {
        if let tag = await latestGitHubTag(), !tag.isEmpty {
            return "@deepseek-ai/dsh@\(tag.hasPrefix("v") ? String(tag.dropFirst()) : tag)"
        }
        guard let url = URL(string: "https://registry.npmjs.org/@deepseek-ai/dsh/latest") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let version = json["version"] as? String else { return nil }
        return "@deepseek-ai/dsh@\(version)"
    }

    private func latestGitHubTag() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/deepseek-ai/deepseek-harness/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = json["tag_name"] as? String else { return nil }
        return tag
    }

    private func makeSnapshot(profileDirectory: URL) throws -> StartupSnapshot {
        let snapshotDirectory = supportURL.appendingPathComponent("snapshots/\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        var existed: [String: Bool] = [:]
        for name in ["package.json", "pnpm-lock.yaml", "cordis.patch.yml"] {
            let source = profileDirectory.appendingPathComponent(name)
            let value = fileManager.fileExists(atPath: source.path)
            existed[name] = value
            if value { try fileManager.copyItem(at: source, to: snapshotDirectory.appendingPathComponent(name)) }
        }
        return StartupSnapshot(directory: snapshotDirectory, profileDirectory: profileDirectory, manifestExisted: existed["package.json"] == true, lockfileExisted: existed["pnpm-lock.yaml"] == true, patchExisted: existed["cordis.patch.yml"] == true)
    }

    private func updateRegistryPlugins(profileDirectory: URL, runtime: NodeRuntime, dshPackage: String) async throws -> [String] {
        let manifestURL = profileDirectory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let dependencies = json["dependencies"] as? [String: String] else { return [] }
        let names = dependencies.keys.filter { name in
            let spec = dependencies[name] ?? ""
            return !spec.hasPrefix("file:") && !Self.corePluginPrefixes.contains(where: name.hasPrefix) && name != "@deepseek-ai/dsh"
        }.sorted()
        guard !names.isEmpty, let pnpm = pnpmURL() else { return [] }
        var updated: [String] = []
        for name in names {
            let result = try await run(pnpm, arguments: ["update", "--latest", name], cwd: profileDirectory, runtime: runtime)
            if result == 0 { updated.append(name) }
        }
        _ = dshPackage
        return updated
    }

    private func disableNextPlugin(profileDirectory: URL, detail: String, excluding: [String]) throws -> String? {
        let manifestURL = profileDirectory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL), var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], var dsh = json["dsh"] as? [String: Any], var profile = dsh["profile"] as? [String: Any], var bundles = profile["bundles"] as? [String] else { return nil }
        let named = bundles.filter { !$0.hasPrefix("@deepseek-ai/dsh-") && !$0.hasPrefix("@deepseek-ai/cordis-") && $0 != "@deepseek-ai/dsh-base" && $0 != "@deepseek-ai/dsh-web-app" && !excluding.contains($0) }
        // Prefer the bundle explicitly named by the bootstrap error. Only use
        // the last third-party bundle as a conservative fallback when DSH
        // provides no plugin identifier at all.
        let target = named.first(where: { detail.localizedCaseInsensitiveContains($0) })
            ?? named.first(where: { detail.localizedCaseInsensitiveContains($0.replacingOccurrences(of: "@", with: "")) })
            ?? (detail.localizedCaseInsensitiveContains("plugin") ? named.last : nil)
        guard let target else { return nil }
        bundles.removeAll { $0 == target }
        profile["bundles"] = bundles
        dsh["profile"] = profile
        json["dsh"] = dsh
        let output = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: manifestURL, options: .atomic)
        return target
    }

    private func pnpmURL() -> URL? {
        ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm", fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/pnpm/pnpm").path].map(URL.init(fileURLWithPath:)).first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func run(_ executable: URL, arguments: [String], cwd: URL, runtime: NodeRuntime) async throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(executable.deletingLastPathComponent().path):\(runtime.nodeURL.deletingLastPathComponent().path):\(environment["PATH"] ?? "")"
        process.environment = environment
        try process.run()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in process.terminationHandler = { _ in continuation.resume() } }
        return process.terminationStatus
    }
}
