import CryptoKit
import Foundation

public struct SemVer: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^v", with: "", options: .regularExpression)
        let parts = normalized.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0 else {
            throw RuntimeError.invalidNodeVersion(value)
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public enum NodeArchitecture: String, Sendable {
    case arm64
    case x64

    public static var host: NodeArchitecture {
        #if arch(arm64)
        return .arm64
        #else
        return .x64
        #endif
    }

    public init?(nodeProcessArchitecture: String) {
        switch nodeProcessArchitecture.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "arm64", "aarch64": self = .arm64
        case "x64", "x86_64": self = .x64
        default: return nil
        }
    }
}

public struct NodeDistribution: Sendable {
    public let version: SemVer
    public let architecture: NodeArchitecture

    public init(version: SemVer, architecture: NodeArchitecture) {
        self.version = version
        self.architecture = architecture
    }

    public var archiveName: String {
        "node-v\(version)-darwin-\(architecture.rawValue).tar.gz"
    }

    public var archiveURL: URL {
        URL(string: "https://nodejs.org/dist/v\(version)/\(archiveName)")!
    }

    public var checksumsURL: URL {
        URL(string: "https://nodejs.org/dist/v\(version)/SHASUMS256.txt")!
    }
}

public enum RuntimeError: LocalizedError, Sendable {
    case invalidNodeVersion(String)
    case noCompatibleNode
    case nodeDownloadFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(String)
    case missingExecutable(URL)
    case processFailed(String)
    case pluginInstallFailed(String)
    case dshDidNotStart(String)

    public var errorDescription: String {
        switch self {
        case .invalidNodeVersion(let value): return "无法识别 Node 版本：\(value)"
        case .noCompatibleNode: return "未找到兼容的 Node.js，将自动下载运行时。"
        case .nodeDownloadFailed(let detail): return "Node.js 下载失败：\(detail)"
        case .checksumMismatch: return "Node.js 校验和不匹配，已拒绝安装。"
        case .extractionFailed(let detail): return "Node.js 解压失败：\(detail)"
        case .missingExecutable(let url): return "缺少可执行文件：\(url.path)"
        case .processFailed(let detail): return "进程启动失败：\(detail)"
        case .pluginInstallFailed(let detail): return "dsh-market 安装失败：\(detail)"
        case .dshDidNotStart(let detail): return "DeepSeek Harness 未能启动：\(detail)"
        }
    }
}

public enum NodeCompatibility {
    public static func isCompatible(version: SemVer, architecture: NodeArchitecture, hostArchitecture: NodeArchitecture, minimum: SemVer) -> Bool {
        version >= minimum && architecture == hostArchitecture
    }
}

public struct NodeRuntime: Sendable {
    public let nodeURL: URL
    public let npxURL: URL
    public let version: SemVer
    public let architecture: NodeArchitecture

    public init(nodeURL: URL, version: SemVer, architecture: NodeArchitecture) throws {
        let npxURL = nodeURL.deletingLastPathComponent().appendingPathComponent("npx")
        guard FileManager.default.isExecutableFile(atPath: nodeURL.path), FileManager.default.isExecutableFile(atPath: npxURL.path) else {
            throw RuntimeError.missingExecutable(npxURL)
        }
        self.nodeURL = nodeURL
        self.npxURL = npxURL
        self.version = version
        self.architecture = architecture
    }
}

@MainActor
public final class NodeRuntimeManager {
    public static let minimumVersion = try! SemVer("22.19.0")
    public static let provisionedVersion = try! SemVer("22.23.1")

    private let fileManager: FileManager
    private let applicationSupportURL: URL
    private let environment: [String: String]

    public init(applicationSupportURL: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DeepSeek Harness Desktop", isDirectory: true)
        self.environment = environment
    }

    public func resolve() async throws -> NodeRuntime {
        if let runtime = try findCompatibleNode() { return runtime }
        return try await downloadProvisionedRuntime()
    }

    public func findCompatibleNode() throws -> NodeRuntime? {
        var candidates: [URL] = []
        if let path = environment["PATH"] {
            candidates += path.split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent("node") }
        }
        candidates += [
            URL(fileURLWithPath: "/opt/homebrew/bin/node"),
            URL(fileURLWithPath: "/usr/local/bin/node"),
            URL(fileURLWithPath: "/usr/bin/node")
        ]
        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate.path).inserted {
            guard fileManager.isExecutableFile(atPath: candidate.path) else { continue }
            guard let versionText = try? ProcessRunner.capture(executable: candidate, arguments: ["--version"]),
                  let version = try? SemVer(versionText),
                  let architectureText = try? ProcessRunner.capture(executable: candidate, arguments: ["-p", "process.arch"]),
                  let architecture = NodeArchitecture(nodeProcessArchitecture: architectureText),
                  NodeCompatibility.isCompatible(version: version, architecture: architecture, hostArchitecture: .host, minimum: Self.minimumVersion),
                  let runtime = try? NodeRuntime(nodeURL: candidate, version: version, architecture: architecture) else { continue }
            return runtime
        }
        return nil
    }

    private func downloadProvisionedRuntime() async throws -> NodeRuntime {
        let distribution = NodeDistribution(version: Self.provisionedVersion, architecture: .host)
        let installURL = applicationSupportURL.appendingPathComponent("runtime/v\(distribution.version)-\(distribution.architecture.rawValue)", isDirectory: true)
        let existingNode = installURL.appendingPathComponent("bin/node")
        if fileManager.isExecutableFile(atPath: existingNode.path),
           let versionText = try? ProcessRunner.capture(executable: existingNode, arguments: ["--version"]),
           let version = try? SemVer(versionText),
           let runtime = try? NodeRuntime(nodeURL: existingNode, version: version, architecture: distribution.architecture),
           NodeCompatibility.isCompatible(version: version, architecture: distribution.architecture, hostArchitecture: .host, minimum: Self.minimumVersion) {
            return runtime
        }

        let stagingURL = applicationSupportURL.appendingPathComponent("downloads/.staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
            let (archiveData, _) = try await URLSession.shared.data(from: distribution.archiveURL)
            let (checksumData, _) = try await URLSession.shared.data(from: distribution.checksumsURL)
            let expected = try Self.checksum(for: distribution.archiveName, in: checksumData)
            let actual = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
            guard expected == actual else { throw RuntimeError.checksumMismatch(expected: expected, actual: actual) }

            let archiveURL = stagingURL.appendingPathComponent(distribution.archiveName)
            try archiveData.write(to: archiveURL, options: .atomic)
            let extractedURL = stagingURL.appendingPathComponent("extracted", isDirectory: true)
            try fileManager.createDirectory(at: extractedURL, withIntermediateDirectories: true)
            try ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-xzf", archiveURL.path, "-C", extractedURL.path, "--strip-components", "1"])
            try fileManager.createDirectory(at: installURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: installURL.path) { try fileManager.removeItem(at: installURL) }
            try fileManager.moveItem(at: extractedURL, to: installURL)
            guard fileManager.isExecutableFile(atPath: existingNode.path) else { throw RuntimeError.extractionFailed("解压后缺少 node") }
            return try NodeRuntime(nodeURL: existingNode, version: distribution.version, architecture: distribution.architecture)
        } catch let error as RuntimeError {
            throw error
        } catch {
            throw RuntimeError.nodeDownloadFailed(error.localizedDescription)
        }
    }

    private static func checksum(for filename: String, in data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8),
              let line = text.split(whereSeparator: { $0.isNewline }).first(where: { $0.contains(filename) }) else {
            throw RuntimeError.nodeDownloadFailed("官方校验文件中找不到 \(filename)")
        }
        let checksum = line.split(whereSeparator: { $0 == " " || $0 == "*" }).first.map(String.init) ?? ""
        guard checksum.count == 64 else { throw RuntimeError.nodeDownloadFailed("官方校验值格式无效") }
        return checksum.lowercased()
    }
}

public enum DSHOutputParser {
    public static func url(from line: String) -> URL? {
        guard let range = line.range(of: #"http://127\.0\.0\.1:\d+"#, options: .regularExpression) else { return nil }
        return URL(string: String(line[range]))
    }
}

public enum ProcessRunner {
    public static func capture(executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RuntimeError.processFailed(String(data: data, encoding: .utf8) ?? "exit \(process.terminationStatus)") }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func run(executable: URL, arguments: [String]) throws {
        _ = try capture(executable: executable, arguments: arguments)
    }
}
