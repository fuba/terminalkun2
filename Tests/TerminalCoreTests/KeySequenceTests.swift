import XCTest
@testable import TerminalCore

final class KeySequenceTests: XCTestCase {
    func testCopyModeUsesLiteralControlBytesAndCursorMode() {
        XCTAssertEqual(KeySequence.encode("^A ^["), "\u{1}\u{1b}")
        XCTAssertEqual(KeySequence.encode("^B ["), "\u{2}[")
        XCTAssertEqual(KeySequence.encode("M-x Space Enter"), "\u{1b}x \r")
        XCTAssertEqual(KeySequence.encode("Up", applicationCursor: true), "\u{1b}OA")
    }

    func testRejectsInvalidOrOversizedSequences() {
        for value in ["", "^é", "^1", "bogus", "Escape\nEnter", String(repeating: "a ", count: 33)] {
            XCTAssertNil(KeySequence.encode(value), value)
        }
    }

    func testLegacyConfigurationAndMinimumFontSize() throws {
        var config = AppConfiguration()
        XCTAssertNil(config.keySequences)
        config.appearance.fontSize = 6
        let copy = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(config))
        try copy.validate()
        XCTAssertEqual(copy.effectiveKeySequences, KeySequence.defaults)
        config.keySequences = []
        XCTAssertTrue(config.effectiveKeySequences.isEmpty)
        config.appearance.fontSize = 5
        XCTAssertThrowsError(try config.validate())
    }
}
