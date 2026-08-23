import Foundation
import XCTest
@testable import DeepSeekHarnessCore

final class DSHHealthCheckerTests: XCTestCase {
    private func response(for request: URLRequest, status: Int = 200, body: [String: Any]) throws -> (Data, HTTPURLResponse) {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil))
        return (data, response)
    }

    func testDomainPreflightRequiresRootAndBothRPCMethods() async throws {
        let recorder = PathRecorder()
        let checker = DSHHealthChecker { request in
            await recorder.append(request.url?.path ?? "")
            if request.httpMethod == "GET" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data("<html>DeepSeek Harness</html>".utf8), response)
            }
            let envelope = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            return try self.response(for: request, body: ["type": "server-response", "rpcId": envelope["rpcId"]!, "result": ["ok": true, "value": [:]]])
        }

        let report = try await checker.check(baseURL: URL(string: "http://127.0.0.1:1234")!)
        let paths = await recorder.values()

        XCTAssertEqual(report.methods, ["agentPreset.list", "settings.describe"])
        XCTAssertEqual(paths, ["/", "/api/agentPreset.list", "/api/settings.describe"])
    }

    func testDomainPreflightRejectsHTTP200WithFailedRPC() async throws {
        let checker = DSHHealthChecker { request in
            if request.httpMethod == "GET" {
                return (Data("<html></html>".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let envelope = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            return try self.response(for: request, body: ["type": "server-response", "rpcId": envelope["rpcId"]!, "result": ["ok": false, "error": ["message": "preset unavailable"]]])
        }

        do {
            _ = try await checker.check(baseURL: URL(string: "http://127.0.0.1:1234")!)
            XCTFail("Expected domain failure")
        } catch RuntimeError.domainHealthFailed(let method, _) {
            XCTAssertEqual(method, "agentPreset.list")
        }
    }

    func testDomainPreflightRejectsMismatchedRPCIdentity() async throws {
        let checker = DSHHealthChecker { request in
            if request.httpMethod == "GET" {
                return (Data("<html></html>".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return try self.response(for: request, body: ["type": "server-response", "rpcId": "stale-generation", "result": ["ok": true, "value": [:]]])
        }

        await XCTAssertThrowsErrorAsync(try await checker.check(baseURL: URL(string: "http://127.0.0.1:1234")!))
    }

    func testRecoveryRequestBypassesLocalCache() {
        let url = URL(string: "http://127.0.0.1:1234")!
        XCTAssertEqual(WebRecoveryRequest.make(url: url, recovering: false).cachePolicy, .useProtocolCachePolicy)
        XCTAssertEqual(WebRecoveryRequest.make(url: url, recovering: true).cachePolicy, .reloadIgnoringLocalCacheData)
    }
}

private actor PathRecorder {
    private var paths: [String] = []
    func append(_ path: String) { paths.append(path) }
    func values() -> [String] { paths }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch { }
}
