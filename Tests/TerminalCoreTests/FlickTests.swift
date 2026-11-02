// MIT License
import XCTest
@testable import TerminalCore

final class FlickTests: XCTestCase {
    func testFiveDirectionsReturningToCenterAndCancellation() {
        var gesture = FlickGesture(start: CGPoint(x: 100, y: 100))
        XCTAssertEqual(gesture.direction, .center)
        gesture.move(to: CGPoint(x: 65, y: 100)); XCTAssertEqual(gesture.direction, .left)
        gesture.move(to: CGPoint(x: 100, y: 65)); XCTAssertEqual(gesture.direction, .up)
        gesture.move(to: CGPoint(x: 135, y: 100)); XCTAssertEqual(gesture.direction, .right)
        gesture.move(to: CGPoint(x: 100, y: 135)); XCTAssertEqual(gesture.direction, .down)
        gesture.move(to: CGPoint(x: 104, y: 105)); XCTAssertEqual(gesture.direction, .center)
        gesture.move(to: CGPoint(x: 300, y: 100)); XCTAssertTrue(gesture.cancelled)
        gesture.move(to: CGPoint(x: 100, y: 100)); XCTAssertTrue(gesture.cancelled)
    }
    func testDeadZoneAndDiagonalHysteresis() {
        var gesture = FlickGesture(start: .zero)
        gesture.move(to: CGPoint(x: 10, y: 2)); XCTAssertEqual(gesture.direction, .center)
        gesture.move(to: CGPoint(x: 30, y: 25)); XCTAssertEqual(gesture.direction, .right)
        gesture.move(to: CGPoint(x: 29, y: 30)); XCTAssertEqual(gesture.direction, .right)
        gesture.move(to: CGPoint(x: 20, y: 35)); XCTAssertEqual(gesture.direction, .down)
    }
    func testKanaAndNumericLayoutHaveUniqueReachableMappings() {
        let kana = JapaneseFlickLayout.kana
        XCTAssertEqual(kana.count, 11)
        XCTAssertEqual(kana.first?.text(.left), "い")
        XCTAssertEqual(kana.first?.text(.down), "お")
        XCTAssertEqual(kana.first(where: { $0.id == "kana-wa" })?.text(.up), "ん")
        XCTAssertEqual(Set(kana.map(\.id)).count, kana.count)
        for number in 0...9 { XCTAssertTrue(JapaneseFlickLayout.numbers.contains { $0.text(.center) == String(number) }) }
    }
    func testKanaVariantsAndNonKanaNeverAppendStrayMarks() {
        XCTAssertEqual(KanaVariant.cycle.apply(to: "は"), "ば")
        XCTAssertEqual(KanaVariant.cycle.apply(to: "ば"), "ぱ")
        XCTAssertEqual(KanaVariant.cycle.apply(to: "ぱ"), "は")
        XCTAssertEqual(KanaVariant.voiced.apply(to: "か"), "が")
        XCTAssertEqual(KanaVariant.voiced.apply(to: "が"), "か")
        XCTAssertEqual(KanaVariant.small.apply(to: "つ"), "っ")
        XCTAssertEqual(KanaVariant.large.apply(to: "っ"), "つ")
        XCTAssertEqual(KanaVariant.small.apply(to: "ヨ"), "ョ")
        XCTAssertEqual(KanaVariant.semiVoiced.apply(to: "ハ"), "パ")
        XCTAssertNil(KanaVariant.cycle.apply(to: "。"))
        XCTAssertNil(KanaVariant.voiced.apply(to: "a"))
    }
}
