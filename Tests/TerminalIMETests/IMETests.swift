import XCTest
@testable import TerminalIME

final class IMETests: XCTestCase {
    @MainActor func testRealDictionaryConversionAndModeBoundary() {
        let engine = JapaneseInput()
        engine.insert("nihongo")
        XCTAssertEqual(engine.reading, "にほんご")
        engine.convert()
        XCTAssertTrue(engine.candidates.contains("日本語"), "Real bundled dictionary must produce 日本語")
        engine.cancel()
        XCTAssertTrue(engine.reading.isEmpty)
        engine.insert("konnichiha")
        XCTAssertFalse(engine.commit().isEmpty)
        XCTAssertTrue(engine.reading.isEmpty)
    }
}
