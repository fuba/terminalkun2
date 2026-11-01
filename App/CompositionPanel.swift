import UIKit
import TerminalCore

@MainActor
protocol CompositionPresenting: AnyObject {
    func presentComposition(_ state: CompositionState)
}

@MainActor
final class CompositionPanel: UIView {
    let compositionLabel = UILabel()
    private let readingScroll = UIScrollView()
    private let candidates = UIScrollView()
    private let candidateContent = UIView()
    private var buttons: [UIButton] = []
    private var state = CompositionState.empty
    private var segmentFrames: [CGRect] = []
    private var foreground = UIColor.label
    private var surface = UIColor.secondarySystemBackground
    private var compact = false
    var chooseCandidate: ((Int) -> Void)?
    var chooseSegment: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "compositionPanel"
        isHidden = true
        layer.cornerRadius = 8; layer.borderWidth = 0.5
        layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.16
        layer.shadowRadius = 4; layer.shadowOffset = CGSize(width: 0, height: 2)
        backgroundColor = surface
        readingScroll.showsHorizontalScrollIndicator = false
        candidates.showsHorizontalScrollIndicator = false; candidates.delaysContentTouches = false
        compositionLabel.font = .systemFont(ofSize: 16)
        compositionLabel.accessibilityIdentifier = "compositionText"
        compositionLabel.isAccessibilityElement = true
        compositionLabel.isUserInteractionEnabled = true
        compositionLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapSegment(_:))))
        candidates.accessibilityIdentifier = "candidateList"
        addSubview(readingScroll); readingScroll.addSubview(compositionLabel)
        addSubview(candidates); candidates.addSubview(candidateContent)
        accessibilityElements = [readingScroll, candidates]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setColors(background: UIColor, foreground: UIColor) {
        guard !self.foreground.isEqual(foreground) || !surface.isEqual(background) else { return }
        self.foreground = foreground; surface = background; backgroundColor = background
        layer.borderColor = foreground.withAlphaComponent(0.3).cgColor
        update(state)
    }
    func update(_ state: CompositionState) {
        self.state = state
        isHidden = state.reading.isEmpty; accessibilityElementsHidden = isHidden
        let text = NSMutableAttributedString()
        let pieces = state.converting ? state.segments.map(\.text) : [state.reading]
        var x: CGFloat = 0
        segmentFrames = []
        for (index, piece) in pieces.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [.font: compositionLabel.font!, .foregroundColor: foreground, .kern: TerminalTypography.tracking]
            if !state.converting || index == state.selectedSegment {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            let value = NSAttributedString(string: piece, attributes: attributes)
            text.append(value)
            let width = value.size().width
            segmentFrames.append(CGRect(x: x, y: 0, width: width, height: 24)); x += width
        }
        compositionLabel.attributedText = text
        compositionLabel.accessibilityValue = state.converting ? "文節 \(state.selectedSegment + 1)/\(state.segments.count)" : nil
        buttons.forEach { $0.removeFromSuperview() }; buttons = []
        for (index, value) in state.candidates.prefix(20).enumerated() {
            var configuration = UIButton.Configuration.plain()
            configuration.attributedTitle = AttributedString(NSAttributedString(string: value, attributes: [.font: UIFont.systemFont(ofSize: 16), .kern: TerminalTypography.tracking]))
            configuration.baseForegroundColor = foreground
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            configuration.background.cornerRadius = 5
            configuration.background.backgroundColor = state.converting && index == state.selectedCandidate ? foreground.withAlphaComponent(0.16) : .clear
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.chooseCandidate?(index) })
            button.accessibilityIdentifier = "candidate-\(index)"
            if state.converting && index == state.selectedCandidate { button.accessibilityTraits.insert(.selected) }
            candidateContent.addSubview(button); buttons.append(button)
        }
        candidates.accessibilityElements = buttons
        setNeedsLayout(); layoutIfNeeded()
    }
    func preferredSize(maxWidth: CGFloat, compact: Bool = false) -> CGSize {
        if self.compact != compact { self.compact = compact; setNeedsLayout() }
        let width = min(maxWidth, max(compact ? 320 : 200, (compositionLabel.attributedText?.size().width ?? 0) + 20))
        return CGSize(width: max(0, width), height: state.candidates.isEmpty ? 32 : (compact ? 44 : 76))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let inline = compact && !buttons.isEmpty
        let readingWidth = inline ? min(bounds.width * 0.35, max(44, (compositionLabel.attributedText?.size().width ?? 0))) : max(0, bounds.width - 20)
        readingScroll.frame = CGRect(x: 10, y: inline ? max(0, (bounds.height - 24) / 2) : 4, width: readingWidth, height: min(24, max(0, bounds.height - 8)))
        let textWidth = max(readingScroll.bounds.width, compositionLabel.attributedText?.size().width ?? 0)
        compositionLabel.frame = CGRect(x: 0, y: 0, width: textWidth, height: 24)
        readingScroll.contentSize = compositionLabel.bounds.size
        if state.converting, segmentFrames.indices.contains(state.selectedSegment) {
            readingScroll.scrollRectToVisible(segmentFrames[state.selectedSegment], animated: false)
        } else { readingScroll.setContentOffset(CGPoint(x: max(0, textWidth - readingScroll.bounds.width), y: 0), animated: false) }
        let candidateX = inline ? readingScroll.frame.maxX + 10 : 4
        candidates.frame = CGRect(x: candidateX, y: inline ? 0 : 28, width: max(0, bounds.width - candidateX - 4), height: max(0, bounds.height - (inline ? 0 : 32)))
        var x: CGFloat = 0
        for button in buttons {
            let width = max(44, button.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 44)).width)
            button.frame = CGRect(x: x, y: 0, width: width, height: candidates.bounds.height)
            x += width + 2
        }
        candidateContent.frame = CGRect(x: 0, y: 0, width: x, height: candidates.bounds.height)
        candidates.contentSize = candidateContent.bounds.size
        if buttons.indices.contains(state.selectedCandidate) { candidates.scrollRectToVisible(buttons[state.selectedCandidate].frame, animated: false) }
    }
    @objc private func tapSegment(_ gesture: UITapGestureRecognizer) {
        guard state.converting else { return }
        let point = gesture.location(in: compositionLabel)
        if let index = segmentFrames.firstIndex(where: { $0.contains(point) }) { chooseSegment?(index) }
    }
}
