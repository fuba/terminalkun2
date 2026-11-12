import XCTest
import UIKit
import CoreText
import TerminalRenderer
import TerminalCore
@testable import TerminalKun2

@MainActor
final class PresentationTests: XCTestCase {
    func testCompactFontActuallyNarrowsTheTerminalGridWithoutReducingHeight() {
        let base = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let compact = TerminalTypography.font(name: "", size: 14)
        let normalWidth = ("WWWW" as NSString).size(withAttributes: [.font: base]).width
        let compactWidth = ("WWWW" as NSString).size(withAttributes: [.font: compact]).width
        XCTAssertLessThan(compactWidth, normalWidth)
        XCTAssertGreaterThan(compactWidth, normalWidth * 0.88)
        XCTAssertEqual(CTFontGetAscent(compact), CTFontGetAscent(base), accuracy: 0.1)
        let view = SessionTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 240), font: base, options: TerminalOptions(cols: 80, rows: 24))
        let originalColumns = view.terminalDimensions.cols
        view.font = compact
        XCTAssertGreaterThan(view.terminalDimensions.cols, originalColumns)
    }
    func testCompositionPanelHasNoPresenceWhenIdleAndKeepsLongTextReachable() {
        let panel = CompositionPanel()
        XCTAssertTrue(panel.isHidden)
        let state = CompositionState(reading: String(repeating: "日本語", count: 40), segments: [], selectedSegment: 0, candidates: ["日本語", "にほんご"], selectedCandidate: 0, converting: false)
        panel.update(state)
        XCTAssertFalse(panel.isHidden)
        let size = panel.preferredSize(maxWidth: 240)
        XCTAssertLessThanOrEqual(size.width, 240)
        panel.frame = CGRect(origin: .zero, size: size); panel.layoutIfNeeded()
        let label = panel.compositionLabel
        XCTAssertEqual(label.text, state.reading)
        XCTAssertGreaterThan(label.frame.width, panel.bounds.width)
        panel.update(.empty)
        XCTAssertTrue(panel.isHidden)
    }
    func testShortViewportUsesOneRowWithFullHeightCandidateTargets() {
        let panel = CompositionPanel()
        panel.update(CompositionState(reading: "にほんご", segments: [.init("日本語")], selectedSegment: 0,
            candidates: ["日本語", "にほんご"], selectedCandidate: 0, converting: true))
        panel.frame = CGRect(origin: .zero, size: panel.preferredSize(maxWidth: 500, compact: true))
        panel.layoutIfNeeded()
        XCTAssertEqual(panel.bounds.height, 44)
        let candidates = panel.subviews.first { $0.accessibilityIdentifier == "candidateList" }!
        let button = candidates.accessibilityElements!.first as! UIButton
        XCTAssertEqual(button.frame.height, 44)
        XCTAssertLessThan(panel.compositionLabel.superview!.frame.maxX, candidates.frame.minX)
        XCTAssertTrue(button.accessibilityTraits.contains(.selected))
    }
}

extension PresentationTests {
    func testLinkHitTestingUsesActualSixPointGrid() throws {
        let view = SessionTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 120), font: nil, options: TerminalOptions(cols: 80, rows: 24))
        view.font = TerminalTypography.font(name: "", size: 6)
        view.feed(text: "日  https://example.test/a\r\n")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            view.visibleRowsText(0..<1).first?.contains("https://") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
        let cell = view.caretFrame.size
        let point = CGPoint(x: cell.width * 5.5, y: cell.height * 0.5)
        XCTAssertEqual(view.webLink(at: point)?.absoluteString, "https://example.test/a")
        XCTAssertNil(view.webLink(at: CGPoint(x: cell.width * 1.5, y: point.y)))
    }
}
