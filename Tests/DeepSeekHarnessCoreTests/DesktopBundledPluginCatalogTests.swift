import XCTest
@testable import DeepSeekHarnessCore

final class DesktopBundledPluginCatalogTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testBundledPluginsHaveExplicitStableInstallationOrder() throws {
        let plugins = try DesktopBundledPluginCatalog.descriptors(
            pluginsDirectory: repositoryRoot.appendingPathComponent("Resources/Plugins", isDirectory: true)
        )

        XCTAssertEqual(plugins.map(\.packageName), ["dsh-preset-catalog", "dsh-model-search"])
        XCTAssertEqual(plugins.map(\.expectedVersion), ["0.1.0", "0.1.0"])
        XCTAssertEqual(plugins.map(\.bundleIdentifier), ["dsh-preset-catalog", "dsh-model-search"])
        XCTAssertTrue(plugins.allSatisfy { $0.packageSpec.hasPrefix("file:") })
    }

    func testLegacyAdvisorMigrationDetectsDependencyBundleOrInstalledPackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "dependencies": ["dsh-agent-preset-advisor": "file:/old/app/plugin"],
            "dsh": ["profile": ["bundles": ["@deepseek-ai/dsh-base", "dsh-agent-preset-advisor"]]]
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("package.json"))

        XCTAssertTrue(LegacyPluginMigration.needsRemoval(packageName: "dsh-agent-preset-advisor", bundleIdentifier: "dsh-agent-preset-advisor", in: root))
        XCTAssertTrue(try LegacyPluginMigration.disableBundle("dsh-agent-preset-advisor", in: root))
        let disabledData = try Data(contentsOf: root.appendingPathComponent("package.json"))
        let disabledManifest = try XCTUnwrap(JSONSerialization.jsonObject(with: disabledData) as? [String: Any])
        let disabledDSH = try XCTUnwrap(disabledManifest["dsh"] as? [String: Any])
        let disabledProfile = try XCTUnwrap(disabledDSH["profile"] as? [String: Any])
        XCTAssertFalse(try XCTUnwrap(disabledProfile["bundles"] as? [String]).contains("dsh-agent-preset-advisor"))

        let cleanManifest: [String: Any] = [
            "dependencies": ["dsh-preset-catalog": "file:/new/catalog"],
            "dsh": ["profile": ["bundles": ["@deepseek-ai/dsh-base", "dsh-preset-catalog"]]]
        ]
        try JSONSerialization.data(withJSONObject: cleanManifest).write(to: root.appendingPathComponent("package.json"), options: .atomic)
        XCTAssertFalse(LegacyPluginMigration.needsRemoval(packageName: "dsh-agent-preset-advisor", bundleIdentifier: "dsh-agent-preset-advisor", in: root))

        let installed = root.appendingPathComponent("node_modules/dsh-agent-preset-advisor", isDirectory: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        XCTAssertTrue(LegacyPluginMigration.needsRemoval(packageName: "dsh-agent-preset-advisor", bundleIdentifier: "dsh-agent-preset-advisor", in: root))
    }
}
