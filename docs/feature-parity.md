# terminalkun からの機能対応

移植元: `fuba/terminalkun@3d61cd82885e5c39c47a41c2613bae3c49011cb5`。
併せて参照した macOS 版: `fuba/terminal2@8354ec9c1c3420a0dfae83181195c3798f546cd4`。
移植先は SwiftUI / UIKit のアプリであり、Android APK や WebView をラップしません。

| 元の機能群 | iPhone 版 |
| --- | --- |
| 独自キーボード、英数・日本語、修飾キー、Fn、記号 | UIKit のマルチタッチ入力。sticky / double-tap lock、独立した長押しリピート、回転・離脱で停止。標準 iOS IME と切り替え可 |
| Mozc 完全辞書・予測・連文節・学習・ユーザー辞書 | 同梱 azooKey 実辞書に適応。文節選択、境界変更、予測、端末内の候補学習、永続ユーザー辞書。確定と改行を分離。入力中だけカーソル付近に読み・候補を重ね、常設欄の高さを取らない |
| プロフィール、お気に入り、タブ復元 | ネイティブ List / Form。順序・名前・選択位置・下書き復元。SSH は再認証・再接続待ち |
| Tailscale ネットワーク連携（参照 macOS 版） | 公式 iOS Tailscale VPN と連携。読み取り専用 OAuth / API による実 Tailnet 一覧、制御サーバーへの接続状態、再読み込み、一覧からの接続先作成・SSH 接続。初回に API 資格情報を設定。実機 VPN 越しの SSH は追加確認対象 |
| デスクトップ版からの QR 鍵転送 | カメラで TKQR1 の単一・分割 QR を収集し、認証付き復号、実鍵の fingerprint 確認後に device-only Keychain へ保存。送信側は terminal #3 / terminal2 #6 に実装依頼中 |
| OpenSSH config | Files 取り込み、永続 bookmark と起動時再同期、Host / HostName / User / Port / ワイルドカード / 否定パターン / ProxyJump。Include / Match は通知。ProxyCommand 等の任意実行設定は接続を止めて明示 |
| SSH PTY、パスワード、鍵、ホスト鍵 | 実 Citadel / NIOSSH 接続。Ed25519 生成、暗号化 Ed25519 / RSA 取り込み、ECDSA、厳格なホスト鍵照合・Keychain 保管。公開鍵のみコピー・共有・保存、名称変更・削除 |
| keep-alive、自動再接続 | 15秒間隔、3回失敗判定、同じタブで上限60秒の指数バックオフ。入力とリサイズは順序を保つ単一キュー |
| SFTP、ファイル・画像貼り付け | Files、共有 URL、ドラッグ＆ドロップ、クリップボード画像。ランダムな private `/tmp` ディレクトリ、排他作成、シェル引用済みパスを挿入 |
| VT / xterm、True Color、CJK、代替画面 | SwiftTerm の実 VT エンジンと UIKit / Metal。DA / DSR、カーソルモード、マウス、選択、検索、bracketed paste、OSC タイトル・ディレクトリ |
| リンク・クリップボード | OSC 8 と検出リンクは http(s) のみ起動。OSC 52 書き込みは1 MiB制限・内容確認必須。読み出しは拒否 |
| Sixel / iTerm2 / Kitty 画像 | SwiftTerm の同梱デコーダー。Kitty の分割、キャッシュ、アニメーション、Unicode placeholder を含む。リモートから端末内ファイル・共有メモリへのアクセスは許可しない |
| tmux 操作 | マウス、ホイール、独立 exec チャネルの mouse 設定と global prefix 取得。prefix を検証して左右スワイプを送信。二本指でアプリのタブ切り替え |
| 表示設定・フォント・キー割り当て | 5配色、背景不透明度、文字サイズ、スクロールバック行数、TTF/OTF、記録可能な物理キー設定、ピンチ拡縮。⌘ を iOS の既定操作へ適応 |
| ローカル forkpty シェル | iOS の制約に適応した実ファイル・HTTP コマンド環境。任意の実行ファイルを動かす POSIX シェルとは異なる |
| Android Foreground Service | iOS の短時間 background task と、復帰後の再接続へ適応。サーバーの tmux によりプロセスを保持 |
| セッションログ | opt-in、ANSI / OSC / DCS / APC / C1 除去、UTF-8 境界保持、4 MiB / 最大20ファイル、共有。診断ログとは別扱い |
| 音声・コマンド候補 | Speech / AVAudioEngine の日本語認識、編集・確認、定型候補。Ollama / OpenAI 互換 API による自由文生成、単一行検証、挿入のみ |
| 診断・性能 | MetricKit のクラッシュ・メトリクス、SwiftTerm の処理統計、容量制限付き私有ログ。外部への自動送信なし |

## 元で未完成だった部分

- **SSH agent:** 実装済み。選択鍵一つだけを転送し、実 OpenSSH の二段接続で認証を確認。前面時のみ署名、操作・サイズ・頻度制限付き。
- **ハードウェア鍵:** Secure Enclave P-256 の生成・SSH署名を実装。実機用ビルド済み。外付け FIDO2 / OpenSSH `sk-*` 鍵は未実装であり、Secure Enclave と同じものとは扱わない。
- **VT/xterm の拡充:** 試作独自パーサーを SwiftTerm へ置換。全端末・全拡張との完全互換を保証するものではない。
- **Kitty の拡充:** エンジンのアニメーション・Unicode placeholder を使用。SSH 接続先のファイル名・共有メモリを iPhone のローカルパスとして開く転送方式は採用しない。直接 / 分割転送を使用する。
- **自由文 AI:** 実 HTTP クライアントを実装。実推論サーバーで確認必須の単一行コマンド生成を検証。認識・生成・実行を自動で連結しない。

## 完了判定に残っている項目

従来漏れていた Tailscale 一覧は、iPhone から直接公式 HTTPS API を使う形で実装した。Mac の CLI を iPhone で呼ぶ前提やサンプル端末一覧は使わない。公式 VPN 越しの物理 iPhone の SSH 接続と、両デスクトップ送信側の完成後の QR カメラ相互運用は追加確認対象。操作・保管・方式は [QR と Tailscale](qr-and-tailscale.md) を参照。

## 保管と再起動

秘密鍵と信頼したホスト鍵は、この端末だけの unlock 時 Keychain。パスワード・パスフレーズは設定 JSON に保存しない。セッション本文は既定では記録しない。設定・ユーザー辞書・学習・opt-inログはアプリ内に保存し、設定 JSON を外部編集した場合は毎秒再読込する。不正な JSON や危険な表示範囲では直前の設定を継続し、元ファイルを修正するまで保存を停止する。
