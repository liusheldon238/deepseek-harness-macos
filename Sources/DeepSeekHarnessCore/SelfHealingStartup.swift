import Foundation

public enum StartupPhase: String, Sendable {
    case node = "正在检查 Node.js…"
    case dsh = "正在检查 DeepSeek Harness…"
    case plugins = "正在检查已安装插件…"
    case launching = "正在启动 DeepSeek Harness…"
    case repairing = "检测到插件冲突，正在隔离并修复…"
}

public enum StartupLogPresentation: Sendable {
    case starting
    case running
    case failed

    public var showsControls: Bool { self != .running }
    public var expandsLog: Bool { self != .running }
}

public struct ClientPluginFailure: Sendable, Equatable {
    public let pluginID: String
    public let detail: String

    public init(pluginID: String, detail: String) {
        self.pluginID = pluginID
        self.detail = detail
    }
}

public enum ClientPluginFailureParser {
    public static func failure(from text: String) -> ClientPluginFailure? {
        guard text.localizedCaseInsensitiveContains("Failed to load plugins"),
              text.localizedCaseInsensitiveContains("web boot:") else { return nil }
        let pattern = #"did not activate\s+([@A-Za-z0-9._/-]+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return ClientPluginFailure(pluginID: String(text[range]), detail: String(text.suffix(4000)))
    }
}

public enum PluginConflictResolver {
    private static let coreBundles: Set<String> = [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-web-app"
    ]

    public static func isCore(_ bundle: String) -> Bool {
        coreBundles.contains(bundle)
    }

    public static func candidate(in detail: String, bundles: [String], excluding: [String]) -> String? {
        let candidates = bundles.filter { !isCore($0) && !excluding.contains($0) }
        let matches = candidates.filter { containsWholeIdentifier($0, in: detail) }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func containsWholeIdentifier(_ identifier: String, in detail: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: identifier)
        let pattern = "(?<![@A-Za-z0-9._/-])\(escaped)(?![@A-Za-z0-9._/-])"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return expression.firstMatch(in: detail, range: NSRange(detail.startIndex..., in: detail)) != nil
    }
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

public enum StartupSemVer {
    public static func latest(_ values: [String]) -> String? {
        values.compactMap { try? SemVer($0) }.max()?.description
    }
}

public enum DSHReleaseSelection {
    private struct Version: Comparable {
        let major: Int
        let minor: Int
        let patch: Int
        let prerelease: [String]?
        let original: String

        init?(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let pattern = #"^[vV]?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
                  let majorRange = Range(match.range(at: 1), in: normalized),
                  let minorRange = Range(match.range(at: 2), in: normalized),
                  let patchRange = Range(match.range(at: 3), in: normalized),
                  let major = Int(normalized[majorRange]),
                  let minor = Int(normalized[minorRange]),
                  let patch = Int(normalized[patchRange]) else { return nil }
            self.major = major
            self.minor = minor
            self.patch = patch
            if let range = Range(match.range(at: 4), in: normalized) {
                let identifiers = normalized[range].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
                guard !identifiers.isEmpty, identifiers.allSatisfy({ !$0.isEmpty }) else { return nil }
                prerelease = identifiers
            } else {
                prerelease = nil
            }
            original = normalized.hasPrefix("v") || normalized.hasPrefix("V") ? String(normalized.dropFirst()) : normalized
        }

        static func < (lhs: Version, rhs: Version) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
            switch (lhs.prerelease, rhs.prerelease) {
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            case let (left?, right?):
                for index in 0..<min(left.count, right.count) {
                    if left[index] == right[index] { continue }
                    let leftNumber = Int(left[index])
                    let rightNumber = Int(right[index])
                    switch (leftNumber, rightNumber) {
                    case let (l?, r?): return l < r
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return left[index] < right[index]
                    }
                }
                return left.count < right.count
            }
        }
    }

    public static func latest(githubTag: String?, npmVersion: String?) -> String? {
        [githubTag, npmVersion]
            .compactMap { $0 }
            .compactMap(Version.init)
            .max()?
            .original
    }

    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let candidate = Version(candidate), let installed = Version(installed) else {
            return candidate != installed
        }
        return candidate > installed
    }
}

public struct DSHLocalRuntime: Sendable, Equatable {
    public let version: String
    public let cliURL: URL

    public static func inspect(directory: URL, expectedArchitecture: NodeArchitecture, fileManager: FileManager = .default) -> DSHLocalRuntime? {
        let package = directory.appendingPathComponent("node_modules/@deepseek-ai/dsh", isDirectory: true)
        let manifestURL = package.appendingPathComponent("package.json")
        let cliURL = package.appendingPathComponent("lib/bin.js")
        let markerURL = directory.appendingPathComponent("node-architecture")
        guard let marker = try? String(contentsOf: markerURL, encoding: .utf8),
              NodeArchitecture(nodeProcessArchitecture: marker) == expectedArchitecture,
              fileManager.fileExists(atPath: cliURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else { return nil }
        return DSHLocalRuntime(version: version, cliURL: cliURL)
    }

    public static func needsInstall(local: DSHLocalRuntime?, latestVersion: String) -> Bool {
        guard let local else { return true }
        return DSHReleaseSelection.isNewer(latestVersion, than: local.version)
    }
}

@MainActor
public final class SelfHealingStartup {
    public static let fallbackDSHPackage = "@deepseek-ai/dsh@0.1.0-rc.6"
    private static let registryCorePluginPrefixes = ["@deepseek-ai/dsh-", "@deepseek-ai/cordis-"]
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
        let snapshotsDirectory = supportURL.appendingPathComponent("snapshots", isDirectory: true)
        var transaction = try ProfileTransaction.begin(profileDirectory: profileDirectory, snapshotsDirectory: snapshotsDirectory, fileManager: fileManager)
        var rolledBack = false
        let dshPackage = await latestDSHPackage() ?? Self.fallbackDSHPackage
        try Task.checkCancellation()
        let runtimeDirectory = supportURL.appendingPathComponent("dsh-runtime", isDirectory: true)
        var localDSH = DSHLocalRuntime.inspect(directory: runtimeDirectory, expectedArchitecture: runtime.architecture, fileManager: fileManager)
        var runtimeStaging: RuntimeStaging?
        if let latestVersion = Self.packageVersion(dshPackage), DSHLocalRuntime.needsInstall(local: localDSH, latestVersion: latestVersion), let pnpm = pnpmURL() {
            progress(.dsh, "发现 DSH \(latestVersion)，正在更新一次性本地运行时…")
            let staging = try RuntimeStaging.begin(targetDirectory: runtimeDirectory, fileManager: fileManager)
            do {
                let result = try await run(pnpm, arguments: ["add", "--dir", staging.directory.path, dshPackage], cwd: supportURL, runtime: runtime)
                try Data("\(runtime.architecture.rawValue)\n".utf8).write(to: staging.directory.appendingPathComponent("node-architecture"), options: .atomic)
                let candidate = result == 0 ? DSHLocalRuntime.inspect(directory: staging.directory, expectedArchitecture: runtime.architecture, fileManager: fileManager) : nil
                if let candidate {
                    localDSH = candidate
                    runtimeStaging = staging
                    processManager.appendDiagnostic("DSH 候选运行时 \(candidate.version) 已准备，待健康验证后替换。")
                } else {
                    try staging.discard()
                    processManager.appendDiagnostic("DSH \(latestVersion) 更新失败，继续使用最后一次可用的本地版本。")
                }
            } catch {
                try? staging.discard()
                if error is CancellationError {
                    try transaction.restore()
                    throw error
                }
                processManager.appendDiagnostic("DSH \(latestVersion) 更新超时或失败，继续使用最后一次可用的本地版本。")
            }
        }
        let selectedPackage = localDSH.map { "@deepseek-ai/dsh@\($0.version)" } ?? dshPackage
        progress(.plugins, "本地 DSH：\(selectedPackage)")
        var updated: [String]
        do {
            updated = try await updateRegistryPlugins(profileDirectory: profileDirectory, runtime: runtime, dshPackage: selectedPackage)
        } catch {
            try? runtimeStaging?.discard()
            try transaction.restore()
            throw error
        }
        var disabled: [String] = []
        var candidatePackage = selectedPackage
        var candidateLocalCLI = localDSH?.cliURL
        for _ in 0..<8 {
            do {
                progress(.launching, candidatePackage)
                let url = try await processManager.start(using: runtime, dshPackage: candidatePackage, localDSHCLI: candidateLocalCLI)
                try runtimeStaging?.promote()
                runtimeStaging = nil
                try transaction.commit()
                return (url, StartupReport(runtime: runtime, dshPackage: candidatePackage, updatedPlugins: updated, disabledPlugins: disabled, rolledBack: rolledBack))
            } catch let error as RuntimeError {
                guard case .pluginConflict(let detail) = error else {
                    processManager.stop()
                    try? runtimeStaging?.discard()
                    runtimeStaging = nil
                    try transaction.restore()
                    rolledBack = true
                    if candidatePackage != Self.fallbackDSHPackage {
                        candidatePackage = Self.fallbackDSHPackage
                        candidateLocalCLI = nil
                        updated = []
                        transaction = try ProfileTransaction.begin(profileDirectory: profileDirectory, snapshotsDirectory: snapshotsDirectory, fileManager: fileManager)
                        continue
                    }
                    throw error
                }
                progress(.repairing, detail)
                guard let candidate = try disableNextPlugin(profileDirectory: profileDirectory, detail: detail, excluding: disabled) else {
                    processManager.stop()
                    try? runtimeStaging?.discard()
                    try transaction.restore()
                    throw error
                }
                disabled.append(candidate)
                processManager.suppressPluginForCurrentApplicationRun(candidate)
            }
        }
        processManager.stop()
        try? runtimeStaging?.discard()
        try transaction.restore()
        throw RuntimeError.dshDidNotStart("自动隔离插件后仍无法启动：\(disabled.joined(separator: ", "))")
    }

    public func disableConflictingPlugin(_ failure: ClientPluginFailure) throws -> String? {
        processManager.stop()
        let profileDirectory = supportURL.appendingPathComponent("dsh-home/profiles/web", isDirectory: true)
        let disabled = try disableNextPlugin(profileDirectory: profileDirectory, detail: failure.pluginID, excluding: [])
        if let disabled {
            processManager.suppressPluginForCurrentApplicationRun(disabled)
            processManager.appendDiagnostic("检测到 WebView 插件激活失败，已禁用 \(disabled) 并准备重试。")
        }
        return disabled
    }

    private func latestDSHPackage() async -> String? {
        async let githubTag = latestGitHubTag()
        async let npmVersion = latestNPMVersion(for: "@deepseek-ai/dsh")
        guard let version = await DSHReleaseSelection.latest(githubTag: githubTag, npmVersion: npmVersion) else { return nil }
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

    private func updateRegistryPlugins(profileDirectory: URL, runtime: NodeRuntime, dshPackage: String) async throws -> [String] {
        let manifestURL = profileDirectory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let dependencies = json["dependencies"] as? [String: String] else { return [] }
        let names = dependencies.keys.filter { name in
            let spec = dependencies[name] ?? ""
            return !spec.hasPrefix("file:") && !Self.registryCorePluginPrefixes.contains(where: name.hasPrefix) && name != "@deepseek-ai/dsh"
        }.sorted()
        guard !names.isEmpty, let pnpm = pnpmURL() else { return [] }
        var updated: [String] = []
        for name in names {
            guard let latest = await latestNPMVersion(for: name) else { continue }
            if dependencies[name] == latest { continue }
            let result = try await run(pnpm, arguments: ["update", "\(name)@\(latest)"], cwd: profileDirectory, runtime: runtime)
            if result == 0 { updated.append(name) }
        }
        _ = dshPackage
        return updated
    }

    private func disableNextPlugin(profileDirectory: URL, detail: String, excluding: [String]) throws -> String? {
        let manifestURL = profileDirectory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL), var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], var dsh = json["dsh"] as? [String: Any], var profile = dsh["profile"] as? [String: Any], var bundles = profile["bundles"] as? [String] else { return nil }
        let target = PluginConflictResolver.candidate(in: detail, bundles: bundles, excluding: excluding)
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

    private static func packageVersion(_ package: String) -> String? {
        guard let marker = package.lastIndex(of: "@"), marker != package.startIndex else { return nil }
        return String(package[package.index(after: marker)...])
    }

    private func latestNPMVersion(for packageName: String) async -> String? {
        let escaped = packageName.replacingOccurrences(of: "/", with: "%2F")
        guard let url = URL(string: "https://registry.npmjs.org/\(escaped)/latest") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }

    private func run(_ executable: URL, arguments: [String], cwd: URL, runtime: NodeRuntime) async throws -> Int32 {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(executable.deletingLastPathComponent().path):\(runtime.nodeURL.deletingLastPathComponent().path):\(environment["PATH"] ?? "")"
        let updateLogURL = supportURL.appendingPathComponent("update.log")
        if !fileManager.fileExists(atPath: updateLogURL.path) { fileManager.createFile(atPath: updateLogURL.path, contents: nil) }
        let updateHandle = try? FileHandle(forWritingTo: updateLogURL)
        _ = try? updateHandle?.seekToEnd()
        let status = try await ManagedProcess.run(executable: executable, arguments: arguments, environment: environment, currentDirectory: cwd, output: updateHandle, timeout: .seconds(120))
        try? updateHandle?.close()
        return status
    }
}
