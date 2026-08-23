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
}
