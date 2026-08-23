import XCTest
@testable import DeepSeekHarnessCore

final class DSHOutputParserTests: XCTestCase {
    func testParsesDSHListeningURL() throws {
        let url = try XCTUnwrap(DSHOutputParser.url(from: "dsh web: http://127.0.0.1:43127"))
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.port, 43127)
    }

    func testIgnoresUnrelatedOutput() {
        XCTAssertNil(DSHOutputParser.url(from: "npm warn deprecated package"))
    }

    func testFindsLoopbackURLAnywhereInLine() throws {
        let url = try XCTUnwrap(DSHOutputParser.url(from: "started at 10:00 · http://127.0.0.1:65535 · pid 42"))
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:65535")
        XCTAssertEqual(url.port, 65535)
    }

    func testParsesOSSelectedPortZero() throws {
        let url = try XCTUnwrap(DSHOutputParser.url(from: "dsh web: http://127.0.0.1:0"))
        XCTAssertEqual(url.port, 0)
    }

    func testRejectsNonLoopbackOrInvalidHosts() {
        XCTAssertNil(DSHOutputParser.url(from: "http://localhost:43127"))
        XCTAssertNil(DSHOutputParser.url(from: "http://127.0.0.2:43127"))
        XCTAssertNil(DSHOutputParser.url(from: "https://127.0.0.1:43127"))
        XCTAssertNil(DSHOutputParser.url(from: "http://127.0.0.1:not-a-port"))
    }
}
