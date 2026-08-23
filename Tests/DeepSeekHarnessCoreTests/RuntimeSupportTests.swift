import XCTest
@testable import DeepSeekHarnessCore

final class RuntimeSupportTests: XCTestCase {
    func testVersionComparisonUsesSemanticComponents() throws {
        XCTAssertLessThan(try SemVer("22.19.0"), try SemVer("22.23.1"))
        XCTAssertGreaterThanOrEqual(try SemVer("22.23.1"), try SemVer("22.19.0"))
        XCTAssertThrowsError(try SemVer("22.23"))
    }

    func testSemVerNormalizesLeadingVAndWhitespace() throws {
        XCTAssertEqual(try SemVer("  v22.19.0\n").description, "22.19.0")
        XCTAssertEqual(try SemVer("V22.23.1").description, "22.23.1")
        XCTAssertEqual(try SemVer("22.0.0").description, "22.0.0")
    }

    func testSemVerRejectsInvalidVersions() {
        for value in ["22.23", "22.23.1.0", "22.23.1-rc.1", "22.x.1", "-1.0.0", "22.19.-1", ""] {
            XCTAssertThrowsError(try SemVer(value), "Expected SemVer to reject \(value)")
        }
    }

    func testNodeArchitectureParsesProcessArch() {
        XCTAssertEqual(NodeArchitecture(nodeProcessArchitecture: "arm64"), .arm64)
        XCTAssertEqual(NodeArchitecture(nodeProcessArchitecture: "aarch64"), .arm64)
        XCTAssertEqual(NodeArchitecture(nodeProcessArchitecture: " x86_64\n"), .x64)
        XCTAssertEqual(NodeArchitecture(nodeProcessArchitecture: "x64"), .x64)
        XCTAssertNil(NodeArchitecture(nodeProcessArchitecture: "arm"))
        XCTAssertNil(NodeArchitecture(nodeProcessArchitecture: ""))
    }

    func testOnlyCompatibleNodeIsAccepted() throws {
        let minimum = try SemVer("22.19.0")
        XCTAssertTrue(NodeCompatibility.isCompatible(version: try SemVer("22.23.1"), architecture: .arm64, hostArchitecture: .arm64, minimum: minimum))
        XCTAssertTrue(NodeCompatibility.isCompatible(version: minimum, architecture: .arm64, hostArchitecture: .arm64, minimum: minimum))
        XCTAssertFalse(NodeCompatibility.isCompatible(version: try SemVer("22.18.0"), architecture: .arm64, hostArchitecture: .arm64, minimum: minimum))
        XCTAssertFalse(NodeCompatibility.isCompatible(version: try SemVer("22.23.1"), architecture: .x64, hostArchitecture: .arm64, minimum: minimum))
    }

    func testNodeDistributionUsesOfficialArchitectureSpecificURL() throws {
        let arm = NodeDistribution(version: try SemVer("22.23.1"), architecture: .arm64)
        XCTAssertEqual(arm.archiveURL.absoluteString, "https://nodejs.org/dist/v22.23.1/node-v22.23.1-darwin-arm64.tar.gz")
        XCTAssertEqual(arm.archiveName, "node-v22.23.1-darwin-arm64.tar.gz")
        XCTAssertEqual(arm.checksumsURL.absoluteString, "https://nodejs.org/dist/v22.23.1/SHASUMS256.txt")
        let intel = NodeDistribution(version: try SemVer("22.23.1"), architecture: .x64)
        XCTAssertEqual(intel.archiveURL.absoluteString, "https://nodejs.org/dist/v22.23.1/node-v22.23.1-darwin-x64.tar.gz")
        XCTAssertEqual(intel.archiveName, "node-v22.23.1-darwin-x64.tar.gz")
        XCTAssertEqual(intel.checksumsURL.absoluteString, "https://nodejs.org/dist/v22.23.1/SHASUMS256.txt")
    }
}
