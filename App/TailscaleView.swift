// MIT License
import SwiftUI
import TerminalCore

@MainActor
final class TailnetBrowser: ObservableObject {
    struct Credentials: Codable {
        var tailnet: String
        var token: String
        var clientID: String? = nil
        var secret: String? = nil
    }
    private static let account = "tailscale.devices-read.v1"
    @Published var peers: [TailscalePeer] = []
    @Published var loading = false
    @Published var error: String?
    @Published var updated: Date?
    @Published var configured = false
    private var credentials: Credentials?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    init() {
        do {
            if let data = try SecureStore.get(Self.account) {
                credentials = try JSONDecoder().decode(Credentials.self, from: data); configured = true
            }
        } catch { self.error = "Tailscale 設定を読み込めませんでした。" }
    }
    func refresh(replacement: Credentials? = nil) {
        guard let value = replacement ?? credentials else { return }
        cancel(); loading = true; error = nil
        let token = generation
        task = Task { @MainActor in
            do {
                let access: String
                if let id = value.clientID, let secret = value.secret { access = try await TailscaleClient.accessToken(clientID: id, secret: secret) }
                else { access = value.token }
                let peers = try await TailscaleClient.devices(tailnet: value.tailnet, token: access)
                guard !Task.isCancelled, token == generation else { return }
                if replacement != nil {
                    try SecureStore.set(JSONEncoder().encode(value), account: Self.account)
                    credentials = value; configured = true
                }
                self.peers = peers; updated = Date(); loading = false
            } catch {
                guard !Task.isCancelled, token == generation else { return }
                self.error = error.localizedDescription; loading = false
            }
        }
    }
    func forget() {
        cancel()
        do {
            try SecureStore.remove(Self.account); credentials = nil; configured = false; peers = []; updated = nil; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; loading = false }
}

struct TailscaleView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    @StateObject private var browser = TailnetBrowser()
    @State private var tailnet = "-"
    @State private var accessToken = ""
    @State private var useOAuth = true
    @State private var clientID = ""
    @State private var query = ""
    @State private var changeCredentials = false
    @State private var editing: ConnectionProfile?
    @State private var pendingConnection: ConnectionProfile?
    @State private var forget = false

    var body: some View {
        List {
            Section {
                NavigationLink("Tailscale の接続手順") { TailscaleHelpView() }
            }
            if !browser.configured || changeCredentials {
                Section("Tailscale API") {
                    Picker("認証", selection: $useOAuth) { Text("OAuth（継続利用）").tag(true); Text("アクセストークン").tag(false) }
                    TextField("Tailnet 名（既定は -）", text: $tailnet).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("tailnetName")
                    if useOAuth { TextField("OAuth クライアント ID", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("tailnetClientID") }
                    SecureField(useOAuth ? "OAuth シークレット" : "API アクセストークン", text: $accessToken).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("tailnetToken")
                    Button("接続して保存") {
                        browser.refresh(replacement: .init(tailnet: tailnet, token: useOAuth ? "" : accessToken, clientID: useOAuth ? clientID : nil, secret: useOAuth ? accessToken : nil))
                        accessToken = ""
                    }.disabled(browser.loading || accessToken.isEmpty || (useOAuth && clientID.isEmpty)).accessibilityIdentifier("tailnetSave")
                    Text("devices:core:read 権限のアクセストークンを使用します。資格情報はこの端末だけの Keychain に保存します。SSH 通信には、iPhone の公式 Tailscale アプリで同じ Tailnet に接続してください。")
                        .foregroundStyle(.secondary)
                }
            }
            if let error = browser.error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
            if browser.configured {
                Section {
                    ForEach(browser.peers.filter { query.isEmpty || ($0.displayName + " " + $0.name + " " + $0.addresses.joined(separator: " ")).localizedCaseInsensitiveContains(query) }) { peer in
                        Button { select(peer) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "circle.fill").font(.caption2).foregroundStyle(peer.online == true ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(peer.displayName).foregroundStyle(.primary)
                                    Text(peer.sshHost).font(.callout).foregroundStyle(.secondary)
                                    Text(peer.authorized == false ? "承認待ち" : peer.online == true ? "オンライン" : peer.online == false ? "オフライン" : "状態不明")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }.padding(.vertical, 4)
                        }.disabled(peer.authorized == false || browser.loading)
                    }
                    if browser.peers.isEmpty && !browser.loading { Text("この Tailnet に端末がありません。").foregroundStyle(.secondary) }
                }
                Section {
                    if let date = browser.updated { Text("更新: \(date.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary) }
                    Button("API 資格情報を変更") { changeCredentials.toggle() }
                    Button("連携を解除", role: .destructive) { forget = true }
                }
            }
            if browser.loading { ProgressView("端末一覧を取得中") }
        }
        .navigationTitle("Tailscale").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "端末名・IP")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { browser.refresh() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("端末一覧を再読み込み").disabled(browser.loading || !browser.configured) } }
        .refreshable { browser.refresh() }
        .task { browser.refresh() }
        .onDisappear { browser.cancel(); accessToken = "" }
        .onChange(of: browser.configured) { _, value in if value { changeCredentials = false } }
        .onChange(of: phase) { _, value in
            if value != .active { browser.cancel(); accessToken = "" }
            else { browser.refresh() }
        }
        .sheet(item: $editing, onDismiss: {
            if let profile = pendingConnection { pendingConnection = nil; store.connect(profile) }
        }) { profile in
            ProfileEditor(profile: profile, connectAfterSave: { pendingConnection = $0 })
        }
        .confirmationDialog("Tailscale の資格情報をこの端末から削除しますか？", isPresented: $forget) { Button("連携を解除", role: .destructive) { browser.forget(); changeCredentials = false } }
    }
    private func select(_ peer: TailscalePeer) {
        if let existing = store.sortedProfiles.first(where: { profile in
            peer.addresses.contains(profile.host) || profile.host.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == peer.name.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }) { store.connect(existing) }
        else { editing = ConnectionProfile(name: peer.displayName, host: peer.sshHost) }
    }
}
