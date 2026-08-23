import Foundation

public enum DesktopBundledPluginCatalog {
    private static let orderedPackages = ["dsh-preset-catalog", "dsh-model-search"]

    public static func descriptors(pluginsDirectory: URL) throws -> [BundledPluginDescriptor] {
        try orderedPackages.map { packageName in
            let packageDirectory = pluginsDirectory.appendingPathComponent(packageName, isDirectory: true)
            let manifestURL = packageDirectory.appendingPathComponent("package.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  manifest["name"] as? String == packageName,
                  let version = manifest["version"] as? String,
                  !version.isEmpty else {
                throw RuntimeError.pluginInstallFailed("捆绑插件 \(packageName) 缺失或 package.json 无效。")
            }
            return BundledPluginDescriptor(
                packageName: packageName,
                packageSpec: "file:\(packageDirectory.path)",
                expectedVersion: version,
                bundleIdentifier: packageName
            )
        }
    }
}

public enum LegacyPluginMigration {
    public static func needsRemoval(packageName: String, bundleIdentifier: String, in profileDirectory: URL) -> Bool {
        if FileManager.default.fileExists(atPath: profileDirectory.appendingPathComponent("node_modules/\(packageName)").path) {
            return true
        }
        guard let data = try? Data(contentsOf: profileDirectory.appendingPathComponent("package.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let dependencies = manifest["dependencies"] as? [String: Any], dependencies[packageName] != nil {
            return true
        }
        let dsh = manifest["dsh"] as? [String: Any]
        let profile = dsh?["profile"] as? [String: Any]
        let bundles = profile?["bundles"] as? [String]
        return bundles?.contains(bundleIdentifier) == true
    }

    @discardableResult
    public static func disableBundle(_ bundleIdentifier: String, in profileDirectory: URL) throws -> Bool {
        let manifestURL = profileDirectory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var dsh = manifest["dsh"] as? [String: Any],
              var profile = dsh["profile"] as? [String: Any],
              var bundles = profile["bundles"] as? [String],
              bundles.contains(bundleIdentifier) else { return false }
        bundles.removeAll { $0 == bundleIdentifier }
        profile["bundles"] = bundles
        dsh["profile"] = profile
        manifest["dsh"] = dsh
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: manifestURL, options: .atomic)
        return true
    }
}
