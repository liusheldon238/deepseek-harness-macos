import XCTest
@testable import DeepSeekHarnessCore

final class RuntimeSupportTests: XCTestCase {
    func testVersionComparisonUsesSemanticComponents() throws {
        XCTAssertLessThan(try SemVer("22.19.0"), try SemVer("22.23.1"))
        XCTAssertGreaterThanOrEqual(try SemVer("22.23.1"), try SemVer("22.19.0"))
        XCTAssertThrowsError(try SemVer("22.23"))
    }

    func testOnlyCompatibleNodeIsAccepted() throws {
        let minimum = try SemVer("22.19.0")
        XCTAssertTrue(NodeCompatibility.isCompatible(version: try SemVer("22.23.1"), architecture: .arm64, hostArchitecture: .arm64, minimum: minimum))
        XCTAssertFalse(NodeCompatibility.isCompatible(version: try SemVer("22.18.0"), architecture: .arm64, hostArchitecture: .arm64, minimum: minimum))
        XCTAssertFalse(NodeCompatibility.isCompatible(version: try SemVer("22.23.1"), architecture: .x64, hostArchitecture: .arm64, minimum: minimum))
    }

    func testNodeDistributionUsesOfficialArchitectureSpecificURL() throws {
        let arm = NodeDistribution(version: try SemVer("22.23.1"), architecture: .arm64)
        XCTAssertEqual(arm.archiveURL.absoluteString, "https://nodejs.org/dist/v22.23.1/node-v22.23.1-darwin-arm64.tar.gz")
        let intel = NodeDistribution(version: try SemVer("22.23.1"), architecture: .x64)
        XCTAssertEqual(intel.archiveURL.absoluteString, "https://nodejs.org/dist/v22.23.1/node-v22.23.1-darwin-x64.tar.gz")
    }
}
