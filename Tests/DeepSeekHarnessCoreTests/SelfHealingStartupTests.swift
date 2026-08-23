import Foundation
import XCTest
@testable import DeepSeekHarnessCore

final class SelfHealingStartupTests: XCTestCase {
    func testLatestSemVerIgnoresInvalidValues() {
        XCTAssertEqual(StartupSemVer.latest(["0.1.0", "v0.2.0", "bad", "0.1.9"]), "0.2.0")
        XCTAssertNil(StartupSemVer.latest(["bad", "0.2"]))
    }

    func testSnapshotRestoresProfileFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = root.appendingPathComponent("profile")
        let snapshotDir = root.appendingPathComponent("snapshot")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: snapshotDir.appendingPathComponent("package.json"))
        try Data("new".utf8).write(to: profile.appendingPathComponent("package.json"))
        let snapshot = StartupSnapshot(directory: snapshotDir, profileDirectory: profile, manifestExisted: true, lockfileExisted: false, patchExisted: false)
        try snapshot.restore()
        XCTAssertEqual(try String(contentsOf: profile.appendingPathComponent("package.json")), "old")
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
        XCTAssertFalse(StartupLogPresentation.starting.expandsLog)
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
}
