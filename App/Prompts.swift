import SwiftUI
import TerminalTransport

struct AuthenticationView: View {
    @EnvironmentObject var store: AppStore
    let prompt: AuthenticationPrompt
    @State private var password = ""
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(prompt.profile.address).textSelection(.enabled) }
                Section {
                    SecureField(prompt.profile.keyID == nil ? "パスワード" : "鍵のパスフレーズ", text: $password).textContentType(.password).accessibilityIdentifier("sshPassword")
                }
            }
            .navigationTitle("SSH 認証").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { store.finishAuthentication(password: nil) } }
                ToolbarItem(placement: .confirmationAction) { Button("接続") {
                    store.finishAuthentication(password: prompt.profile.keyID == nil ? password : "", passphrase: prompt.profile.keyID == nil ? "" : password); password = ""
                }.bold().accessibilityIdentifier("authenticateSSH") }
            }
        }.presentationDetents([.medium, .large]).interactiveDismissDisabled()
    }
}

struct HostVerificationView: View {
    @EnvironmentObject var store: AppStore
    let prompt: HostPrompt
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(prompt.profile.address).textSelection(.enabled) }
                Section("ホスト鍵の指紋") { Text(HostTrust.fingerprint(prompt.key)).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                Section { Text("接続先の管理者が示す指紋と一致することを確認してください。このホストへの初めての接続です。") }
                Section { Button("このホスト鍵を信頼して接続") { store.acceptHost(true) }.accessibilityIdentifier("trustHost") }
            }
            .navigationTitle("ホスト鍵を確認").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("中止") { store.acceptHost(false) } } }
        }.interactiveDismissDisabled()
    }
}

struct ClipboardView: View {
    @EnvironmentObject var store: AppStore
    let prompt: ClipboardPrompt
    var body: some View {
        NavigationStack {
            ScrollView { Text(prompt.text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                .navigationTitle("リモートからのコピー").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("拒否") { store.clipboard = nil } }
                    ToolbarItem(placement: .confirmationAction) { Button("コピーを許可") { UIPasteboard.general.string = prompt.text; store.clipboard = nil } }
                }
        }
    }
}
