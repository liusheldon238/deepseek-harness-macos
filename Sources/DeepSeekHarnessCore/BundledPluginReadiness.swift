import Foundation

public struct BundledPluginDescriptor: Sendable, Equatable {
    public let packageName: String
    public let packageSpec: String
    public let expectedVersion: String?
    public let bundleIdentifier: String

    public init(packageName: String, packageSpec: String, expectedVersion: String?, bundleIdentifier: String) {
        self.packageName = packageName
        self.packageSpec = packageSpec
        self.expectedVersion = expectedVersion
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct BundledPluginInstallAttempt: Sendable, Equatable {
    public let environment: [String: String]
    public let timeoutSeconds: Int
}

public enum BundledPluginInstallPolicy {
    public static func attempts(baseEnvironment: [String: String], packageSpec: String) -> [BundledPluginInstallAttempt] {
        guard packageSpec.hasPrefix("file:") else {
            return [BundledPluginInstallAttempt(environment: baseEnvironment, timeoutSeconds: 120)]
        }
        var offline = baseEnvironment
        offline["npm_config_offline"] = "true"
        offline["NPM_CONFIG_OFFLINE"] = "true"
        return [
            BundledPluginInstallAttempt(environment: offline, timeoutSeconds: 20),
            BundledPluginInstallAttempt(environment: baseEnvironment, timeoutSeconds: 120),
        ]
    }
}

public enum BundledPluginReadiness {
    public static func hasInstallation(_ descriptor: BundledPluginDescriptor, in profileDirectory: URL) -> Bool {
        let manifest = object(at: profileDirectory.appendingPathComponent("package.json"))
        let dependencies = manifest?["dependencies"] as? [String: Any]
        if dependencies?[descriptor.packageName] != nil { return true }
        return FileManager.default.fileExists(atPath: profileDirectory.appendingPathComponent("node_modules/\(descriptor.packageName)/package.json").path)
    }

    public static func needsInstall(_ descriptor: BundledPluginDescriptor, in profileDirectory: URL, excludingBundles: Set<String> = []) -> Bool {
        if excludingBundles.contains(descriptor.bundleIdentifier) { return false }
        guard let manifest = object(at: profileDirectory.appendingPathComponent("package.json")),
              let dependencies = manifest["dependencies"] as? [String: Any],
              let installedSpec = dependencies[descriptor.packageName] as? String,
              dependency(installedSpec, matches: descriptor.packageSpec),
              let installed = object(at: profileDirectory.appendingPathComponent("node_modules/\(descriptor.packageName)/package.json")),
              installed["name"] as? String == descriptor.packageName,
              version(installed["version"] as? String, matches: descriptor.expectedVersion),
              let dsh = manifest["dsh"] as? [String: Any],
              let profile = dsh["profile"] as? [String: Any],
              let bundles = profile["bundles"] as? [String],
              bundles.contains(descriptor.bundleIdentifier) else { return true }
        return false
    }

    private static func version(_ installed: String?, matches expected: String?) -> Bool {
        guard let installed, !installed.isEmpty else { return false }
        return expected == nil || installed == expected
    }

    private static func dependency(_ installed: String, matches expected: String) -> Bool {
        if expected.hasPrefix("file:") { return installed.hasPrefix("file:") }
        return !installed.hasPrefix("file:")
    }

    private static func object(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
