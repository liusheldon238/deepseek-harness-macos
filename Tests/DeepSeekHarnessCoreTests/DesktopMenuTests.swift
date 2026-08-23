import XCTest
@testable import DeepSeekHarnessCore

final class DesktopMenuTests: XCTestCase {
    func testStandardEditCommandsExposeMacKeyboardShortcuts() {
        let shortcuts = Dictionary(uniqueKeysWithValues: DesktopEditCommand.allCases.map { ($0, $0.keyEquivalent) })
        XCTAssertEqual(shortcuts[.undo], "z")
        XCTAssertEqual(shortcuts[.redo], "Z")
        XCTAssertEqual(shortcuts[.cut], "x")
        XCTAssertEqual(shortcuts[.copy], "c")
        XCTAssertEqual(shortcuts[.paste], "v")
        XCTAssertEqual(shortcuts[.selectAll], "a")
    }
}
