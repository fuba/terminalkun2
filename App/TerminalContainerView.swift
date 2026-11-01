import UIKit
import TerminalCore

@MainActor
final class TerminalContainerView: UIView, CompositionPresenting {
    let terminal: SessionTerminalView
    private weak var session: TerminalSession?
    private let panel = CompositionPanel()
    private var state = CompositionState.empty
    private var displayLink: CADisplayLink?
    private let displayTarget = CompositionDisplayTarget()
    private var restoreFocusOnAttachment = false

    init(session: TerminalSession) {
        self.session = session; terminal = session.terminal
        super.init(frame: .zero)
        addSubview(terminal); addSubview(panel)
        accessibilityIdentifier = "terminalContainer"
        displayTarget.owner = self
        panel.chooseCandidate = { [weak session] in session?.keyboard.chooseCandidate($0) }
        panel.chooseSegment = { [weak session] in session?.keyboard.chooseSegment($0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { displayLink?.invalidate() }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { restoreFocusOnAttachment = terminal.superview === self && terminal.isFirstResponder }
        super.willMove(toWindow: newWindow)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            terminal.compositionContainer = self
            session?.keyboard.compositionPresenter = self
            if restoreFocusOnAttachment { restoreFocusOnAttachment = false; _ = terminal.becomeFirstResponder() }
        } else {
            displayLink?.invalidate(); displayLink = nil; panel.isHidden = true
        }
        positionPanel()
    }
    func detach() {
        restoreFocusOnAttachment = false
        displayLink?.invalidate(); displayLink = nil
        panel.isHidden = true
        if session?.keyboard.compositionPresenter === self { session?.keyboard.compositionPresenter = nil }
        if terminal.compositionContainer === self {
            _ = terminal.resignFirstResponder(); terminal.compositionContainer = nil
        }
    }
    func presentComposition(_ state: CompositionState) {
        let starting = self.state.reading.isEmpty && !state.reading.isEmpty
        self.state = state
        panel.setColors(background: terminal.nativeBackgroundColor, foreground: terminal.nativeForegroundColor)
        panel.update(state)
        if starting { terminal.scroll(toPosition: 1) }
        positionPanel()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if terminal.frame != bounds { terminal.frame = bounds }
        positionPanel()
    }
    fileprivate func positionPanel() {
        let active = window != nil && terminal.superview === self && terminal.isFirstResponder && session?.store?.configuration.appearance.customKeyboard == true && !state.reading.isEmpty
        panel.isHidden = !active; panel.accessibilityElementsHidden = !active
        guard active else { displayLink?.invalidate(); displayLink = nil; return }
        let caret = terminal.convert(terminal.caretFrame, to: self)
        let desired = panel.preferredSize(maxWidth: max(0, bounds.width - 12), compact: bounds.height < 110)
        let frame = CompositionLayout.frame(viewport: bounds, caret: caret, desired: desired)
        if panel.frame != frame { panel.frame = frame; panel.setNeedsLayout() }
        bringSubviewToFront(panel)
        if displayLink == nil {
            let link = CADisplayLink(target: displayTarget, selector: #selector(CompositionDisplayTarget.tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 60, preferred: 30)
            link.add(to: .main, forMode: .common); displayLink = link
        }
    }
}

@MainActor
private final class CompositionDisplayTarget: NSObject {
    weak var owner: TerminalContainerView?
    @objc func tick() { owner?.positionPanel() }
}
