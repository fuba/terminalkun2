import SwiftUI
import UniformTypeIdentifiers
import TerminalCore

struct ConnectionsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var importer = false
    @State private var editing: ConnectionProfile?
    var body: some View {
        NavigationStack {
            List {
                Section { Button("端末内の作業フォルダ", systemImage: "folder") { store.newLocal() }.accessibilityIdentifier("openLocalFromConnections") }
                Section {
                    ForEach(store.sortedProfiles.filter { query.isEmpty || ($0.name + " " + $0.address).localizedCaseInsensitiveContains(query) }) { profile in
                        Button { store.connect(profile) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: profile.favorite ? "star.fill" : "server.rack").foregroundStyle(profile.favorite ? .yellow : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.name).font(.body).foregroundStyle(.primary)
                                    Text(profile.address).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Spacer()
                                if store.sessions.contains(where: { $0.profileID == profile.id && $0.state == .connected }) { Image(systemName: "circle.fill").font(.caption2).foregroundStyle(.green) }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 4)
                        }.contextMenu {
                            Button(profile.favorite ? "お気に入りを解除" : "お気に入り", systemImage: "star") { if let i = store.configuration.profiles.firstIndex(where: { $0.id == profile.id }) { store.configuration.profiles[i].favorite.toggle() } }
                            Button("編集", systemImage: "pencil") { editing = profile }
                            Button("削除", systemImage: "trash", role: .destructive) { store.removeProfile(profile.id) }
                        }.swipeActions {
                            Button("削除", role: .destructive) { store.removeProfile(profile.id) }
                            Button("編集") { editing = profile }.tint(.gray)
                        }
                    }
                    if store.configuration.profiles.isEmpty { ContentUnavailableView("接続先がありません", systemImage: "server.rack", description: Text("＋から追加するか SSH config を取り込めます。")) }
                }
                Section {
                    Button("接続先を追加", systemImage: "plus") { editing = ConnectionProfile(name: "", host: "") }
                    Button("SSH config を取り込む", systemImage: "square.and.arrow.down") { importer = true }
                    if store.configuration.sshConfigBookmark != nil { Button("SSH config を再同期", systemImage: "arrow.clockwise") { store.syncSSHConfig() } }
                }
            }
            .searchable(text: $query, prompt: "名前・ホスト・ユーザー")
            .navigationTitle("接続先").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { editing = ConnectionProfile(name: "", host: "") } label: { Image(systemName: "plus") }.accessibilityLabel("接続先を追加") }
            }
            .sheet(item: $editing) { ProfileEditor(profile: $0) }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.data, .plainText]) { result in
                do { try store.importSSHConfig(result.get()) } catch { store.error = error.localizedDescription }
            }
        }
    }
}

struct ProfileEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var profile: ConnectionProfile
    @State private var showKeys = false
    @State private var validation: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名前", text: $profile.name).accessibilityIdentifier("profileName")
                    TextField("ホスト名・IP", text: $profile.host).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("profileHost")
                    TextField("ユーザー名", text: $profile.user).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("profileUser")
                    HStack { Text("ポート"); Spacer(); TextField("22", value: $profile.port, format: .number.grouping(.never)).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90).accessibilityIdentifier("profilePort") }
                    Toggle("お気に入り", isOn: $profile.favorite)
                }
                Section("認証") {
                    Picker("秘密鍵", selection: $profile.keyID) {
                        Text("パスワード").tag(UUID?.none)
                        ForEach(store.configuration.keys) { key in Text(key.name).tag(Optional(key.id)) }
                    }
                    Button("鍵を管理", systemImage: "key") { showKeys = true }
                    Toggle("SSH agent を転送", isOn: Binding(get: { profile.agentForwarding == true }, set: { profile.agentForwarding = $0 })).disabled(profile.keyID == nil)
                    if profile.agentForwarding == true { Text("この接続先は、選択した鍵で別の SSH 接続を認証できます。秘密鍵は転送せず、アプリが前面にある間だけ署名します。").font(.callout).foregroundStyle(.secondary) }
                }
                Section("踏み台") {
                    Picker("ProxyJump", selection: Binding(get: { profile.jumpHost ?? "" }, set: { profile.jumpHost = $0.isEmpty ? nil : $0 })) {
                        Text("なし").tag("")
                        ForEach(store.configuration.profiles.filter { $0.id != profile.id }) { Text($0.name).tag($0.name) }
                    }
                }
                if !profile.unsupportedOptions.isEmpty { Section { Text("自動実行できない設定: " + profile.unsupportedOptions.joined(separator: ", ")).foregroundStyle(.orange); Button("この設定を外す") { profile.unsupportedOptions = [] } } }
                if let validation { Text(validation).foregroundStyle(.red) }
            }
            .navigationTitle("接続先").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.bold().accessibilityIdentifier("saveProfile") }
            }
            .sheet(isPresented: $showKeys) { KeyListView() }
        }
    }
    private func save() {
        do {
            profile.host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines); profile.user = profile.user.trimmingCharacters(in: .whitespacesAndNewlines)
            if profile.name.isEmpty { profile.name = profile.host }
            try profile.validate()
            if let index = store.configuration.profiles.firstIndex(where: { $0.id == profile.id }) { store.configuration.profiles[index] = profile }
            else { store.configuration.profiles.append(profile) }
            dismiss()
        } catch { validation = error.localizedDescription }
    }
}
