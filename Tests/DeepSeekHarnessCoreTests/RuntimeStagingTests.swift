import Foundation
import XCTest
@testable import DeepSeekHarnessCore

final class RuntimeStagingTests: XCTestCase {
    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }

    func testDiscardLeavesVerifiedRuntimeUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("dsh-runtime")
        try write("verified", to: target.appendingPathComponent("version"))
        let staging = try RuntimeStaging.begin(targetDirectory: target)
        try write("broken", to: staging.directory.appendingPathComponent("version"))

        try staging.discard()

        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("version"), encoding: .utf8), "verified")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.directory.path))
    }

    func testPromoteAtomicallyReplacesVerifiedRuntime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("dsh-runtime")
        try write("verified", to: target.appendingPathComponent("version"))
        let staging = try RuntimeStaging.begin(targetDirectory: target)
        try write("candidate", to: staging.directory.appendingPathComponent("version"))

        try staging.promote()

        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("version"), encoding: .utf8), "candidate")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.directory.path))
    }
}
