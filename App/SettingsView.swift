import SwiftUI
import UniformTypeIdentifiers
import CoreText
import TerminalCore
import TerminalTransport

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var importFont = false
    var body: some View {
        NavigationStack {
            Form {
                Section("表示") {
                    Picker("配色", selection: $store.configuration.appearance.theme) { ForEach(TerminalPalette.names, id: \.self) { Text($0) } }
                    HStack { Text("文字サイズ"); Slider(value: $store.configuration.appearance.fontSize, in: 10...32, step: 1); Text(Int(store.configuration.appearance.fontSize).description).monospacedDigit().frame(width: 26) }
                    HStack { Text("背景の不透明度"); Slider(value: $store.configuration.appearance.opacity, in: 0.35...1); Text("\(Int(store.configuration.appearance.opacity * 100))%").monospacedDigit() }
                    Stepper("スクロール履歴 \(store.configuration.appearance.scrollback) 行", value: $store.configuration.appearance.scrollback, in: 1000...50000, step: 1000)
                    Button(store.configuration.appearance.fontName.isEmpty ? "フォントを取り込む" : "フォント: " + store.configuration.appearance.fontName) { importFont = true }
                    if !store.configuration.appearance.fontName.isEmpty { Button("標準の等幅フォントに戻す") { store.configuration.appearance.fontName = "" } }
                    Toggle("画面を自動ロックしない", isOn: $store.configuration.appearance.keepScreenAwake)
                }
                Section("入力") {
                    Toggle("プログラミング用キーボード", isOn: $store.configuration.appearance.customKeyboard)
                        .accessibilityIdentifier("customKeyboardMode")
                        .accessibilityValue(store.configuration.appearance.customKeyboard ? "オン" : "オフ")
                    NavigationLink("ユーザー辞書") { DictionaryView(embedded: true) }
                    NavigationLink("キー割り当て") { ShortcutSettingsView() }
                }
                Section("SSH") {
                    Toggle("通信断から自動再接続", isOn: $store.configuration.appearance.autoReconnect)
                    Toggle("tmux のマウス操作を有効にする", isOn: $store.configuration.appearance.tmuxMouse)
                    NavigationLink("秘密鍵・公開鍵") { KeyListView(embedded: true) }
                    NavigationLink("信頼したホスト鍵") { KnownHostsView() }
                }
                Section("コマンド生成") {
                    TextField("API URL（Ollama / OpenAI 互換）", text: $store.configuration.aiEndpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("モデル名", text: $store.configuration.aiModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("入力した依頼だけを指定サーバーに送信します。生成結果は確認後に入力欄へ挿入し、改行は送信しません。").font(.callout).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("使い方") { HelpView(embedded: true) }
                    Button("設定 JSON を共有") { store.share([store.configURL]) }
                    Button("診断ログを共有") {
                        store.share((try? FileManager.default.contentsOfDirectory(at: store.logs, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix("session-") }) ?? [])
                    }
                    Text("terminalkun2 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · MIT").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
            .fileImporter(isPresented: $importFont, allowedContentTypes: [.font, .data]) { result in
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count < 32 * 1024 * 1024, let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider), let name = font.postScriptName else { throw AppError.message("有効な TTF / OTF フォントを選択してください。") }
                    var error: Unmanaged<CFError>?
                    let registered = CTFontManagerRegisterGraphicsFont(font, &error)
                    let registrationError = error?.takeRetainedValue()
                    guard registered || UIFont(name: name as String, size: 14) != nil else {
                        throw registrationError.map { $0 as Error } ?? AppError.message("フォントを登録できませんでした。")
                    }
                    try data.write(to: store.support.appendingPathComponent("terminal-font"), options: [.atomic, .completeFileProtection])
                    store.configuration.appearance.fontName = name as String
                } catch { store.error = error.localizedDescription }
            }
        }
    }
}

struct ShortcutSettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var recording: String?
    var body: some View {
        List {
            ForEach(store.configuration.shortcuts) { binding in
                HStack {
                    Text(Self.label(binding.action)); Spacer()
                    Button(recording == binding.action ? "キーを押してください" : Self.chord(binding)) { recording = binding.action }
                    Button { assign(binding.action, input: "", modifiers: []) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).accessibilityLabel("割り当て解除")
                }.padding(.vertical, 4)
            }
            Button("初期値に戻す") { store.configuration.shortcuts = ShortcutBinding.defaults }
        }.navigationTitle("キー割り当て")
            .overlay {
                if let recording {
                    VStack(spacing: 18) {
                        Text(Self.label(recording)).font(.title3)
                        KeyRecorder { input, modifiers in assign(recording, input: input, modifiers: modifiers); self.recording = nil }.frame(width: 1, height: 1)
                        Text("物理キーボードで押すか、文字と修飾キーを指定してください。")
                        ChordEditor { input, modifiers in assign(recording, input: input, modifiers: modifiers); self.recording = nil }
                        Button("キャンセル") { self.recording = nil }
                    }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding()
                }
            }
    }
    private func assign(_ action: String, input: String, modifiers: Modifiers) {
        for i in store.configuration.shortcuts.indices where store.configuration.shortcuts[i].input == input && store.configuration.shortcuts[i].modifiers == modifiers { store.configuration.shortcuts[i].input = "" }
        if let index = store.configuration.shortcuts.firstIndex(where: { $0.action == action }) { store.configuration.shortcuts[index].input = input; store.configuration.shortcuts[index].modifiers = modifiers }
    }
    static func chord(_ b: ShortcutBinding) -> String { b.input.isEmpty ? "未割り当て" : (b.modifiers.contains(.control) ? "⌃" : "") + (b.modifiers.contains(.alt) ? "⌥" : "") + (b.modifiers.contains(.shift) ? "⇧" : "") + (b.modifiers.contains(.command) ? "⌘" : "") + b.input.uppercased() }
    static func label(_ action: String) -> String { ["newTab": "新しいタブ", "closeTab": "タブを閉じる", "connections": "接続先", "settings": "設定", "search": "検索", "nextTab": "次のタブ", "previousTab": "前のタブ", "paste": "貼り付け", "copy": "コピー", "fontLarger": "文字を拡大", "fontSmaller": "文字を縮小", "fontReset": "文字サイズを戻す", "logging": "ログの開始・停止", "upload": "ファイル送信", "inputLanguage": "英数・日本語", "help": "使い方", "scrollPageUp": "前のページ", "scrollPageDown": "次のページ", "scrollTop": "履歴の先頭", "scrollBottom": "履歴の末尾"][action] ?? action }
}

struct ChordEditor: View {
    let save: (String, Modifiers) -> Void
    @State private var text = ""
    @State private var command = true
    @State private var control = false
    @State private var alt = false
    @State private var shift = false
    var body: some View {
        VStack {
            TextField("キー", text: $text).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
            HStack { Toggle("⌘", isOn: $command); Toggle("⌃", isOn: $control); Toggle("⌥", isOn: $alt); Toggle("⇧", isOn: $shift) }.toggleStyle(.button)
            Button("割り当てる") { var mods: Modifiers = []; if command { mods.insert(.command) }; if control { mods.insert(.control) }; if alt { mods.insert(.alt) }; if shift { mods.insert(.shift) }; save(String(text.prefix(1)), mods) }.disabled(text.isEmpty)
        }
    }
}

struct KeyRecorder: UIViewRepresentable {
    let record: (String, Modifiers) -> Void
    func makeUIView(context: Context) -> CaptureView { let view = CaptureView(); view.record = record; DispatchQueue.main.async { view.becomeFirstResponder() }; return view }
    func updateUIView(_ view: CaptureView, context: Context) {}
    final class CaptureView: UIView {
        var record: ((String, Modifiers) -> Void)?
        override var canBecomeFirstResponder: Bool { true }
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if let key = presses.first?.key, !key.charactersIgnoringModifiers.isEmpty { record?(key.charactersIgnoringModifiers, Modifiers(key.modifierFlags)) }
        }
    }
}

struct KnownHostsView: View {
    @EnvironmentObject var store: AppStore
    @State private var removing: ConnectionProfile?
    var body: some View {
        List(store.configuration.profiles) { profile in
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.address).textSelection(.enabled)
                if let data = try? SecureStore.get("host:\(profile.host.lowercased()):\(profile.port)"), let key = String(data: data, encoding: .utf8) {
                    Text(TerminalTransport.HostTrust.fingerprint(key)).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Button("この鍵を削除", role: .destructive) { removing = profile }
                } else { Text("未登録").foregroundStyle(.secondary) }
            }.padding(.vertical, 6)
        }.navigationTitle("ホスト鍵")
            .confirmationDialog("ホスト鍵を削除しますか？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("削除", role: .destructive) { if let p = removing { do { try SecureStore.remove("host:\(p.host.lowercased()):\(p.port)") } catch { store.error = error.localizedDescription } }; removing = nil }
            }
    }
}
