// MIT License
import SwiftUI

struct TailscaleHelpView: View {
    var body: some View {
        List {
            Section("1. iPhone を Tailnet に接続") {
                Text("公式 Tailscale アプリを開き、接続先と同じ Tailnet にサインインします。初回は VPN 構成を許可し、Tailscale が接続済みになっていることを確認します。")
                Link("Tailscale の iPhone 設定手順", destination: URL(string: "https://tailscale.com/docs/install/ios")!)
            }
            Section("2. SSH 接続先を準備") {
                Text("接続先にも Tailscale を入れ、同じ Tailnet でオンラインにします。接続先で OpenSSH などの SSH サーバーを起動し、OS のユーザー名、SSH ポート（通常 22）、認証に使う鍵またはパスワードを確認します。macOS は「システム設定 → 一般 → 共有 → リモートログイン」です。")
                Text("Tailnet のアクセスルールと接続先のファイアウォールで、iPhone から SSH ポートへの接続を許可します。")
                Link("Tailscale 経由の SSH", destination: URL(string: "https://tailscale.com/docs/reference/ssh-over-tailscale")!)
            }
            Section("3. 接続先を登録") {
                Text("ホストの Tailscale IP（100.x.x.x）や MagicDNS 名が分かる場合は「接続先 → ＋」で直接登録できます。ユーザー名・ポート・鍵を指定して接続し、初回は表示されたホスト鍵の指紋を接続先で確認します。")
            }
            Section("端末一覧から選びたい場合") {
                Text("Tailscale 管理画面の Trust credentials で「Credential → OAuth」を選びます。Devices → Core の Read（devices:core:read）だけを選んで生成し、その場で Client ID と Client secret を控えます。画面を閉じると secret は再表示できません。")
                Link("Tailscale 管理画面を開く", destination: URL(string: "https://console.tailscale.com/admin/settings/trust-credentials")!)
                Link("OAuth の作成手順", destination: URL(string: "https://tailscale.com/docs/features/oauth-clients")!)
                Text("terminalkun2 の「接続先 → Tailscale の端末」で、Tailnet 名は通常「-」のまま、OAuth の ID と secret を入力し「接続して保存」。一覧から端末を選び、SSH のユーザー名・ポート・鍵を指定します。OAuth の資格情報は端末一覧の取得にだけ使います。")
            }
            Section("接続できないとき") {
                Label("一覧を取得できない", systemImage: "list.bullet")
                Text("401 / 403 は ID・secret、Read 権限、Tailnet を確認します。secret を紛失した場合は管理画面で再発行し、「API 資格情報を変更」で差し替えます。")
                Label("一覧には出るがタイムアウトする", systemImage: "network")
                Text("iPhone 側の VPN、端末承認、アクセスルール、ポートを確認します。名前で失敗する場合は Tailscale IP を直接指定します。一覧のオンライン表示は Tailscale への接続状態です。")
                Label("SSH の認証で止まる", systemImage: "key")
                Text("接続先 OS のユーザー名、鍵、サーバーの認証設定を確認します。通常の SSH サーバーと Tailscale SSH は認証方式が異なります。Tailscale SSH の check モードはこのアプリ内での再認証に対応していません。")
                Link("Tailscale SSH の認証方式", destination: URL(string: "https://tailscale.com/docs/features/tailscale-ssh")!)
            }
        }
        .textSelection(.enabled)
        .navigationTitle("Tailscale の接続手順")
        .navigationBarTitleDisplayMode(.inline)
    }
}
