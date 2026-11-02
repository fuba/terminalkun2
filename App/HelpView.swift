import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    var embedded = false
    var body: some View {
        if embedded { content }
        else { NavigationStack { content.toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } } } }
    }
    private var content: some View {
        List {
            Section("接続") { Text("接続先の＋からホスト・ユーザー・ポートを登録します。鍵認証では鍵を作成して公開鍵を接続先に登録し、その鍵をプロフィールに割り当てます。初回はホスト鍵の指紋を確認してください。") }
            Section("入力") {
                Text("日本語フリックはアプリ内の独自キーボードで使えます。キーボード上の ⌨ ボタンまたは設定で切り替えます。")
                Text("独自キーボードの「あいう」で日本語フリック、「ABC」で英数へ切り替えます。かなをタップ、または上下左右へ滑らせて離すと入力します。「小゛゜」で直前のかなを変更できます。123 は数字、#+= は記号です。")
                Text("変換・候補選択後に「確定」、Esc で取消。文字の確定では改行を送らず、その次の「改行」で端末へ送信します。")
                Text("入力中の文字と候補はカーソルのそばに表示されます。長い文字列や候補は横にスクロールでき、変換中の文節はタップして選べます。")
                Text("Ctrl / Alt / Shift は次の一打に適用します。連続二回タップでロック、もう一度タップで解除します。Fn には F1〜F12 と Home / End / Page キーがあります。")
            }
            Section("端末操作") {
                Text("長押しと選択ハンドルでコピーできます。Ctrl+C は選択中ならコピー、それ以外では端末へ送信します。⌘C / ⌘V も利用できます。")
                Text("左右の二本指スワイプでタブを切り替えます。一本指の左右スワイプは接続先の tmux ウィンドウを移動します。ピンチで文字サイズを変更できます。")
                Text("ファイル送信・画像の貼り付けは SFTP を使います。送信後は引用済みのリモートパスが入力されます。端末からのクリップボード書き込みには毎回確認が必要です。")
            }
            Section("iPhone での動作") {
                Text("iOS はアプリを長時間バックグラウンドで動作させません。復帰後に同じタブで再接続できます。サーバー側で tmux を使うと作業を維持できます。切断中の入力は下書きになり、自動実行されません。")
                Text("ローカルは Files から参照できるアプリ専用フォルダです。help で利用できる実ファイル操作・ネットワークコマンドを確認できます。任意のプログラム実行には SSH 接続先を使用してください。")
            }
            Section("ライセンス") {
                Text("TerminalKun2: MIT\nSwiftTerm: MIT\nCitadel: MIT\nazooKey: MIT / 辞書データ Apache-2.0\nSwiftNIO・Swift Crypto: Apache-2.0 with Swift exception")
                if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) { Text(text).font(.callout).textSelection(.enabled) }
            }
        }.textSelection(.enabled).navigationTitle("使い方").navigationBarTitleDisplayMode(.inline)
    }
}
