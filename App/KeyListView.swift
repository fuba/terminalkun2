import SwiftUI
import UniformTypeIdentifiers
import TerminalCore
import TerminalTransport

struct KeyListView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    var embedded = false
    @State private var name = "iPhone"
    @State private var generating = false
    @State private var importer = false
    @State private var importedPEM = ""
    @State private var passphrase = ""
    @State private var showImport = false
    @State private var scanQR = false
    @State private var selected: SavedKey?
    @State private var removing: SavedKey?
    @State private var renamed: SavedKey?
    @State private var rename = ""
    var body: some View {
        if embedded { content }
        else { NavigationStack { content.toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } } } }
    }
    private var content: some View {
        List {
            ForEach(store.configuration.keys) { key in
                Button { selected = key } label: {
                    HStack {
                        Image(systemName: "key").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key.name).foregroundStyle(.primary)
                            Text(HostTrust.fingerprint(key.publicKey)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }.contextMenu {
                    Button("名前を変更", systemImage: "pencil") { renamed = key; rename = key.name }
                    Button("公開鍵をコピー", systemImage: "doc.on.doc") { UIPasteboard.general.string = key.publicKey }
                    Button("削除", systemImage: "trash", role: .destructive) { removing = key }
                }.swipeActions { Button("削除", role: .destructive) { removing = key } }
            }
            Section {
                TextField("鍵の名前", text: $name)
                Button("Ed25519 鍵を生成", systemImage: "plus") { generate() }.disabled(generating || name.isEmpty).accessibilityIdentifier("generateKey")
                if KeyMaterial.hardwareAvailable { Button("Secure Enclave 鍵を生成", systemImage: "lock.shield") { generateHardware() }.disabled(name.isEmpty) }
            }
            Section("取り込み") {
                Button("QR をカメラで読み取る", systemImage: "qrcode.viewfinder") { scanQR = true }.accessibilityIdentifier("scanPrivateKeyQR")
                Button("既存の秘密鍵を取り込む", systemImage: "square.and.arrow.down") { importer = true }
            }
        }.navigationTitle("SSH 鍵").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $scanQR) { QRKeyImportView() }
            .sheet(item: $selected) { key in
                NavigationStack {
                    Form {
                        Section(key.name) { Text(key.publicKey).font(.system(.body, design: .monospaced)).textSelection(.enabled).accessibilityIdentifier("publicKeyText") }
                        Section {
                            Button("公開鍵をコピー", systemImage: "doc.on.doc") { UIPasteboard.general.string = key.publicKey }
                            Button("公開鍵を共有・保存", systemImage: "square.and.arrow.up") { share(key) }
                        }
                        Text("接続先の ~/.ssh/authorized_keys にこの公開鍵を登録し、接続先の認証設定で割り当ててください。").font(.callout).foregroundStyle(.secondary)
                    }.navigationTitle("公開鍵").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { selected = nil } } }
                }
            }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.data]) { result in
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 1024 * 1024, let pem = String(data: data, encoding: .utf8) else { throw AppError.message("1 MiB 以下の秘密鍵を選択してください。") }
                    importedPEM = pem; name = url.lastPathComponent; passphrase = ""; showImport = true
                } catch { store.error = error.localizedDescription }
            }
            .sheet(isPresented: $showImport, onDismiss: { importedPEM = ""; passphrase = "" }) {
                NavigationStack {
                    Form {
                        TextField("名前", text: $name)
                        SecureField("鍵のパスフレーズ", text: $passphrase)
                        Text("秘密鍵はこの iPhone の Keychain に保存します。パスフレーズは保存しません。").font(.callout).foregroundStyle(.secondary)
                    }.navigationTitle("秘密鍵を取り込む").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { showImport = false } }
                            ToolbarItem(placement: .confirmationAction) { Button("保存") { importKey() } }
                        }
                }
            }
            .confirmationDialog("この鍵を削除しますか？ 割り当てた接続先はパスワード認証に戻ります。", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("鍵を削除", role: .destructive) {
                    if let key = removing {
                        do {
                            try SecureStore.remove(key.id.uuidString)
                            store.configuration.keys.removeAll { $0.id == key.id }
                            for index in store.configuration.profiles.indices where store.configuration.profiles[index].keyID == key.id { store.configuration.profiles[index].keyID = nil }
                        } catch { store.error = error.localizedDescription }
                    }; removing = nil
                }
            }
            .alert("鍵の名前", isPresented: Binding(get: { renamed != nil }, set: { if !$0 { renamed = nil } })) {
                TextField("名前", text: $rename)
                Button("保存") {
                    if let key = renamed, let index = store.configuration.keys.firstIndex(where: { $0.id == key.id }) {
                        store.configuration.keys[index].name = rename
                        store.configuration.keys[index].publicKey = key.publicKey.split(separator: " ").prefix(2).joined(separator: " ") + " " + rename.components(separatedBy: .newlines).joined(separator: " ")
                    }; renamed = nil
                }
                Button("キャンセル", role: .cancel) { renamed = nil }
            }
    }
    private func generate() {
        generating = true; defer { generating = false }
        do {
            let material = try KeyMaterial.generate(name: name)
            let key = SavedKey(name: name, publicKey: material.publicKey)
            try SecureStore.set(Data(material.privateKey.utf8), account: key.id.uuidString)
            store.configuration.keys.append(key); selected = key
        } catch { store.error = error.localizedDescription }
    }
    private func importKey() {
        do {
            let publicKey = try KeyMaterial.publicKey(pem: importedPEM, passphrase: passphrase, name: name)
            let key = SavedKey(name: name, publicKey: publicKey)
            try SecureStore.set(Data(importedPEM.utf8), account: key.id.uuidString)
            store.configuration.keys.append(key); showImport = false; selected = key
        } catch { store.error = error.localizedDescription }
    }
    private func generateHardware() {
        do {
            let material = try KeyMaterial.generateHardware(name: name)
            var key = SavedKey(name: name, publicKey: material.publicKey); key.hardwareBacked = true
            try SecureStore.set(material.data, account: key.id.uuidString)
            store.configuration.keys.append(key); selected = key
        } catch { store.error = error.localizedDescription }
    }
    private func share(_ key: SavedKey) {
        do {
            let folder = store.support.appendingPathComponent("PublicKeys"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safe = key.name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? String($0) : "_" }.joined()
            let url = folder.appendingPathComponent((safe.isEmpty ? "id_ed25519" : safe) + ".pub")
            try (key.publicKey + "\n").write(to: url, atomically: true, encoding: .utf8)
            selected = nil; store.share([url])
        } catch { store.error = error.localizedDescription }
    }
}
