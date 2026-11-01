import UIKit
import TerminalCore
import TerminalIME

@MainActor
final class ProgramKeyboard: UIInputView {
    struct Key { let label: String; let value: String; let units: CGFloat; init(_ label: String, _ value: String? = nil, _ units: CGFloat = 1) { self.label = label; self.value = value ?? label; self.units = units } }
    private struct Hit { let key: Key; let frame: CGRect }
    private weak var session: TerminalSession?
    private let engine: JapaneseInput
    private var hits: [Hit] = []
    private var touches: [ObjectIdentifier: Int] = [:]
    private var timers: [ObjectIdentifier: Timer] = [:]
    private var modifiers = ModifierState()
    private var japanese = false
    private var function = false
    private var symbols = false
    private var selectedCandidate = 0
    private var geometrySize = CGSize.zero
    private var geometryFunction = false
    private var geometrySymbols = false
    private var epoch = 0
    private let composition = UILabel()
    private let candidates = UIScrollView()
    private let candidateStack = UIView()
    private var candidateButtons: [UIButton] = []
    var onModifiersChanged: ((Modifiers, Modifiers) -> Void)?
    init(session: TerminalSession) {
        self.session = session
        self.engine = JapaneseInput(memory: session.store!.support.appendingPathComponent("JapaneseLearning"))
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 300), inputViewStyle: .keyboard)
        allowsSelfSizing = true; isMultipleTouchEnabled = true; backgroundColor = .secondarySystemBackground
        composition.font = .systemFont(ofSize: 16); composition.textColor = .label; composition.accessibilityIdentifier = "compositionText"
        composition.isAccessibilityElement = true; candidates.accessibilityIdentifier = "candidateList"
        addSubview(composition); addSubview(candidates)
        composition.isUserInteractionEnabled = true
        composition.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectComposition(_:))))
        candidates.addSubview(candidateStack)
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.willResignActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: traitCollection.verticalSizeClass == .compact ? 210 : 300) }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass { invalidateIntrinsicContentSize() }
    }
    func setWords(_ words: [UserWord]) { engine.words = words }
    @objc private func background() { resetInput() }
    func resetInput() {
        epoch += 1
        timers.values.forEach { $0.invalidate() }; timers = [:]; touches = [:]
        modifiers.reset(); engine.cancel(); selectedCandidate = 0; refreshComposition(); refreshModifiers()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if geometrySize != bounds.size || geometryFunction != function || geometrySymbols != symbols {
            epoch += 1; timers.values.forEach { $0.invalidate() }; timers = [:]; touches = [:]
            geometrySize = bounds.size; geometryFunction = function; geometrySymbols = symbols
        }
        composition.frame = CGRect(x: 10, y: 1, width: bounds.width - 20, height: 22)
        candidates.frame = CGRect(x: 5, y: 23, width: bounds.width - 10, height: 36)
        var candidateX: CGFloat = 0
        for button in candidateButtons {
            let size = button.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 36))
            let width = max(44, size.width)
            button.frame = CGRect(x: candidateX, y: 0, width: width, height: 36)
            candidateX += width + 8
        }
        candidateStack.frame = CGRect(x: 0, y: 0, width: candidateX, height: 36)
        candidates.contentSize = CGSize(width: candidateX, height: 36)
        candidates.accessibilityElements = candidateButtons
        hits = []
        let rows = keyRows(), top: CGFloat = 62, rowHeight = (bounds.height - top - 4) / CGFloat(rows.count)
        for (rowIndex, row) in rows.enumerated() {
            let width = (bounds.width - 6) / row.reduce(CGFloat(0)) { $0 + $1.units }
            var x: CGFloat = 3
            for key in row {
                hits.append(Hit(key: key, frame: CGRect(x: x + 2, y: top + CGFloat(rowIndex) * rowHeight + 2, width: width * key.units - 4, height: rowHeight - 4)))
                x += width * key.units
            }
        }
        let keys = hits.map { hit in
            let element = KeyboardAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = display(hit.key); element.accessibilityTraits = .keyboardKey
            element.accessibilityIdentifier = "program-key-" + hit.key.value
            element.accessibilityFrameInContainerSpace = hit.frame
            element.activate = { [weak self] in self?.handle(hit.key.value) }; return element
        }
        accessibilityElements = [composition, candidates] + keys
        setNeedsDisplay()
    }
    private func keyRows() -> [[Key]] {
        if symbols {
            return [
                Array("`[]{}<>|\\").map { Key(String($0)) },
                Array("~!@#$%^&*").map { Key(String($0)) },
                Array("()-_=+;:'\"").map { Key(String($0)) },
                [Key(","), Key("."), Key("/"), Key("?"), Key("←", "left"), Key("→", "right"), Key("⌫", "backspace", 2)],
                [Key("ABC", "symbols", 1.5), Key("Tab", "tab"), Key("space", "space", 4), Key("↵", "enter", 2)]
            ]
        }
        if function {
            return [
                (1...6).map { Key("F\($0)", "f\($0)") },
                (7...12).map { Key("F\($0)", "f\($0)") },
                [Key("Home", "home"), Key("↑", "up"), Key("End", "end"), Key("PgUp", "pageUp"), Key("Del", "delete")],
                [Key("←", "left"), Key("↓", "down"), Key("→", "right"), Key("PgDn", "pageDown"), Key("コピー", "copy")],
                [Key("ABC", "fn"), Key("^[", "escape"), Key("screen", "screen"), Key("貼付", "paste"), Key("↵", "enter")]
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
        if key.value == "language" { return japanese ? "あ" : "A" }
        if key.value == "space" { return japanese ? "変換" : "space" }
        if key.value.count == 1 { return KeyEncoder.text(key.label, modifiers: modifiers.active.intersection(.shift)) }
        return key.label
    }
    override func draw(_ rect: CGRect) {
        for (index, hit) in hits.enumerated() {
            let pressed = touches.values.contains(index)
            let active = hit.key.value == "shift" && modifiers.active.contains(.shift)
            (pressed ? UIColor.systemGray3 : (active ? UIColor.systemGray2 : UIColor.tertiarySystemBackground)).setFill()
            UIBezierPath(roundedRect: hit.frame, cornerRadius: 5).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: hit.key.value.count == 1 ? 21 : 15, weight: .regular), .foregroundColor: UIColor.label]
            let text = display(hit.key) as NSString, size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: hit.frame.midX - size.width / 2, y: hit.frame.midY - size.height / 2), withAttributes: attrs)
        }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let index = hits.firstIndex(where: { $0.frame.contains(point) }) else { continue }
            let id = ObjectIdentifier(touch); self.touches[id] = index
            let value = hits[index].key.value; handle(value)
            let inputEpoch = epoch
            if value.count == 1 || ["backspace", "left", "right", "up", "down", "delete"].contains(value) {
                timers[id] = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.touches[id] != nil, self.epoch == inputEpoch else { return }
                        self.handle(value)
                        self.timers[id] = Timer.scheduledTimer(withTimeInterval: 0.065, repeats: true) { [weak self] _ in Task { @MainActor in
                            guard let self, self.epoch == inputEpoch, self.touches[id] != nil else { return }; self.handle(value)
                        } }
                    }
                }
            }
        }
        setNeedsDisplay()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if let index = self.touches[id], !hits[index].frame.contains(touch.location(in: self)) { finish(touch) }
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touches.forEach(finish) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touches.forEach(finish) }
    private func finish(_ touch: UITouch) { let id = ObjectIdentifier(touch); timers.removeValue(forKey: id)?.invalidate(); touches.removeValue(forKey: id); setNeedsDisplay() }
    @objc private func selectComposition(_ gesture: UITapGestureRecognizer) {
        guard engine.converting else { return }
        let x = gesture.location(in: composition).x
        var edge: CGFloat = 0
        for (index, segment) in engine.segments.enumerated() {
            edge += ((segment.text + " ") as NSString).size(withAttributes: [.font: composition.font!]).width
            if x <= edge { engine.selectCandidate(selectedCandidate); engine.selectSegment(index); selectedCandidate = 0; refreshComposition(); return }
        }
    }
    func handle(_ value: String) {
        guard let session else { return }
        if ["control", "alt", "shift"].contains(value) {
            modifiers.tap(value == "control" ? .control : value == "alt" ? .alt : .shift); refreshModifiers(); return
        }
        if value == "language" {
            epoch += 1
            if !engine.reading.isEmpty { session.send(Data(engine.commit().utf8)) }
            timers.values.forEach { $0.invalidate() }; timers = [:]
            japanese.toggle(); modifiers.reset(); refreshModifiers(); refreshComposition(); return
        }
        if value == "fn" { function.toggle(); setNeedsLayout(); return }
        if value == "symbols" { symbols.toggle(); function = false; setNeedsLayout(); return }
        if value == "system" {
            if !engine.reading.isEmpty { session.send(Data(engine.commit().utf8)) }
            session.store?.configuration.appearance.customKeyboard.toggle(); return
        }
        if value == "paste" { session.pasteClipboard(); return }
        if value == "copy" { session.terminal.copy(nil); return }
        if value == "screen" { session.send(Data("\u{1}ESC".replacingOccurrences(of: "ESC", with: "[").utf8)); return }
        if value == "hide" { session.terminal.resignFirstResponder(); return }
        if japanese && !engine.reading.isEmpty && !modifiers.active.contains(.control) && !modifiers.active.contains(.alt) {
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
            if japanese && !modifiers.active.contains(.control) && !modifiers.active.contains(.alt) && text.range(of: "^[a-zA-Z'-]+$", options: .regularExpression) != nil {
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
    private func refreshModifiers() { onModifiersChanged?(modifiers.active, modifiers.locked); setNeedsDisplay() }
    private func refreshComposition() {
        if engine.converting {
            let value = NSMutableAttributedString()
            for (index, segment) in engine.segments.enumerated() {
                let attrs: [NSAttributedString.Key: Any] = index == engine.selectedSegment ? [.underlineStyle: NSUnderlineStyle.single.rawValue, .backgroundColor: UIColor.systemGray4] : [:]
                value.append(NSAttributedString(string: segment.text + " ", attributes: attrs))
            }
            composition.attributedText = value
        } else { composition.attributedText = nil; composition.text = engine.reading }
        candidateButtons.forEach { $0.removeFromSuperview() }; candidateButtons = []
        for (index, text) in engine.candidates.prefix(20).enumerated() {
            var configuration = UIButton.Configuration.plain(); configuration.title = text
            configuration.baseForegroundColor = .label
            configuration.background.backgroundColor = engine.converting && index == selectedCandidate ? .systemGray4 : .clear
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                if self.engine.converting { self.engine.selectCandidate(index); self.selectedCandidate = index }
                else { self.session?.send(Data(self.engine.commit(index: index).utf8)) }
                self.refreshComposition()
            })
            button.accessibilityIdentifier = "candidate-\(index)"; candidateStack.addSubview(button); candidateButtons.append(button)
        }
        setNeedsLayout(); layoutIfNeeded()
        if candidateButtons.indices.contains(selectedCandidate) { candidates.scrollRectToVisible(candidateButtons[selectedCandidate].frame, animated: false) }
    }
}

private final class KeyboardAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Void)?
    override func accessibilityActivate() -> Bool { activate?(); return true }
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
        for (label, value) in [("Esc", "escape"), ("Tab", "tab"), ("Ctrl", "control"), ("Alt", "alt"), ("←", "left"), ("↓", "down"), ("↑", "up"), ("→", "right"), ("{", "{"), ("}", "}"), ("⌨", "system"), ("⌄", "hide")] {
            var config = UIButton.Configuration.plain(); config.title = label; config.baseForegroundColor = .label
            let button = UIButton(configuration: config, primaryAction: UIAction { [weak session] _ in session?.keyboard.handle(value) })
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
            button.accessibilityLabel = value; button.accessibilityIdentifier = "accessory-\(value)"
            stack.addArrangedSubview(button); modifierButtons[value] = button
        }
        session.keyboard.onModifiersChanged = { active, locked in
            for (name, flag) in [("control", Modifiers.control), ("alt", Modifiers.alt)] {
                modifierButtons[name]?.configuration?.background.backgroundColor = active.contains(flag) ? .systemGray3 : .clear
                modifierButtons[name]?.configuration?.title = name == "control" ? (locked.contains(flag) ? "Ctrl●" : "Ctrl") : (locked.contains(flag) ? "Alt●" : "Alt")
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44) }
}
