import Foundation
import XCTest
@testable import DeepSeekHarnessCore

final class OwnedBackendRecordTests: XCTestCase {
    private let support = URL(fileURLWithPath: "/Users/test/Library/Application Support/DeepSeek Harness Desktop")
    private var identity: BackendProcessIdentity {
        BackendProcessIdentity(
            pid: 42,
            uid: 501,
            processGroupID: 42,
            startTime: 1234,
            executablePath: "/Users/test/Library/Application Support/DeepSeek Harness Desktop/runtime/v22/bin/node",
            command: "/Users/test/Library/Application Support/DeepSeek Harness Desktop/runtime/v22/bin/node /Users/test/Library/Application Support/DeepSeek Harness Desktop/dsh-runtime/node_modules/@deepseek-ai/dsh/lib/bin.js web --host 127.0.0.1 --port 0 --no-open"
        )
    }

    func testRecordMatchesOnlyExactOwnedDSHWebIdentity() {
        let record = OwnedBackendRecord(identity: identity)

        XCTAssertTrue(record.matches(identity, supportDirectory: support))
        XCTAssertFalse(record.matches(BackendProcessIdentity(pid: 42, uid: 502, processGroupID: 42, startTime: 1234, executablePath: identity.executablePath, command: identity.command), supportDirectory: support))
        XCTAssertFalse(record.matches(BackendProcessIdentity(pid: 42, uid: 501, processGroupID: 42, startTime: 9999, executablePath: identity.executablePath, command: identity.command), supportDirectory: support))
        XCTAssertFalse(record.matches(BackendProcessIdentity(pid: 42, uid: 501, processGroupID: 99, startTime: 1234, executablePath: identity.executablePath, command: identity.command), supportDirectory: support))
        XCTAssertFalse(record.matches(BackendProcessIdentity(pid: 42, uid: 501, processGroupID: 42, startTime: 1234, executablePath: "/usr/local/bin/node", command: identity.command), supportDirectory: support))
        XCTAssertFalse(record.matches(BackendProcessIdentity(pid: 42, uid: 501, processGroupID: 42, startTime: 1234, executablePath: identity.executablePath, command: "node worker.js"), supportDirectory: support))
    }

    func testRegistryReclaimsMatchingRecordAndPreservesUnrelatedProcess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let recordURL = root.appendingPathComponent("backend.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let record = OwnedBackendRecord(identity: identity)
        try JSONEncoder().encode(record).write(to: recordURL)
        var terminated: [pid_t] = []
        let registry = OwnedBackendRegistry(
            recordURL: recordURL,
            supportDirectory: support,
            inspect: { _ in self.identity },
            terminateGroup: { terminated.append($0) }
        )

        XCTAssertTrue(try registry.reclaimStaleBackend())
        XCTAssertEqual(terminated, [42])
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))

        try JSONEncoder().encode(record).write(to: recordURL)
        let unrelated = OwnedBackendRegistry(
            recordURL: recordURL,
            supportDirectory: support,
            inspect: { _ in BackendProcessIdentity(pid: 42, uid: 501, processGroupID: 42, startTime: 9999, executablePath: "/usr/local/bin/node", command: "node web") },
            terminateGroup: { terminated.append($0) }
        )
        XCTAssertFalse(try unrelated.reclaimStaleBackend())
        XCTAssertEqual(terminated, [42])
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))
    }
}
