import Foundation
import XCTest
@testable import DeepSeekHarnessCore

final class SelfHealingStartupTests: XCTestCase {
    func testLatestSemVerIgnoresInvalidValues() {
        XCTAssertEqual(StartupSemVer.latest(["0.1.0", "v0.2.0", "bad", "0.1.9"]), "0.2.0")
        XCTAssertNil(StartupSemVer.latest(["bad", "0.2"]))
    }

    func testDSHReleaseSelectionDoesNotDowngradeFromNewerNPMPrerelease() {
        XCTAssertEqual(
            DSHReleaseSelection.latest(githubTag: "v0.1.0-rc.6", npmVersion: "0.1.1-rc.2"),
            "0.1.1-rc.2"
        )
    }

    func testDSHReleaseSelectionUsesNewerGitHubOrAvailableFallback() {
        XCTAssertEqual(DSHReleaseSelection.latest(githubTag: "v0.2.0-rc.1", npmVersion: "0.1.9"), "0.2.0-rc.1")
        XCTAssertEqual(DSHReleaseSelection.latest(githubTag: nil, npmVersion: "0.1.1-rc.2"), "0.1.1-rc.2")
        XCTAssertEqual(DSHReleaseSelection.latest(githubTag: "v0.1.0-rc.6", npmVersion: nil), "0.1.0-rc.6")
        XCTAssertNil(DSHReleaseSelection.latest(githubTag: "not-a-version", npmVersion: nil))
    }

    func testRegistryPluginUpdateUsesInstalledPackageVersionNotManifestRange() {
        XCTAssertFalse(RegistryPluginUpdate.needsUpdate(installedVersion: "0.26.0", latestVersion: "0.26.0"))
        XCTAssertTrue(RegistryPluginUpdate.needsUpdate(installedVersion: "0.25.3", latestVersion: "0.26.0"))
        XCTAssertFalse(RegistryPluginUpdate.needsUpdate(installedVersion: "0.27.0", latestVersion: "0.26.0"))
        XCTAssertTrue(RegistryPluginUpdate.needsUpdate(installedVersion: nil, latestVersion: "0.26.0"))
    }

    func testClientPluginFailureParsesBrowserRenderedError() {
        let text = """
        Failed to load plugins
        web boot: 1 entry did not activate dsh-agent-preset-advisor: pending
        """
        let failure = ClientPluginFailureParser.failure(from: text)
        XCTAssertEqual(failure?.pluginID, "dsh-agent-preset-advisor")
        XCTAssertTrue(failure?.detail.contains("web boot:") == true)
    }

    func testClientPluginFailureIgnoresHealthyConversationPage() {
        XCTAssertNil(ClientPluginFailureParser.failure(from: "DeepSeek Harness 新建会话 设置"))
    }

    func testStartupLogControlsAreVisibleWhileStartingAndAfterFailure() {
        XCTAssertTrue(StartupLogPresentation.starting.showsControls)
        XCTAssertTrue(StartupLogPresentation.failed.showsControls)
        XCTAssertFalse(StartupLogPresentation.running.showsControls)
        XCTAssertTrue(StartupLogPresentation.failed.expandsLog)
        XCTAssertTrue(StartupLogPresentation.starting.expandsLog)
    }

    func testMatchingLocalDSHVersionUsesStableCLIWithoutInstall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let package = root.appendingPathComponent("node_modules/@deepseek-ai/dsh")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try Data(#"{"version":"0.1.1-rc.2"}"#.utf8).write(to: package.appendingPathComponent("package.json"))
        try Data("#!/usr/bin/env node".utf8).write(to: package.appendingPathComponent("lib/bin.js"))

        try Data("arm64\n".utf8).write(to: root.appendingPathComponent("node-architecture"))
        let local = DSHLocalRuntime.inspect(directory: root, expectedArchitecture: .arm64)
        XCTAssertEqual(local?.version, "0.1.1-rc.2")
        XCTAssertEqual(local?.cliURL, package.appendingPathComponent("lib/bin.js"))
        XCTAssertFalse(DSHLocalRuntime.needsInstall(local: local, latestVersion: "0.1.1-rc.2"))
        XCTAssertTrue(DSHLocalRuntime.needsInstall(local: local, latestVersion: "0.1.2"))
        XCTAssertFalse(DSHLocalRuntime.needsInstall(local: local, latestVersion: "0.1.0-rc.6"))
    }

    func testLocalDSHRuntimeRejectsMissingOrMismatchedArchitectureMarker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let package = root.appendingPathComponent("node_modules/@deepseek-ai/dsh")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try Data(#"{"version":"0.1.1-rc.2"}"#.utf8).write(to: package.appendingPathComponent("package.json"))
        try Data("#!/usr/bin/env node".utf8).write(to: package.appendingPathComponent("lib/bin.js"))

        XCTAssertNil(DSHLocalRuntime.inspect(directory: root, expectedArchitecture: .arm64))
        try Data("x64\n".utf8).write(to: root.appendingPathComponent("node-architecture"))
        XCTAssertNil(DSHLocalRuntime.inspect(directory: root, expectedArchitecture: .arm64))
        try Data("arm64\n".utf8).write(to: root.appendingPathComponent("node-architecture"))
        XCTAssertNotNil(DSHLocalRuntime.inspect(directory: root, expectedArchitecture: .arm64))
    }

    @MainActor
    func testDisablesOnlyPluginNamedByClientFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = root.appendingPathComponent("dsh-home/profiles/web")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["dsh": ["profile": ["bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app", "dshmarket", "dsh-agent-preset-advisor"]]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: profile.appendingPathComponent("package.json"))
        let startup = SelfHealingStartup(supportURL: root)
        let failure = ClientPluginFailure(pluginID: "dsh-agent-preset-advisor", detail: "web boot failed")

        XCTAssertEqual(try startup.disableConflictingPlugin(failure), "dsh-agent-preset-advisor")
        let data = try Data(contentsOf: profile.appendingPathComponent("package.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let dsh = try XCTUnwrap(json["dsh"] as? [String: Any])
        let profileJSON = try XCTUnwrap(dsh["profile"] as? [String: Any])
        let bundles = try XCTUnwrap(profileJSON["bundles"] as? [String])
        XCTAssertTrue(bundles.contains("dshmarket"))
        XCTAssertFalse(bundles.contains("dsh-agent-preset-advisor"))
    }

    @MainActor
    func testGenericPluginFailureDoesNotDisableArbitraryBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = root.appendingPathComponent("dsh-home/profiles/web")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["dsh": ["profile": ["bundles": ["@deepseek-ai/dsh-base", "dshmarket", "dsh-model-search"]]]]
        let manifestURL = profile.appendingPathComponent("package.json")
        let original = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try original.write(to: manifestURL)
        let startup = SelfHealingStartup(supportURL: root)

        XCTAssertNil(try startup.disableConflictingPlugin(ClientPluginFailure(pluginID: "Web plugin startup failed", detail: "generic")))
        let after = try Data(contentsOf: manifestURL)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: after) as? NSDictionary, try JSONSerialization.jsonObject(with: original) as? NSDictionary)
    }

    @MainActor
    func testConflictResolverUsesWholeBundleIdentifierInsteadOfSubstring() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = root.appendingPathComponent("dsh-home/profiles/web")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["dsh": ["profile": ["bundles": ["@deepseek-ai/dsh-base", "dsh-model", "dsh-model-search"]]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: profile.appendingPathComponent("package.json"))
        let startup = SelfHealingStartup(supportURL: root)

        XCTAssertEqual(try startup.disableConflictingPlugin(ClientPluginFailure(pluginID: "dsh-model-search", detail: "web boot failed")), "dsh-model-search")
    }

    func testCorePluginPolicyUsesExplicitAllowlistNotNamespacePrefix() {
        XCTAssertTrue(PluginConflictResolver.isCore("@deepseek-ai/dsh-base"))
        XCTAssertTrue(PluginConflictResolver.isCore("@deepseek-ai/dsh-web-app"))
        XCTAssertFalse(PluginConflictResolver.isCore("@deepseek-ai/dsh-third-party-lookalike"))
    }
}
