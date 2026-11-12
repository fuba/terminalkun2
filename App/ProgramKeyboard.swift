import UIKit
import TerminalCore
import TerminalIME

@MainActor
final class ProgramKeyboard: UIInputView {
    struct Key {
        let label: String; let value: String; let units: CGFloat; let rows: CGFloat; let flick: FlickKey?
        init(_ label: String, _ value: String? = nil, _ units: CGFloat = 1, rows: CGFloat = 1) { self.label = label; self.value = value ?? label; self.units = units; self.rows = rows; flick = nil }
        init(_ flick: FlickKey) { self.label = flick.text(.center) ?? ""; value = flick.id; units = 1; rows = 1; self.flick = flick }
    }
    private struct Hit { let key: Key; let frame: CGRect }
    private struct Press { let index: Int; let sequence: Int; var gesture: FlickGesture?; let label: String }
    private weak var session: TerminalSession?
    private let engine: JapaneseInput
    private var hits: [Hit] = []
    private var presses: [ObjectIdentifier: Press] = [:]
    private var sequence = 0
    private var timers: [ObjectIdentifier: Timer] = [:]
    private var modifiers = ModifierState()
    private var japanese = false
    private var function = false
    private var symbols = false
    private var numbers = false
    private var selectedCandidate = 0
    private(set) var showingSequences = false
    private var geometrySequences: [KeySequence]?
    private var geometrySize = CGSize.zero
    private var geometryFunction = false
    private var geometrySymbols = false
    private var geometryCompact = false
    private var geometryJapanese = false
    private var geometryNumbers = false
    private var epoch = 0
    private let preview = FlickPreview()
    private let keyPop = UILabel()
    private let feedback = UISelectionFeedbackGenerator()
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 248)
    weak var compositionPresenter: CompositionPresenting? { didSet { refreshComposition() } }
    var onModifiersChanged: ((Modifiers, Modifiers) -> Void)?
    init(session: TerminalSession) {
        self.session = session
        self.engine = JapaneseInput(memory: session.store!.support.appendingPathComponent("JapaneseLearning"))
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 248), inputViewStyle: .keyboard)
        allowsSelfSizing = true; isMultipleTouchEnabled = true; backgroundColor = .secondarySystemBackground
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint.isActive = true
        preview.isHidden = true; preview.isUserInteractionEnabled = false; preview.isAccessibilityElement = false
        addSubview(preview)
        keyPop.isHidden = true; keyPop.isUserInteractionEnabled = false
        keyPop.accessibilityIdentifier = "program-key-preview"
        keyPop.isAccessibilityElement = false
        keyPop.backgroundColor = .systemBackground
        keyPop.textColor = .label
        keyPop.textAlignment = .center
        keyPop.adjustsFontSizeToFitWidth = true
        keyPop.minimumScaleFactor = 0.65
        keyPop.layer.cornerRadius = 8
        keyPop.clipsToBounds = true
        addSubview(keyPop)
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.willResignActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var compactHeight: Bool {
        // Input windows can retain portrait coordinates; use the input view's actual width.
        if let size = session?.terminal.window?.bounds.size ?? window?.bounds.size {
            return bounds.width > min(size.width, size.height) + 1
        }
        return session?.terminal.traitCollection.verticalSizeClass == .compact
    }
    private var isFlickLayout: Bool { japanese && !symbols && !function && !showingSequences }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: (compactHeight ? (isFlickLayout ? 184 : 148) : 238) + max(10, safeAreaInsets.bottom)) }
    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        CGSize(width: targetSize.width, height: intrinsicContentSize.height)
    }
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize {
        systemLayoutSizeFitting(targetSize)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow(); if window == nil { cancelPresses() }; invalidateIntrinsicContentSize()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass { invalidateIntrinsicContentSize() }
    }
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange(); heightConstraint.constant = intrinsicContentSize.height; invalidateIntrinsicContentSize(); setNeedsLayout()
    }
    func setWords(_ words: [UserWord]) { engine.words = words }
    @objc private func background() { resetInput() }
    func resetInput() {
        cancelPresses()
        if showingSequences { setSequenceMode(false) }
        modifiers.reset(); engine.cancel(); selectedCandidate = 0; refreshComposition(); refreshModifiers()
    }
    private func cancelPresses() {
        epoch += 1; timers.values.forEach { $0.invalidate() }; timers = [:]; presses = [:]; preview.isHidden = true; keyPop.isHidden = true; setNeedsDisplay()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if heightConstraint.constant != intrinsicContentSize.height { heightConstraint.constant = intrinsicContentSize.height }
        if geometryCompact != compactHeight { geometryCompact = compactHeight; invalidateIntrinsicContentSize() }
        let sequences = showingSequences ? session?.store?.configuration.effectiveKeySequences : nil
        if geometrySize != bounds.size || geometrySequences != sequences || geometryFunction != function || geometrySymbols != symbols || geometryJapanese != japanese || geometryNumbers != numbers {
            cancelPresses()
            geometrySize = bounds.size; geometryFunction = function; geometrySymbols = symbols
            geometryJapanese = japanese; geometryNumbers = numbers; geometrySequences = sequences
        }
        hits = []
        let rows = keyRows()
        let top: CGFloat = isFlickLayout ? 4 : (compactHeight ? 15 : 23)
        let rowHeight = max(1, (bounds.height - top - max(10, safeAreaInsets.bottom) - 4) / CGFloat(rows.count))
        for (rowIndex, row) in rows.enumerated() {
            let width = (bounds.width - 6) / (isFlickLayout ? 5 : row.reduce(CGFloat(0)) { $0 + $1.units })
            var x: CGFloat = 3
            for key in row {
                hits.append(Hit(key: key, frame: CGRect(x: x + 2, y: top + CGFloat(rowIndex) * rowHeight + 2, width: width * key.units - 4, height: rowHeight * key.rows - 4)))
                x += width * key.units
            }
        }
        let keys = hits.map { hit in
            let element = KeyboardAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = display(hit.key); element.accessibilityTraits = .keyboardKey
            element.accessibilityIdentifier = "program-key-" + hit.key.value
            element.accessibilityFrameInContainerSpace = hit.frame.insetBy(dx: -2, dy: -2)
            element.activate = { [weak self] in self?.activate(hit.key, direction: .center) }
            if let flick = hit.key.flick {
                element.accessibilityHint = "上下左右へフリックして入力"
                element.accessibilityCustomActions = FlickDirection.allCases.filter { $0 != .center }.compactMap { direction in
                    guard let text = flick.text(direction) else { return nil }
                    return UIAccessibilityCustomAction(name: text) { [weak self] _ in self?.activate(hit.key, direction: direction); return true }
                }
            }
            return element
        }
        accessibilityElements = keys
        setNeedsDisplay()
    }
    private func keyRows() -> [[Key]] {
        if showingSequences {
            let keys = (session?.store?.configuration.effectiveKeySequences ?? []).map { Key($0.name, "sequence-" + $0.id.uuidString) }
            let rows = stride(from: 0, to: keys.count, by: 3).map { start in
                Array(keys[start..<min(start + 3, keys.count)])
            }
            return rows + [[Key("戻る", "sequences"), Key("Esc", "escape"),
                            Key("←", "left"), Key("↑", "up"), Key("↓", "down"), Key("→", "right")]]
        }
        if symbols {
            return [
                Array("`[]{}<>|\\").map { Key(String($0)) },
                Array("~!@#$%^&*").map { Key(String($0)) },
                Array("()-_=+;:'\"").map { Key(String($0)) },
                [Key(","), Key("."), Key("/"), Key("?"), Key("←", "left"), Key("→", "right"), Key("⌫", "backspace", 2)],
                [Key(japanese ? (numbers ? "123" : "かな") : "ABC", "symbols", 1.5), Key("Tab", "tab"), Key("space", "space", 4), Key("↵", "enter", 2)]
            ]
        }
        if function {
            return [
                (1...6).map { Key("F\($0)", "f\($0)") },
                (7...12).map { Key("F\($0)", "f\($0)") },
                [Key("Home", "home"), Key("↑", "up"), Key("End", "end"), Key("PgUp", "pageUp"), Key("Del", "delete")],
                [Key("←", "left"), Key("↓", "down"), Key("→", "right"), Key("PgDn", "pageDown"), Key("コピー", "copy")],
                [Key(japanese ? (numbers ? "123" : "かな") : "ABC", "fn"), Key("^[", "escape"), Key("screen", "screen"), Key("貼付", "paste"), Key("↵", "enter")]
            ]
        }
        if japanese {
            let keys = numbers ? JapaneseFlickLayout.numbers : JapaneseFlickLayout.kana
            let bottomLeft = numbers ? FlickKey("number-sign", ["-","+","=","*","/"]) : FlickKey("kana-modifier", ["小゛゜","゛","小","゜","大"])
            return [
                [Key("ABC", "language"), Key(keys[0]), Key(keys[1]), Key(keys[2]), Key("⌫", "backspace")],
                [Key(numbers ? "かな" : "123", "numbers"), Key(keys[3]), Key(keys[4]), Key(keys[5]), Key("変換", "space")],
                [Key("#+=", "symbols"), Key(keys[6]), Key(keys[7]), Key(keys[8]), Key("↵", "enter", rows: 2)],
                [Key("Fn", "fn"), Key(bottomLeft), Key(keys[9]), Key(keys[10])]
            ]
        }
        return [
            Array("1234567890").map { Key(String($0)) },
            Array("qwertyuiop").map { Key(String($0)) },
            Array("asdfghjkl;").map { Key(String($0)) },
            [Key("⇧", "shift", 1.3)] + Array("zxcvbnm").map { Key(String($0)) } + [Key("⌫", "backspace", 1.7)],
            [Key(japanese ? "あ" : "A", "language", 1.2), Key("Fn", "fn"), Key("#+=", "symbols"), Key("/"), Key(japanese ? "変換" : "space", "space", 3), Key("."), Key("↵", "enter", 1.8)]
        ]
    }
    private func display(_ key: Key) -> String {
        if key.value == "shift" { return modifiers.locked.contains(.shift) ? "⇪" : "⇧" }
        if key.value == "language" { return japanese ? "ABC" : "あいう" }
        if key.value == "space" { return japanese ? (engine.reading.isEmpty ? "空白" : "変換") : "space" }
        if key.value == "enter", japanese && !showingSequences { return engine.reading.isEmpty ? "改行" : "確定" }
        if key.value.count == 1 { return KeyEncoder.text(key.label, modifiers: modifiers.active.intersection(.shift)) }
        return key.label
    }
    override func draw(_ rect: CGRect) {
        for (index, hit) in hits.enumerated() {
            let pressed = presses.values.contains { $0.index == index && $0.gesture?.cancelled != true }
            let active = hit.key.value == "shift" && modifiers.active.contains(.shift)
            (pressed ? UIColor.systemGray3 : (active ? UIColor.systemGray2 : UIColor.tertiarySystemBackground)).setFill()
            UIBezierPath(roundedRect: hit.frame, cornerRadius: 5).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: hit.key.flick != nil && hit.key.label.count == 1 ? min(25, max(20, hit.frame.height - 27)) : hit.key.value.count == 1 ? 21 : 15, weight: .regular), .foregroundColor: UIColor.label, .kern: TerminalTypography.tracking]
            let text = display(hit.key) as NSString, size = text.size(withAttributes: attrs)
            if hit.key.value.hasPrefix("sequence-"), size.width > hit.frame.width - 8 {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byCharWrapping
                var wrapped = attrs
                wrapped[.font] = UIFont.systemFont(ofSize: 12)
                wrapped[.paragraphStyle] = paragraph
                let area = hit.frame.insetBy(dx: 4, dy: 2)
                let height = text.boundingRect(with: area.size, options: [.usesLineFragmentOrigin], attributes: wrapped, context: nil).height
                text.draw(with: CGRect(x: area.minX, y: area.midY - height / 2, width: area.width, height: height),
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: wrapped, context: nil)
                continue
            }
            let hint = hit.key.flick?.choices.dropFirst().joined() ?? ""
            text.draw(at: CGPoint(x: hit.frame.midX - size.width / 2, y: hint.isEmpty ? hit.frame.midY - size.height / 2 : hit.frame.minY + max(0, (hit.frame.height - 16 - size.height) / 2)), withAttributes: attrs)
            if !hint.isEmpty {
                let hintAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.secondaryLabel]
                let label = hint as NSString, hintSize = label.size(withAttributes: hintAttrs)
                label.draw(at: CGPoint(x: hit.frame.midX - hintSize.width / 2, y: hit.frame.maxY - hintSize.height - 2), withAttributes: hintAttrs)
            }
        }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) { beginPress(ObjectIdentifier(touch), at: touch.location(in: self)) }
        setNeedsDisplay()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { movePress(ObjectIdentifier(touch), to: touch.location(in: self)) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { (presses[ObjectIdentifier($0)]?.sequence ?? 0) < (presses[ObjectIdentifier($1)]?.sequence ?? 0) }) {
            let id = ObjectIdentifier(touch); movePress(id, to: touch.location(in: self)); endPress(id, cancelled: false)
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { for touch in touches { endPress(ObjectIdentifier(touch), cancelled: true) } }
    func beginPress(_ id: ObjectIdentifier, at point: CGPoint) {
        guard let index = hits.firstIndex(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(point) }) else { return }
        let key = hits[index].key; sequence += 1
        let pressSequence = sequence
        presses[id] = Press(index: index, sequence: pressSequence, gesture: key.flick == nil ? nil : FlickGesture(start: point), label: display(key))
        if key.flick != nil { feedback.prepare(); updatePreview(); return }
        handle(key.value)
        updatePreview(); setNeedsDisplay()
        let inputEpoch = epoch
        guard presses[id]?.sequence == pressSequence else { return }
        if key.value.count == 1 || ["backspace", "left", "right", "up", "down", "delete"].contains(key.value) {
            timers[id] = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self] _ in Task { @MainActor in
                guard let self, self.presses[id]?.sequence == pressSequence, self.epoch == inputEpoch else { return }
                self.handle(key.value)
                guard self.presses[id]?.sequence == pressSequence, self.epoch == inputEpoch else { return }
                self.timers[id] = Timer.scheduledTimer(withTimeInterval: 0.065, repeats: true) { [weak self] _ in Task { @MainActor in
                    guard let self, self.epoch == inputEpoch, self.presses[id]?.sequence == pressSequence else { return }; self.handle(key.value)
                } }
            } }
        }
    }
    func movePress(_ id: ObjectIdentifier, to point: CGPoint) {
        guard var press = presses[id], hits.indices.contains(press.index) else { return }
        if var gesture = press.gesture {
            let previous = gesture.direction; gesture.move(to: point); press.gesture = gesture; presses[id] = press
            if !gesture.cancelled && previous != gesture.direction { feedback.selectionChanged() }
            updatePreview()
        } else if !hits[press.index].frame.insetBy(dx: -2, dy: -2).contains(point) { endPress(id, cancelled: true) }
        setNeedsDisplay()
    }
    func endPress(_ id: ObjectIdentifier, cancelled: Bool) {
        timers.removeValue(forKey: id)?.invalidate()
        if let press = presses.removeValue(forKey: id), !cancelled, let gesture = press.gesture, !gesture.cancelled, hits.indices.contains(press.index) {
            activate(hits[press.index].key, direction: gesture.direction)
        }
        updatePreview(); setNeedsDisplay()
    }
    private func updatePreview() {
        let press = presses.values.filter {
            $0.gesture?.cancelled != true && (!isFlickLayout || $0.gesture != nil)
        }.max { $0.sequence < $1.sequence }
        preview.isHidden = true; keyPop.isHidden = true
        guard let press, hits.indices.contains(press.index) else { return }
        let hit = hits[press.index]
        guard let flick = hit.key.flick, let direction = press.gesture?.direction else {
            guard !isFlickLayout, bounds.width >= 48 else { return }
            let height: CGFloat = compactHeight ? 30 : 38
            let width = min(bounds.width - 8, max(40, hit.frame.width + 8))
            keyPop.font = .systemFont(ofSize: press.label.count == 1 ? 25 : 17)
            keyPop.text = press.label
            keyPop.frame = CGRect(x: min(max(4, hit.frame.midX - width / 2), bounds.width - width - 4),
                                  y: max(0, hit.frame.minY - height + 2), width: width, height: height)
            keyPop.isHidden = false
            bringSubviewToFront(keyPop)
            return
        }
        let frame = hits[press.index].frame, size: CGFloat = 138
        preview.frame = CGRect(x: min(max(4, frame.midX - size / 2), bounds.width - size - 4), y: min(max(4, frame.midY - size + 10), bounds.height - size - 4), width: size, height: size)
        preview.flick = flick; preview.direction = direction; preview.isHidden = false; preview.setNeedsDisplay()
        bringSubviewToFront(preview)
    }
    private func activate(_ key: Key, direction: FlickDirection) {
        guard let flick = key.flick else { handle(key.value); return }
        if key.value == "kana-modifier" {
            let variant: KanaVariant
            switch direction { case .center: variant = .cycle; case .left: variant = .voiced; case .up: variant = .small; case .right: variant = .semiVoiced; case .down: variant = .large }
            engine.modifyPreviousKana(variant); selectedCandidate = 0; refreshComposition(); return
        }
        guard let text = flick.text(direction) else { return }
        if modifiers.active.contains(.control) || modifiers.active.contains(.alt) { handle(text); return }
        if engine.converting { session?.send(Data(engine.commit(index: selectedCandidate).utf8)) }
        engine.insertDirect(text); selectedCandidate = 0; modifiers.consume(); refreshModifiers(); refreshComposition()
    }
    func chooseSegment(_ index: Int) {
        guard engine.converting else { return }
        engine.selectCandidate(selectedCandidate); engine.selectSegment(index)
        selectedCandidate = 0; refreshComposition()
    }
    func chooseCandidate(_ index: Int) {
        if engine.converting { engine.selectCandidate(index); selectedCandidate = index }
        else { session?.send(Data(engine.commit(index: index).utf8)) }
        refreshComposition()
    }
    private func setSequenceMode(_ enabled: Bool) {
        guard let session, showingSequences != enabled else { return }
        cancelPresses()
        showingSequences = enabled
        if session.store?.configuration.appearance.customKeyboard != true {
            session.terminal.inputView = enabled ? self : nil
            session.terminal.reloadInputViews()
        }
        modifiers.reset()
        invalidateIntrinsicContentSize(); refreshModifiers(); refreshComposition()
    }
    func handle(_ value: String) {
        guard let session else { return }
        if value == "sequences" { setSequenceMode(!showingSequences); return }
        if value.hasPrefix("sequence-") {
            guard let sequence = session.store?.configuration.effectiveKeySequences.first(where: { "sequence-" + $0.id.uuidString == value }) else { return }
            session.sendKeySequence(sequence.keys)
            return
        }
        if ["control", "alt", "shift"].contains(value) {
            modifiers.tap(value == "control" ? .control : value == "alt" ? .alt : .shift); refreshModifiers(); return
        }
        if value == "language" {
            if !engine.reading.isEmpty { session.send(Data(engine.commit().utf8)) }
            cancelPresses(); japanese.toggle(); numbers = false; function = false; symbols = false
            modifiers.reset(); invalidateIntrinsicContentSize(); refreshModifiers(); refreshComposition(); return
        }
        if value == "numbers" { cancelPresses(); numbers.toggle(); setNeedsLayout(); return }
        if value == "fn" { cancelPresses(); function.toggle(); symbols = false; invalidateIntrinsicContentSize(); setNeedsLayout(); return }
        if value == "symbols" { cancelPresses(); symbols.toggle(); function = false; invalidateIntrinsicContentSize(); setNeedsLayout(); return }
        if value == "system" {
            setSequenceMode(false)
            if !engine.reading.isEmpty { session.send(Data(engine.commit().utf8)) }
            session.store?.configuration.appearance.customKeyboard.toggle(); return
        }
        if value == "paste" { session.pasteClipboard(); return }
        if value == "copy" { session.terminal.copy(nil); return }
        if value == "screen" { session.sendKeySequence("^A ^["); return }
        if value == "hide" { setSequenceMode(false); session.terminal.resignFirstResponder(); return }
        if japanese && !showingSequences && !engine.reading.isEmpty && !modifiers.active.contains(.control) && !modifiers.active.contains(.alt) {
            switch value {
            case "space", "tab", "down":
                if engine.converting { selectedCandidate = (selectedCandidate + 1) % max(1, engine.candidates.count) }
                else { engine.convert(); selectedCandidate = 0 }; engine.selectCandidate(selectedCandidate); refreshComposition(); return
            case "up": selectedCandidate = max(0, selectedCandidate - 1); engine.selectCandidate(selectedCandidate); refreshComposition(); return
            case "enter": session.send(Data(engine.commit(index: engine.converting ? selectedCandidate : nil).utf8)); refreshComposition(); return
            case "escape": engine.cancel(); refreshComposition(); return
            case "backspace": engine.deleteBackward(); selectedCandidate = 0; refreshComposition(); return
            case "left", "right":
                let offset = value == "left" ? -1 : 1
                if engine.converting {
                    if modifiers.active.contains(.shift) { engine.adjustBoundary(offset) }
                    else { engine.selectCandidate(selectedCandidate); engine.moveSegment(offset) }
                } else { engine.moveCursor(offset) }
                selectedCandidate = 0; modifiers.consume(); refreshModifiers(); refreshComposition(); return
            default: break
            }
        }
        if let key = SpecialKey(rawValue: value) { session.sendKey(key, modifiers: modifiers.active) }
        else {
            let text = value == "space" ? " " : value
            if japanese && !showingSequences && !modifiers.active.contains(.control) && !modifiers.active.contains(.alt) && text.range(of: "^[a-zA-Z'-]+$", options: .regularExpression) != nil {
                engine.insert(text.lowercased()); selectedCandidate = 0; refreshComposition()
            } else {
                if !engine.reading.isEmpty { session.send(Data(engine.commit().utf8)); refreshComposition() }
                if let binding = session.store?.configuration.shortcuts.first(where: { $0.input.lowercased() == text.lowercased() && $0.modifiers == modifiers.active }) { session.action(binding.action) }
                else if modifiers.active.contains(.control), text.lowercased() == "c", session.terminal.selectionActive { session.terminal.copy(nil) }
                else { session.send(Data(KeyEncoder.text(text, modifiers: modifiers.active).utf8)) }
            }
        }
        modifiers.consume(); refreshModifiers()
    }
    private func refreshModifiers() { onModifiersChanged?(modifiers.active, modifiers.locked); setNeedsLayout(); setNeedsDisplay() }
    private func refreshComposition() {
        let state = showingSequences ? CompositionState.empty : CompositionState(reading: engine.reading,
            segments: engine.segments.map { .init($0.text) }, selectedSegment: engine.selectedSegment,
            candidates: engine.candidates, selectedCandidate: selectedCandidate, converting: engine.converting)
        compositionPresenter?.presentComposition(state)
        setNeedsLayout()
    }

}

private final class KeyboardAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Void)?
    override func accessibilityActivate() -> Bool { activate?(); return true }
}

private final class FlickPreview: UIView {
    var flick: FlickKey?
    var direction: FlickDirection = .center
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; backgroundColor = .clear }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let flick else { return }
        let positions: [FlickDirection: CGPoint] = [.center: CGPoint(x: 1, y: 1), .left: CGPoint(x: 0, y: 1), .up: CGPoint(x: 1, y: 0), .right: CGPoint(x: 2, y: 1), .down: CGPoint(x: 1, y: 2)]
        let tile = bounds.width / 3
        for choice in FlickDirection.allCases {
            guard let text = flick.text(choice), let position = positions[choice] else { continue }
            let frame = CGRect(x: position.x * tile, y: position.y * tile, width: tile, height: tile).insetBy(dx: 1, dy: 1)
            (choice == direction ? UIColor.label : UIColor.systemGray5).setFill()
            UIBezierPath(roundedRect: frame, cornerRadius: 8).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: text.count > 1 ? 14 : 26), .foregroundColor: choice == direction ? UIColor.systemBackground : UIColor.label]
            let label = text as NSString, size = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2), withAttributes: attrs)
        }
    }
}

@MainActor
final class TerminalAccessoryBar: UIInputView {
    init(session: TerminalSession) {
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 44), inputViewStyle: .keyboard)
        let scroll = UIScrollView(); scroll.showsHorizontalScrollIndicator = false
        let stack = UIStackView(); stack.axis = .horizontal; stack.spacing = 2
        addSubview(scroll); scroll.addSubview(stack)
        scroll.translatesAutoresizingMaskIntoConstraints = false; stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor), stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 4), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -4), stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)])
        var modifierButtons: [String: UIButton] = [:]
        for (label, value) in [("Esc", "escape"), ("Tab", "tab"), ("Ctrl", "control"), ("Alt", "alt"), ("キー", "sequences"), ("⇧", "shift"), ("←", "left"), ("↓", "down"), ("↑", "up"), ("→", "right"), ("{", "{"), ("}", "}"), ("⌨", "system"), ("⌄", "hide")] {
            var config = UIButton.Configuration.plain(); config.title = label; config.baseForegroundColor = .label
            let button = UIButton(configuration: config, primaryAction: UIAction { [weak session] _ in session?.keyboard.handle(value) })
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
            button.accessibilityLabel = value == "sequences" ? "キー列" : value; button.accessibilityIdentifier = "accessory-\(value)"
            stack.addArrangedSubview(button); modifierButtons[value] = button
        }
        session.keyboard.onModifiersChanged = { active, locked in
            for (name, flag) in [("control", Modifiers.control), ("alt", Modifiers.alt), ("shift", Modifiers.shift)] {
                modifierButtons[name]?.configuration?.background.backgroundColor = active.contains(flag) ? .systemGray3 : .clear
                modifierButtons[name]?.configuration?.title = name == "control" ? (locked.contains(flag) ? "Ctrl●" : "Ctrl") : name == "alt" ? (locked.contains(flag) ? "Alt●" : "Alt") : (locked.contains(flag) ? "⇪" : "⇧")
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44) }
}
