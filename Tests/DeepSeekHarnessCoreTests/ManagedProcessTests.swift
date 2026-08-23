import Darwin
import Foundation
import XCTest
@testable import DeepSeekHarnessCore

final class ManagedProcessTests: XCTestCase {
    private func waitForFile(_ url: URL, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(url.path)")
    }

    func testSpawnCreatesProcessGroupBeforeDescendantStartsAndTerminatesWholeGroup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let childPIDFile = root.appendingPathComponent("child.pid")
        let command = "sleep 30 & child=$!; printf '%s' \"$child\" > \"\(childPIDFile.path)\"; wait"

        let process = try ManagedProcess.spawn(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command],
            environment: ProcessInfo.processInfo.environment,
            currentDirectory: root,
            output: nil
        )
        try await waitForFile(childPIDFile)
        let childPID = try XCTUnwrap(pid_t(String(contentsOf: childPIDFile, encoding: .utf8)))

        XCTAssertEqual(getpgid(process.processIdentifier), process.processIdentifier)
        XCTAssertEqual(getpgid(childPID), process.processIdentifier)

        await process.terminate(grace: .milliseconds(100))

        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(kill(childPID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testRunTimesOutAndKillsDescendants() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let childPIDFile = root.appendingPathComponent("timeout-child.pid")
        let command = "sleep 30 & child=$!; printf '%s' \"$child\" > \"\(childPIDFile.path)\"; wait"

        do {
            _ = try await ManagedProcess.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", command],
                environment: ProcessInfo.processInfo.environment,
                currentDirectory: root,
                output: nil,
                timeout: .milliseconds(150)
            )
            XCTFail("Expected timeout")
        } catch RuntimeError.processTimedOut { }

        try await waitForFile(childPIDFile)
        let childPID = try XCTUnwrap(pid_t(String(contentsOf: childPIDFile, encoding: .utf8)))
        XCTAssertEqual(kill(childPID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }
}
