// MIT License
import XCTest
import UIKit
import TerminalCore
@testable import TerminalKun2

@MainActor
final class FlickKeyboardTests: XCTestCase {
    // Match the app's process-long store and MetricKit subscriber lifetime.
    private static let store = AppStore()
    private final class Presenter: CompositionPresenting {
        var state = CompositionState.empty
        func presentComposition(_ state: CompositionState) { self.state = state }
    }
    private func key(_ id: String, in keyboard: ProgramKeyboard) throws -> CGRect {
        let elements = keyboard.accessibilityElements as? [UIAccessibilityElement] ?? []
        return try XCTUnwrap(elements.first { $0.accessibilityIdentifier == "program-key-" + id }).accessibilityFrameInContainerSpace
    }
    private func makeKeyboard(_ store: AppStore) -> (TerminalSession, ProgramKeyboard, Presenter) {
        let session = TerminalSession(record: .init(id: UUID(), profileID: UUID(), title: "Owned flick test"), store: store)
        let keyboard = session.keyboard, presenter = Presenter()
        keyboard.compositionPresenter = presenter; keyboard.handle("language")
        keyboard.frame = CGRect(x: 0, y: 0, width: 390, height: 248); keyboard.layoutIfNeeded()
        return (session, keyboard, presenter)
    }
    func testDeferredFlickCommitCancellationAndIndependentFingers() throws {
        let (session, keyboard, presenter) = makeKeyboard(Self.store)
        let first = NSObject(), second = NSObject(), a = try key("kana-a", in: keyboard), ka = try key("kana-ka", in: keyboard)
        let id = ObjectIdentifier(first), other = ObjectIdentifier(second)
        keyboard.beginPress(id, at: CGPoint(x: a.midX, y: a.midY))
        keyboard.movePress(id, to: CGPoint(x: a.midX - 36, y: a.midY))
        XCTAssertEqual(presenter.state.reading, "")
        keyboard.beginPress(other, at: CGPoint(x: ka.midX, y: ka.midY))
        keyboard.movePress(other, to: CGPoint(x: ka.midX + 36, y: ka.midY))
        keyboard.endPress(other, cancelled: false); keyboard.endPress(id, cancelled: false)
        XCTAssertEqual(presenter.state.reading, "けい")
        keyboard.beginPress(id, at: CGPoint(x: a.midX, y: a.midY)); keyboard.endPress(id, cancelled: true)
        XCTAssertEqual(presenter.state.reading, "けい")
        keyboard.beginPress(id, at: CGPoint(x: a.midX, y: a.midY))
        keyboard.frame.size.width = 844; keyboard.setNeedsLayout(); keyboard.layoutIfNeeded()
        keyboard.endPress(id, cancelled: false)
        XCTAssertEqual(presenter.state.reading, "けい")
        XCTAssertTrue(session.draft.text.isEmpty)
        keyboard.handle("enter"); XCTAssertEqual(session.draft.text, "けい")
        XCTAssertTrue(presenter.state.reading.isEmpty)
    }
    func testHoldingKanaDoesNotRepeatAndResetStopsPendingDelete() async throws {
        let (session, keyboard, presenter) = makeKeyboard(Self.store)
        let finger = NSObject(), id = ObjectIdentifier(finger), a = try key("kana-a", in: keyboard)
        keyboard.beginPress(id, at: CGPoint(x: a.midX, y: a.midY))
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertTrue(presenter.state.reading.isEmpty)
        keyboard.endPress(id, cancelled: false); XCTAssertEqual(presenter.state.reading, "あ")
        let delete = try key("backspace", in: keyboard)
        keyboard.beginPress(id, at: CGPoint(x: delete.midX, y: delete.midY))
        keyboard.resetInput()
        keyboard.beginPress(id, at: CGPoint(x: a.midX, y: a.midY)); keyboard.endPress(id, cancelled: false)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(presenter.state.reading, "あ")
        XCTAssertTrue(session.draft.text.isEmpty)
    }
    func testFlickAccessibilityChoicesAndKanaKeyTargetSize() throws {
        let (session, keyboard, presenter) = makeKeyboard(Self.store)
        let elements = try XCTUnwrap(keyboard.accessibilityElements as? [UIAccessibilityElement])
        let a = try XCTUnwrap(elements.first { $0.accessibilityIdentifier == "program-key-kana-a" })
        XCTAssertEqual(a.accessibilityCustomActions?.map(\.name), ["い","う","え","お"])
        XCTAssertGreaterThanOrEqual(a.accessibilityFrameInContainerSpace.height, 44)
        let bar = try XCTUnwrap(session.terminal.inputAccessoryView)
        func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let shift = try XCTUnwrap(descendants(bar).first { $0.accessibilityIdentifier == "accessory-shift" } as? UIButton)
        let original = keyboard.onModifiersChanged
        var active = Modifiers()
        keyboard.onModifiersChanged = { flags, locked in active = flags; original?(flags, locked) }
        shift.sendActions(for: .touchUpInside); XCTAssertTrue(active.contains(.shift))
        XCTAssertTrue(a.accessibilityActivate()); XCTAssertEqual(presenter.state.reading, "あ")
        XCTAssertFalse(active.contains(.shift))
        XCTAssertTrue(session.draft.text.isEmpty)
    }
}

extension FlickKeyboardTests {
    func testJapaneseReturnSpansTwoRowsAndEnglishPreviewFollowsPress() throws {
        let (session, keyboard, _) = makeKeyboard(Self.store)
        let enter = try key("enter", in: keyboard)
        XCTAssertGreaterThan(enter.height, try key("kana-ra", in: keyboard).height * 1.8)
        let elements = try XCTUnwrap(keyboard.accessibilityElements as? [UIAccessibilityElement])
        XCTAssertFalse(elements.contains { $0.accessibilityIdentifier == "program-key-hide" })

        keyboard.handle("language"); keyboard.layoutIfNeeded()
        keyboard.handle("shift")
        let a = try key("a", in: keyboard)
        let finger = NSObject(), id = ObjectIdentifier(finger)
        keyboard.beginPress(id, at: CGPoint(x: a.midX, y: a.midY))
        let preview = try XCTUnwrap(keyboard.subviews.first { $0.accessibilityIdentifier == "program-key-preview" } as? UILabel)
        XCTAssertEqual(session.draft.text, "A")
        XCTAssertEqual(preview.text, "A")
        XCTAssertFalse(preview.isHidden)
        XCTAssertLessThan(preview.frame.midY, a.midY)
        keyboard.endPress(id, cancelled: false)
        XCTAssertTrue(preview.isHidden)
        keyboard.handle("sequences"); keyboard.layoutIfNeeded()
        XCTAssertTrue(keyboard.showingSequences)
        for sequence in Self.store.configuration.effectiveKeySequences {
            XCTAssertNoThrow(try key("sequence-" + sequence.id.uuidString, in: keyboard))
        }
        keyboard.handle("sequences")
        XCTAssertFalse(keyboard.showingSequences)
    }
}
