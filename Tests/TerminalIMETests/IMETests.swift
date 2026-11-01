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
        XCTAssertEqual(engine.reading, "こんにちは")
        XCTAssertFalse(engine.commit().isEmpty)
        XCTAssertTrue(engine.reading.isEmpty)
    }
    @MainActor func testSegmentsBoundariesAndPersistentLearning() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = JapaneseInput(memory: folder)
        engine.insert("nihongowonyuuryokusuru"); engine.convert()
        XCTAssertGreaterThan(engine.segments.count, 1)
        let before = engine.segments.map(\.reading).joined()
        engine.adjustBoundary(1)
        XCTAssertEqual(engine.segments.map(\.reading).joined(), before)
        engine.moveSegment(1); XCTAssertEqual(engine.selectedSegment, 1)
        XCTAssertFalse(engine.commit().isEmpty)
        engine.words = [.init(reading: "ふば", word: "fuba")]
        engine.insert("fuba")
        let index = try XCTUnwrap(engine.candidates.firstIndex(of: "fuba"))
        XCTAssertEqual(engine.commit(index: index), "fuba")
        let restored = JapaneseInput(memory: folder); restored.insert("fuba")
        XCTAssertEqual(restored.candidates.first, "fuba")
    }
}
