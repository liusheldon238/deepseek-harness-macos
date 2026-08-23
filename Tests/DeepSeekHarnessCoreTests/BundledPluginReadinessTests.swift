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
}
