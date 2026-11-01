import XCTest
import CoreGraphics
@testable import TerminalCore

final class CompositionLayoutTests: XCTestCase {
    func testPanelPrefersBelowCaretWithoutCoveringIt() {
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 400)
        let caret = CGRect(x: 40, y: 40, width: 8, height: 20)
        let panel = CompositionLayout.frame(viewport: viewport, caret: caret, desired: CGSize(width: 230, height: 74))
        XCTAssertTrue(viewport.contains(panel))
        XCTAssertGreaterThan(panel.minY, caret.maxY)
        XCTAssertFalse(panel.intersects(caret))
    }
    func testBottomRightAndLandscapeStayInsideViewport() {
        for viewport in [CGRect(x: 0, y: 0, width: 390, height: 400), CGRect(x: 0, y: 0, width: 800, height: 110)] {
            let caret = CGRect(x: viewport.maxX - 12, y: viewport.maxY - 24, width: 8, height: 20)
            let panel = CompositionLayout.frame(viewport: viewport, caret: caret, desired: CGSize(width: 300, height: 74))
            XCTAssertTrue(viewport.contains(panel))
            XCTAssertLessThan(panel.maxY, caret.minY)
            XCTAssertFalse(panel.intersects(caret))
        }
    }
    func testLongCompositionAndTinyViewportsRemainBounded() {
        let viewport = CGRect(x: 0, y: 0, width: 180, height: 50)
        let panel = CompositionLayout.frame(viewport: viewport, caret: .zero, desired: CGSize(width: 1000, height: 200))
        XCTAssertTrue(viewport.contains(panel))
        XCTAssertEqual(CompositionLayout.frame(viewport: .zero, caret: .zero, desired: CGSize(width: 100, height: 50)), .zero)
    }
}
