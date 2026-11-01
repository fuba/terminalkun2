import SwiftUI
import UniformTypeIdentifiers
import TerminalCore
import TerminalTransport
import TerminalRenderer

struct WorkspaceView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !store.sessions.isEmpty { tabs }
                if let session = store.selected { SessionPane(session: session).id(session.id) }
                else { empty }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("terminalkun2")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(verticalSizeClass == .compact && store.selected != nil ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { store.sheet = .connections } label: { Image(systemName: "server.rack") }.accessibilityLabel("接続先") }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { store.sheet = .connections } label: { Image(systemName: "plus") }.accessibilityLabel("新しいタブ")
                    Button { store.sheet = .settings } label: { Image(systemName: "gearshape") }.accessibilityLabel("設定")
                }
            }
        }
        .sheet(item: $store.sheet, onDismiss: { store.didDismissSheet() }) { route in
            switch route {
            case .connections: ConnectionsView()
            case .settings: SettingsView()
            case .edit(let profile): ProfileEditor(profile: profile)
            case .keys: KeyListView()
            case .dictionary: DictionaryView()
            case .voice: VoiceView()
            case .help: HelpView()
            }
        }
        .sheet(item: $store.authentication, onDismiss: { if store.authentication != nil { store.finishAuthentication(password: nil) } }) { AuthenticationView(prompt: $0) }
        .sheet(item: $store.hostPrompt, onDismiss: { if store.hostPrompt != nil { store.acceptHost(false) } }) { HostVerificationView(prompt: $0) }
        .sheet(item: $store.clipboard) { prompt in ClipboardView(prompt: prompt) }
        .sheet(isPresented: $store.showShare) { ShareView(items: store.shareURLs) }
        .alert("お知らせ", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("閉じる") { store.error = nil } } message: { Text(store.error ?? "") }
        .confirmationDialog("受け取ったファイルを SSH 接続先へ送信", isPresented: Binding(get: { !store.pendingFiles.isEmpty }, set: { if !$0 { store.pendingFiles = [] } })) {
            Button("送信") { store.selected?.upload(store.pendingFiles); store.pendingFiles = [] }
            Button("キャンセル", role: .cancel) { store.pendingFiles = [] }
        }
    }
    private var empty: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "terminal").font(.system(size: 58, weight: .light)).foregroundStyle(.secondary)
            Text("接続先を選ぶ").font(.title2)
            Button("SSH 接続") { store.sheet = .connections }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("端末内の作業フォルダを開く") { store.newLocal() }.accessibilityIdentifier("openLocal")
            Spacer()
        }.frame(maxWidth: .infinity)
    }
    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(store.sessions) { session in TabButton(session: session) }
            }.padding(.horizontal, 8).padding(.vertical, 5)
        }
        .scrollIndicators(.hidden).background(.bar)
    }
}

struct TabButton: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: TerminalSession
    var body: some View {
        Button {
            store.select(session.id)
            if session.state == .idle { session.retryNow() }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(session.state == .connected || session.state == .local ? Color.green : Color.secondary).frame(width: 6, height: 6)
                Text(session.title).font(.subheadline).lineLimit(2).frame(maxWidth: 180)
                if session.logging { Image(systemName: "record.circle").foregroundStyle(.red) }
            }.padding(.horizontal, 12).padding(.vertical, 9)
                .background(store.selectedID == session.id ? Color(uiColor: .tertiarySystemFill) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("tab-\(session.id)")
            .contextMenu {
                Button("再接続", systemImage: "arrow.clockwise") { session.retryNow() }.disabled(session.state == .connected)
                Button("閉じる", systemImage: "xmark", role: .destructive) { store.close(session) }
            }
    }
}

struct SessionPane: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject var session: TerminalSession
    @State private var showSearch = false
    @State private var query = ""
    @State private var caseSensitive = false
    @State private var regex = false
    @State private var importing = false
    @State private var showClose = false
    @State private var matchCount = "0/0"
    var body: some View {
        VStack(spacing: 0) {
            if verticalSizeClass != .compact { metadata }
            if showSearch {
                HStack {
                    TextField("端末内を検索", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().onSubmit { search(false) }.accessibilityIdentifier("terminalSearch")
                    Text(matchCount).monospacedDigit().foregroundStyle(.secondary).accessibilityIdentifier("searchMatchCount")
                    Button { search(true) } label: { Image(systemName: "chevron.up") }.accessibilityLabel("前の一致")
                    Button { search(false) } label: { Image(systemName: "chevron.down") }.accessibilityLabel("次の一致")
                    Menu { Toggle("大文字と小文字を区別", isOn: $caseSensitive); Toggle("正規表現", isOn: $regex) } label: { Image(systemName: "line.3.horizontal.decrease") }
                    Button { showSearch = false; session.terminal.clearSearch() } label: { Image(systemName: "xmark") }.accessibilityLabel("検索を閉じる")
                }.padding(10).background(.bar)
            }
            if !session.statusMessage.isEmpty && session.state != .connected {
                HStack {
                    Text(session.statusMessage).font(.callout).textSelection(.enabled)
                    Spacer(minLength: 4)
                    if session.state == .waiting || session.state == .idle { Button("再接続") { session.retryNow() } }
                }.padding(10).background(Color(uiColor: .secondarySystemBackground))
            }
            if !session.recoveredDraft.isEmpty {
                HStack {
                    Text("下書き: " + session.recoveredDraft).font(.callout).lineLimit(3)
                    Button("入力に戻す") { session.terminal.pasteText(session.recoveredDraft); session.recoveredDraft = "" }
                    Button { session.recoveredDraft = "" } label: { Image(systemName: "xmark") }.accessibilityLabel("下書きを破棄")
                }.padding(8).background(.bar)
            }
            TerminalSurface(session: session, onSearch: { showSearch.toggle() }, onUpload: { importing = true })
                .accessibilityElement(children: .contain).accessibilityIdentifier("terminalSurface")
            if let progress = session.uploadProgress { ProgressView(value: progress).padding(.horizontal) }
            HStack {
                Button { session.terminal.isFirstResponder ? session.terminal.resignFirstResponder() : session.terminal.becomeFirstResponder() } label: { Image(systemName: "keyboard") }.accessibilityLabel("キーボード")
                Spacer()
                Button { session.pasteClipboard() } label: { Image(systemName: "document.on.clipboard") }.accessibilityLabel("貼り付け")
                Spacer()
                Button { showSearch.toggle() } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("端末内を検索")
                Spacer()
                Menu {
                    if verticalSizeClass == .compact {
                        Button("接続先", systemImage: "server.rack") { store.sheet = .connections }
                        Button("設定", systemImage: "gearshape") { store.sheet = .settings }
                    }
                    Button("ファイルを送信", systemImage: "square.and.arrow.up") { importing = true }.disabled(session.state != .connected)
                    Button("音声・コマンド作成", systemImage: "mic") { store.sheet = .voice }
                    Button(session.logging ? "ログを停止" : "ログを開始", systemImage: "record.circle") { session.toggleLog() }
                    Button("ログを共有", systemImage: "square.and.arrow.up") { session.shareLog() }
                    Button("履歴の先頭", systemImage: "arrow.up.to.line") { session.terminal.scroll(toPosition: 0) }
                    Button("履歴の末尾", systemImage: "arrow.down.to.line") { session.terminal.scroll(toPosition: 1) }
                    Button("タブを閉じる", systemImage: "xmark", role: .destructive) { showClose = true }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("端末操作")
            }.font(.title3).padding(.horizontal, 22).frame(height: 44).background(.bar)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .folder], allowsMultipleSelection: true) { result in
            do { session.upload(try result.get()) } catch { store.error = error.localizedDescription }
        }
        .confirmationDialog("このタブを閉じますか？", isPresented: $showClose) { Button("閉じる", role: .destructive) { store.close(session) } }
    }
    private var metadata: some View {
        HStack(spacing: 8) {
            if session.state == .connecting { ProgressView().controlSize(.small) }
            Text(session.state.rawValue).foregroundStyle(.secondary)
            if let profile = store.configuration.profiles.first(where: { $0.id == session.profileID }) { Text(profile.address) }
            if !session.directory.isEmpty { Text(session.directory).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 60)) { context in Text(context.date, style: .time).monospacedDigit().foregroundStyle(.secondary) }
        }.font(.footnote).textSelection(.enabled).padding(.horizontal, 10).padding(.vertical, 5).background(Color(uiColor: .secondarySystemBackground))
    }
    private func search(_ backwards: Bool) {
        let options = SearchOptions(caseSensitive: caseSensitive, regex: regex)
        if backwards { session.terminal.findPrevious(query, options: options) } else { session.terminal.findNext(query, options: options) }
        let summary = session.terminal.searchMatchSummary(query, options: options)
        matchCount = "\(summary.index)/\(summary.total)"
    }
}

struct TerminalSurface: UIViewRepresentable {
    let session: TerminalSession
    let onSearch: () -> Void
    let onUpload: () -> Void
    func makeUIView(context: Context) -> TerminalContainerView { session.terminal.onSearch = onSearch; session.terminal.onUpload = onUpload; return TerminalContainerView(session: session) }
    func updateUIView(_ view: TerminalContainerView, context: Context) {}
    static func dismantleUIView(_ view: TerminalContainerView, coordinator: ()) { view.detach() }
}

struct ShareView: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
