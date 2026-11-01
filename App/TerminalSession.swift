import SwiftUI
import TerminalCore
import TerminalTransport
import TerminalRenderer

@MainActor
final class TerminalSession: NSObject, ObservableObject, Identifiable, TerminalViewDelegate {
    enum State: String { case idle = "未接続", connecting = "接続中", connected = "接続済み", waiting = "再接続待ち", local = "ローカル", closed = "終了" }
    let id: UUID
    let profileID: UUID?
    @Published var title: String
    @Published var state: State
    @Published var directory = ""
    @Published var statusMessage = ""
    @Published var logging = false
    @Published var uploadProgress: Double?
    @Published var recoveredDraft = ""
    @Published var draft = DisconnectedDraft()
    let terminal: SessionTerminalView
    let connection = SSHConnection()
    weak var store: AppStore?
    private var connectionTask: Task<Void, Never>?
    private var localTask: Task<Void, Never>?
    private var local: LocalWorkspace?
    private var localLine = ""
    private var history: [String] = []
    private var historyIndex = 0
    private var credentials: SSHCredentials?
    private var authenticatedProfile: ConnectionProfile?
    private var userClosed = false
    private var reconnectAttempt = 0
    private let log: SessionLog
    private var appearance: Appearance?
    private var prefix: String?
    private var configuringTmux = false
    private var cols = 80, rows = 24
    lazy var keyboard = ProgramKeyboard(session: self)

    init(record: SessionRecord, store: AppStore) {
        id = record.id; profileID = record.profileID; title = record.title
        state = record.profileID == nil ? .local : .idle
        self.store = store
        log = SessionLog(directory: store.logs)
        let options = TerminalOptions(cols: 80, rows: 24, termName: "xterm-256color", cursorStyle: .blinkBlock,
            scrollback: store.configuration.appearance.scrollback)
        terminal = SessionTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 400), font: nil, options: options)
        super.init()
        terminal.session = self
        terminal.terminalDelegate = self
        terminal.accessibilityIdentifier = "terminalSurface"
        terminal.optionAsMetaKey = true
        terminal.returnByteSequence = [13]
        terminal.linkReporting = .implicit
        terminal.inputAccessoryView = TerminalAccessoryBar(session: self)
        applyAppearance(store.configuration.appearance)
        #if DEBUG
        if ProcessInfo.processInfo.environment["TERMINALKUN2_UI_TESTS"] == "1" { terminal.setCursorStyle(.steadyBlock) }
        #endif
        do { try terminal.setUseMetal(true) } catch { store.diagnostic("Metal unavailable; native renderer selected") }
        draft.append(record.draft)
        if profileID == nil { startLocal() }
    }
    func applyAppearance(_ appearance: Appearance) {
        if let store { keyboard.setWords(store.configuration.dictionary) }
        guard self.appearance != appearance else { return }
        let previous = self.appearance; self.appearance = appearance
        let theme = TerminalPalette.named(appearance.theme)
        terminal.nativeBackgroundColor = theme.background
        terminal.nativeForegroundColor = theme.foreground
        terminal.caretColor = theme.foreground
        terminal.backgroundOpacity = CGFloat(max(0.35, min(1, appearance.opacity)))
        if previous?.fontName != appearance.fontName || previous?.fontSize != appearance.fontSize {
            terminal.font = TerminalTypography.font(name: appearance.fontName, size: CGFloat(appearance.fontSize))
        }
        if previous?.scrollback != appearance.scrollback { terminal.changeScrollback(appearance.scrollback) }
        if previous?.customKeyboard != appearance.customKeyboard {
            let focused = terminal.isFirstResponder
            keyboard.resetInput(); terminal.inputView = appearance.customKeyboard ? keyboard : nil; terminal.reloadInputViews()
            if focused { _ = terminal.becomeFirstResponder() }
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["TERMINALKUN2_UI_TESTS"] == "1" { terminal.setCursorStyle(.steadyBlock) }
        #endif
    }
    func startLocal() {
        guard local == nil, let store else { return }
        do {
            let url = store.documents.appendingPathComponent("Workspace")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            local = LocalWorkspace(root: url); state = .local; title = "ローカル"
            output(Data("terminalkun2\r\nアプリの作業フォルダです。help でコマンドを確認できます。\r\n".utf8)); prompt()
        } catch { statusMessage = error.localizedDescription }
    }
    func connect(_ profile: ConnectionProfile) {
        guard state != .connecting, state != .connected else { return }
        userClosed = false; reconnectAttempt = 0
        let previous = connectionTask; previous?.cancel(); state = .connecting
        connectionTask = Task { [weak self] in
            guard let self, let store = self.store else { return }
            await connection.close(); await previous?.value
            guard !Task.isCancelled else { return }
            var wasConnected = false
            do {
                try profile.validate()
                let auth: SSHCredentials
                if authenticatedProfile == profile, let saved = credentials { auth = saved }
                else { auth = try await store.authenticate(profile) }
                credentials = auth; authenticatedProfile = profile
                var jumps: [(ConnectionProfile, SSHCredentials)] = []
                var visited: Set<String> = [profile.name]
                var next = profile.jumpHost
                while let name = next, !name.isEmpty {
                    guard visited.insert(name).inserted, jumps.count < 8,
                          let jump = store.configuration.profiles.first(where: { $0.name == name }) else { throw AppError.message("ProxyJump の接続先が未登録、循環、または 8 段を超えています: \(name)") }
                    jumps.insert((jump, try await store.authenticate(jump)), at: 0); next = jump.jumpHost
                }
                while !Task.isCancelled && !userClosed {
                    state = .connecting; statusMessage = ""
                    do {
                        try await connection.run(profile: profile, credentials: auth, jumps: jumps, cols: cols, rows: rows,
                            verify: { [weak store] profile, key in
                                guard let store else { throw CancellationError() }
                                try await store.verifyHost(profile: profile, key: key)
                            }, onReady: { [weak self] in
                                guard let self else { return }
                                let firstConnection = !wasConnected
                                self.state = .connected; self.reconnectAttempt = 0; wasConnected = true
                                self.prefix = nil
                                self.terminal.feed(text: "\u{1b}[?1049l\u{1b}[!p\u{1b}[?1000l\u{1b}[?1002l\u{1b}[?1003l\u{1b}[?1006l\u{1b}[?2004l\u{1b}[?1l")
                                self.recoveredDraft = self.draft.take(); self.store?.snapshot()
                                Task { await self.configureTmux() }
                                if !profile.startupCommand.isEmpty && firstConnection { self.send(Data((profile.startupCommand + "\r").utf8)) }
                            }, onData: { [weak self] in self?.output($0) })
                        if !Task.isCancelled { state = .idle; statusMessage = "リモートシェルが終了しました。" }
                        break
                    } catch {
                        if Task.isCancelled || userClosed { break }
                        statusMessage = error.localizedDescription
                        if store.hostPrompt?.profile.id == profile.id { store.acceptHost(false) }
                        let trustFailure = (error as? SSHFailure).map { if case .hostKeyRejected = $0 { return true }; return false } ?? statusMessage.contains("ホスト鍵")
                        let authenticationFailure = String(describing: error).lowercased().contains("authentication")
                        if authenticationFailure || !wasConnected { credentials = nil; authenticatedProfile = nil }
                        guard store.configuration.appearance.autoReconnect,
                              !authenticationFailure,
                              ReconnectPolicy.shouldRetry(wasConnected: wasConnected, userClosed: userClosed, trustFailure: trustFailure) else { state = .idle; break }
                        state = .waiting
                        let delay = ReconnectPolicy.delay(attempt: reconnectAttempt); reconnectAttempt += 1
                        statusMessage = "\(Int(delay))秒後に再接続します。"
                        try await Task.sleep(for: .seconds(delay))
                    }
                }
            } catch { if !Task.isCancelled { statusMessage = error.localizedDescription; state = .idle; credentials = nil; authenticatedProfile = nil } }
        }
    }
    func retryNow() {
        guard state == .waiting || state == .idle, let profileID,
              let profile = store?.configuration.profiles.first(where: { $0.id == profileID }) else { return }
        connectionTask?.cancel(); state = .idle; connect(profile)
    }
    func suspendConnection() {
        guard state == .connected else { return }
        connectionTask?.cancel(); state = .waiting
        statusMessage = "アプリに戻ると再接続します。"
        Task { await connection.close() }
    }
    func stop() {
        userClosed = true; connectionTask?.cancel(); localTask?.cancel(); credentials = nil; authenticatedProfile = nil
        resetInput(); log.stop(); logging = false; state = .closed
        Task { await connection.close() }
    }
    func resetInput() { keyboard.resetInput(); terminal.resignFirstResponder() }
    func output(_ data: Data) {
        let start = CFAbsoluteTimeGetCurrent()
        terminal.feed(byteArray: Array(data)[...])
        if logging { do { try log.append(data) } catch { store?.error = error.localizedDescription; logging = false } }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if elapsed > 16 { store?.diagnostic("slow feed \(data.count) bytes \(Int(elapsed))ms") }
    }
    func send(_ data: Data) {
        if state == .local { localInput(data) }
        else if state == .connected { connection.send(data) }
        else { draft.append(String(decoding: data, as: UTF8.self)); store?.snapshot() }
    }
    func paste(_ text: String) { terminal.insertText(text) }
    func pasteClipboard() {
        if let text = UIPasteboard.general.string { terminal.pasteText(text) }
        else if let image = UIPasteboard.general.image, let data = image.pngData(), let store {
            let url = store.support.appendingPathComponent("paste-\(UUID().uuidString).png")
            do { try data.write(to: url, options: [.atomic, .completeFileProtection]); upload([url]) } catch { store.error = error.localizedDescription }
        } else if let urls = UIPasteboard.general.urls { upload(urls) }
    }
    func sendKey(_ key: SpecialKey, modifiers: Modifiers = []) {
        let applicationCursor = terminal.terminalInputStateSnapshot()?.applicationCursor ?? false
        send(Data(KeyEncoder.special(key, modifiers: modifiers, applicationCursor: applicationCursor).utf8))
    }
    func toggleLog() {
        if logging { log.stop(); logging = false }
        else { do { try log.start(); logging = true } catch { store?.error = error.localizedDescription } }
    }
    func shareLog() { if let url = log.url { store?.shareURLs = [url]; store?.showShare = true } }
    func upload(_ urls: [URL]) {
        guard state == .connected else { store?.error = "ファイル送信には SSH 接続が必要です。"; return }
        Task {
            uploadProgress = 0; defer { uploadProgress = nil }
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            do {
                let paths = try await connection.upload(urls) { self.uploadProgress = $0 }
                terminal.pasteText(paths.map(Shell.quote).joined(separator: " ") + " ")
            } catch { store?.error = "ファイル送信に失敗しました。\n" + error.localizedDescription }
        }
    }
    func configureTmux() async {
        guard state == .connected, !configuringTmux else { return }
        configuringTmux = true; defer { configuringTmux = false }
        do {
            if store?.configuration.appearance.tmuxMouse == true { _ = try await connection.execute("tmux set -g mouse on 2>/dev/null || true") }
            let result = try await connection.execute("tmux show-option -gv prefix 2>/dev/null || true").trimmingCharacters(in: .whitespacesAndNewlines)
            prefix = TmuxPrefix.parse(result)
        } catch { store?.diagnostic("tmux setup unavailable") }
    }
    func tmuxWindow(_ next: Bool) {
        guard state == .connected, let prefix, let mode = terminal.terminalInputStateSnapshot()?.mouseMode, mode != .off else { return }
        send(Data((prefix + (next ? "n" : "p")).utf8))
    }
    func action(_ action: String) {
        guard let store else { return }
        switch action {
        case "newTab", "connections": store.sheet = .connections
        case "closeTab": store.close(self)
        case "settings": store.sheet = .settings
        case "nextTab": store.nextTab(1)
        case "previousTab": store.nextTab(-1)
        case "paste": pasteClipboard()
        case "copy": terminal.copy(nil)
        case "search": terminal.onSearch?()
        case "fontLarger": store.configuration.appearance.fontSize = min(32, store.configuration.appearance.fontSize + 1)
        case "fontSmaller": store.configuration.appearance.fontSize = max(10, store.configuration.appearance.fontSize - 1)
        case "fontReset": store.configuration.appearance.fontSize = 14
        case "logging": toggleLog()
        case "upload": terminal.onUpload?()
        case "inputLanguage": keyboard.handle("language")
        case "help": store.sheet = .help
        case "scrollPageUp": terminal.scrollUp(lines: max(1, rows - 1))
        case "scrollPageDown": terminal.scrollDown(lines: max(1, rows - 1))
        case "scrollTop": terminal.scroll(toPosition: 0)
        case "scrollBottom": terminal.scroll(toPosition: 1)
        default: break
        }
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        cols = max(1, newCols); rows = max(1, newRows); connection.resize(cols: cols, rows: rows)
    }
    func setTerminalTitle(source: TerminalView, title: String) { if !title.isEmpty { self.title = String(title.prefix(120)) } }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { self.directory = directory.flatMap { URL(string: $0)?.path } ?? directory ?? "" }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { send(Data(data)) }
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        UIApplication.shared.open(url)
    }
    func clipboardCopy(source: TerminalView, content: Data) {
        guard content.count <= 1024 * 1024, let value = String(data: content, encoding: .utf8), store?.clipboard == nil else { return }
        store?.clipboard = ClipboardPrompt(text: value)
    }
    func clipboardRead(source: TerminalView) -> Data? { nil }
    func bell(source: TerminalView) { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    private func prompt() { output(Data("\r\n$ ".utf8)) }
    private func localInput(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        if text == "\u{1b}[A" || text == "\u{1b}OA" {
            if !history.isEmpty { historyIndex = max(0, historyIndex - 1); localLine = history[historyIndex]; redrawLocalLine() }; return
        }
        if text == "\u{1b}[B" || text == "\u{1b}OB" {
            historyIndex = min(history.count, historyIndex + 1); localLine = historyIndex < history.count ? history[historyIndex] : ""; redrawLocalLine(); return
        }
        if text.hasPrefix("\u{1b}") { return }
        for char in text {
            if char == "\u{3}" { localTask?.cancel(); localTask = nil; localLine = ""; output(Data("^C".utf8)); prompt() }
            else if char == "\r" || char == "\n" {
                guard localTask == nil, let local else { continue }
                let command = localLine; localLine = ""; history.append(command); historyIndex = history.count
                output(Data("\r\n".utf8))
                localTask = Task { [weak self] in
                    guard let self else { return }
                    do { let result = try await local.execute(command); try Task.checkCancellation(); output(Data(result.replacingOccurrences(of: "\n", with: "\r\n").utf8)) }
                    catch { if !Task.isCancelled { output(Data((error.localizedDescription + "\r\n").utf8)) } }
                    if !Task.isCancelled { localTask = nil; directory = local.directory.lastPathComponent; prompt() }
                }
            } else if localTask == nil {
                if char == "\u{7f}" || char == "\u{8}" { if !localLine.isEmpty { localLine.removeLast(); redrawLocalLine() } }
                else if char == "\u{15}" { localLine = ""; redrawLocalLine() }
                else if char == "\u{4}" { if localLine.isEmpty { store?.close(self) } }
                else if !char.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { localLine.append(char); output(Data(String(char).utf8)) }
            }
        }
    }
    private func redrawLocalLine() { output(Data(("\r\u{1b}[2K$ " + localLine).utf8)) }
}

struct TerminalPalette {
    let background: UIColor, foreground: UIColor
    static let names = ["Carbon", "Paper", "Solarized", "Midnight", "Forest"]
    static func named(_ name: String) -> Self {
        switch name {
        case "Paper": return .init(background: UIColor(white: 0.97, alpha: 1), foreground: UIColor(white: 0.12, alpha: 1))
        case "Solarized": return .init(background: UIColor(red: 0, green: 0.17, blue: 0.21, alpha: 1), foreground: UIColor(red: 0.58, green: 0.63, blue: 0.63, alpha: 1))
        case "Midnight": return .init(background: UIColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1), foreground: UIColor(white: 0.9, alpha: 1))
        case "Forest": return .init(background: UIColor(red: 0.04, green: 0.12, blue: 0.09, alpha: 1), foreground: UIColor(red: 0.8, green: 0.9, blue: 0.82, alpha: 1))
        default: return .init(background: UIColor(white: 0.055, alpha: 1), foreground: UIColor(white: 0.9, alpha: 1))
        }
    }
}
