import XCTest
@testable import DeepSeekHarnessCore

final class BundledPluginReadinessTests: XCTestCase {
    private func makeProfile(
        dependency: String? = "file:/bundle/dsh-model-provider",
        installedVersion: String? = "0.1.0",
        bundles: [String] = ["dsh-model-provider"]
    ) throws -> URL {
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)

        var dependencies: [String: String] = [:]
        if let dependency { dependencies["dsh-model-provider"] = dependency }
        let manifest: [String: Any] = [
            "dependencies": dependencies,
            "dsh": ["profile": ["bundles": bundles]]
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: profile.appendingPathComponent("package.json"))

        if let installedVersion {
            let packageDirectory = profile.appendingPathComponent("node_modules/dsh-model-provider", isDirectory: true)
            try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            let package: [String: Any] = ["name": "dsh-model-provider", "version": installedVersion]
            try JSONSerialization.data(withJSONObject: package).write(to: packageDirectory.appendingPathComponent("package.json"))
        }
        return profile
    }

    private var descriptor: BundledPluginDescriptor {
        BundledPluginDescriptor(
            packageName: "dsh-model-provider",
            packageSpec: "file:/bundle/dsh-model-provider",
            expectedVersion: "0.1.0",
            bundleIdentifier: "dsh-model-provider"
        )
    }

    func testCompleteInstallationIsNoOp() throws {
        let profile = try makeProfile()

        XCTAssertFalse(BundledPluginReadiness.needsInstall(descriptor, in: profile))
    }

    func testMissingManifestDependencyTriggersReinstall() throws {
        let profile = try makeProfile(dependency: nil)

        XCTAssertTrue(BundledPluginReadiness.needsInstall(descriptor, in: profile))
    }

    func testMissingInstalledPackageTriggersReinstall() throws {
        let profile = try makeProfile(installedVersion: nil)

        XCTAssertTrue(BundledPluginReadiness.needsInstall(descriptor, in: profile))
    }

    func testStaleInstalledPackageTriggersReinstall() throws {
        let profile = try makeProfile(installedVersion: "0.0.9")

        XCTAssertTrue(BundledPluginReadiness.hasInstallation(descriptor, in: profile))
        XCTAssertTrue(BundledPluginReadiness.needsInstall(descriptor, in: profile))
    }

    func testCompletelyMissingPluginHasNoInstallationToRemove() throws {
        let profile = try makeProfile(dependency: nil, installedVersion: nil, bundles: [])

        XCTAssertFalse(BundledPluginReadiness.hasInstallation(descriptor, in: profile))
        XCTAssertTrue(BundledPluginReadiness.needsInstall(descriptor, in: profile))
    }

    func testMissingBundleActivationTriggersReinstall() throws {
        let profile = try makeProfile(bundles: [])

        XCTAssertTrue(BundledPluginReadiness.needsInstall(descriptor, in: profile))
    }

    func testSuppressedMissingBundleDoesNotReinstallDuringRepairLoop() throws {
        let profile = try makeProfile(bundles: [])

        XCTAssertFalse(BundledPluginReadiness.needsInstall(descriptor, in: profile, excludingBundles: ["dsh-model-provider"]))
    }

    func testRegistryPluginMayRemainAtNewerUpdatedVersion() throws {
        let profile = try makeProfile(dependency: "1.20.1", installedVersion: "1.20.1")
        let registryDescriptor = BundledPluginDescriptor(
            packageName: "dsh-model-provider",
            packageSpec: "dsh-model-provider@1.13.1",
            expectedVersion: nil,
            bundleIdentifier: "dsh-model-provider"
        )

        XCTAssertFalse(BundledPluginReadiness.needsInstall(registryDescriptor, in: profile))
    }

    func testLocalPluginInstallTriesOfflineBeforeNetworkFallback() {
        let base = ["PATH": "/test/bin"]
        let attempts = BundledPluginInstallPolicy.attempts(baseEnvironment: base, packageSpec: "file:/bundle/plugin")

        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts[0].environment["npm_config_offline"], "true")
        XCTAssertEqual(attempts[0].timeoutSeconds, 20)
        XCTAssertNil(attempts[1].environment["npm_config_offline"])
        XCTAssertEqual(attempts[1].timeoutSeconds, 120)
    }

    func testRegistryPluginInstallUsesNetworkDirectly() {
        let attempts = BundledPluginInstallPolicy.attempts(baseEnvironment: [:], packageSpec: "dshmarket@1.13.1")

        XCTAssertEqual(attempts.count, 1)
        XCTAssertNil(attempts[0].environment["npm_config_offline"])
    }
}
