import Foundation
import XCTest
@testable import DeepSeekHarnessCore

final class ProfileTransactionTests: XCTestCase {
    func testRecoverPendingRestoresProfileAfterInterruptedTransaction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = root.appendingPathComponent("profiles/web")
        let snapshots = root.appendingPathComponent("snapshots")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data("verified".utf8).write(to: profile.appendingPathComponent("state.txt"))
        _ = try ProfileTransaction.begin(profileDirectory: profile, snapshotsDirectory: snapshots)
        try Data("interrupted".utf8).write(to: profile.appendingPathComponent("state.txt"))

        XCTAssertTrue(try ProfileTransaction.recoverPending(profileDirectory: profile, snapshotsDirectory: snapshots))
        XCTAssertEqual(try String(contentsOf: profile.appendingPathComponent("state.txt"), encoding: .utf8), "verified")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: snapshots.path), [])
    }

    func testRecoverPendingRemovesProfileCreatedByInterruptedFirstRun() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = root.appendingPathComponent("profiles/web")
        let snapshots = root.appendingPathComponent("snapshots")
        _ = try ProfileTransaction.begin(profileDirectory: profile, snapshotsDirectory: snapshots)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)

        XCTAssertTrue(try ProfileTransaction.recoverPending(profileDirectory: profile, snapshotsDirectory: snapshots))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.path))
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }

    func testRestoreReplacesEntireProfileIncludingInstalledPackagesAndDisabledState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = root.appendingPathComponent("profiles/web")
        let snapshots = root.appendingPathComponent("snapshots")
        try write("old-manifest", to: profile.appendingPathComponent("package.json"))
        try write("old-plugin", to: profile.appendingPathComponent("node_modules/example/index.js"))
        try write("old-disabled", to: profile.appendingPathComponent("disabled-plugins.json"))
        let transaction = try ProfileTransaction.begin(profileDirectory: profile, snapshotsDirectory: snapshots)

        try write("new-manifest", to: profile.appendingPathComponent("package.json"))
        try FileManager.default.removeItem(at: profile.appendingPathComponent("node_modules/example"))
        try write("partial-plugin", to: profile.appendingPathComponent("node_modules/partial/index.js"))
        try write("new-disabled", to: profile.appendingPathComponent("disabled-plugins.json"))

        try transaction.restore()

        XCTAssertEqual(try String(contentsOf: profile.appendingPathComponent("package.json"), encoding: .utf8), "old-manifest")
        XCTAssertEqual(try String(contentsOf: profile.appendingPathComponent("node_modules/example/index.js"), encoding: .utf8), "old-plugin")
        XCTAssertEqual(try String(contentsOf: profile.appendingPathComponent("disabled-plugins.json"), encoding: .utf8), "old-disabled")
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("node_modules/partial").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.directory.path))
    }

    func testCommitRemovesCurrentAndStaleSnapshots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = root.appendingPathComponent("profiles/web")
        let snapshots = root.appendingPathComponent("snapshots")
        try write("manifest", to: profile.appendingPathComponent("package.json"))
        try write("legacy", to: snapshots.appendingPathComponent("legacy/package.json"))
        let transaction = try ProfileTransaction.begin(profileDirectory: profile, snapshotsDirectory: snapshots)

        try transaction.commit()

        let remaining = try FileManager.default.contentsOfDirectory(atPath: snapshots.path)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRestoreRemovesProfileCreatedAfterSnapshotOfMissingProfile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = root.appendingPathComponent("profiles/web")
        let transaction = try ProfileTransaction.begin(profileDirectory: profile, snapshotsDirectory: root.appendingPathComponent("snapshots"))
        try write("created", to: profile.appendingPathComponent("package.json"))

        try transaction.restore()

        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.path))
    }
}
