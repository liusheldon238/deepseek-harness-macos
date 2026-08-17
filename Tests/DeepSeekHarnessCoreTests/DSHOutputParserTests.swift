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
}
