import UIKit
import UniformTypeIdentifiers
import TerminalCore
import TerminalRenderer

@MainActor
final class SessionTerminalView: TerminalView, UIDropInteractionDelegate {
    weak var session: TerminalSession?
    var onSearch: (() -> Void)?
    var onUpload: (() -> Void)?
    override init(frame: CGRect, font: UIFont? = nil, options: TerminalOptions) {
        super.init(frame: frame, font: font, options: options)
        addInteraction(UIDropInteraction(delegate: self))
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let single = UISwipeGestureRecognizer(target: self, action: #selector(oneFingerSwipe(_:)))
            single.direction = direction; single.numberOfTouchesRequired = 1; addGestureRecognizer(single)
            let double = UISwipeGestureRecognizer(target: self, action: #selector(twoFingerSwipe(_:)))
            double.direction = direction; double.numberOfTouchesRequired = 2; addGestureRecognizer(double)
            single.require(toFail: double)
        }
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var keyCommands: [UIKeyCommand]? {
        let commands = session?.store?.configuration.shortcuts.compactMap { binding -> UIKeyCommand? in
            guard !binding.input.isEmpty else { return nil }
            if binding.action == "inputLanguage", session?.store?.configuration.appearance.customKeyboard != true { return nil }
            let command = UIKeyCommand(title: binding.action, action: #selector(shortcut(_:)), input: binding.input, modifierFlags: binding.modifiers.uiFlags, propertyList: binding.action)
            command.wantsPriorityOverSystemBehavior = true; return command
        } ?? []
        return commands + (1...9).map { index in
            let key = UIKeyCommand(title: "タブ \(index)", action: #selector(selectTab(_:)), input: String(index), modifierFlags: .command, propertyList: index)
            key.wantsPriorityOverSystemBehavior = true; return key
        }
    }
    @objc private func shortcut(_ command: UIKeyCommand) {
        guard markedTextRange == nil, let action = command.propertyList as? String else { return }
        session?.action(action)
    }
    @objc private func selectTab(_ command: UIKeyCommand) {
        guard let index = command.propertyList as? Int, let store = session?.store, store.sessions.indices.contains(index - 1) else { return }
        store.select(store.sessions[index - 1].id)
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.charactersIgnoringModifiers.lowercased() == "c" && $0.key?.modifierFlags.contains(.control) == true }), selectionActive {
            copy(nil); return
        }
        super.pressesBegan(presses, with: event)
    }
    @objc private func oneFingerSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard session?.state == .connected else { return }
        session?.tmuxWindow(gesture.direction == .left)
    }
    nonisolated override func mouseModeChanged(source: Terminal) {
        super.mouseModeChanged(source: source)
        Task { @MainActor [weak self] in await self?.session?.configureTmux() }
    }
    @objc private func twoFingerSwipe(_ gesture: UISwipeGestureRecognizer) { session?.store?.nextTab(gesture.direction == .left ? 1 : -1) }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .ended, let store = session?.store {
            store.configuration.appearance.fontSize = max(10, min(32, (store.configuration.appearance.fontSize * gesture.scale).rounded()))
        }
    }
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        self.session?.state == .connected && session.hasItemsConforming(toTypeIdentifiers: [UTType.data.identifier, UTType.fileURL.identifier, UTType.image.identifier])
    }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal { UIDropProposal(operation: .copy) }
    func dropInteraction(_ interaction: UIDropInteraction, performDrop drop: UIDropSession) {
        guard let session, let store = session.store else { return }
        for item in drop.items {
            let provider = item.itemProvider
            let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true }) ?? UTType.data.identifier
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else { Task { @MainActor in store.error = error?.localizedDescription }; return }
                do {
                    let folder = store.support.appendingPathComponent("Drop-" + UUID().uuidString)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let copy = folder.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: copy)
                    Task { @MainActor in session.upload([copy]) }
                } catch { Task { @MainActor in store.error = error.localizedDescription } }
            }
        }
    }
}

extension Modifiers {
    var uiFlags: UIKeyModifierFlags {
        var flags: UIKeyModifierFlags = []
        if contains(.command) { flags.insert(.command) }; if contains(.control) { flags.insert(.control) }
        if contains(.alt) { flags.insert(.alternate) }; if contains(.shift) { flags.insert(.shift) }; return flags
    }
    init(_ flags: UIKeyModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }; if flags.contains(.control) { insert(.control) }
        if flags.contains(.alternate) { insert(.alt) }; if flags.contains(.shift) { insert(.shift) }
    }
}
