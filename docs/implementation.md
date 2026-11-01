# 実装構成

参照元: `fuba/terminalkun@3d61cd82885e5c39c47a41c2613bae3c49011cb5`。
macOS 版参照: `fuba/terminal2@8354ec9c1c3420a0dfae83181195c3798f546cd4`。

SwiftUI の NavigationStack / Form / sheet と UIKit の端末・入力を使用する。WebView やデモ接続は使用しない。

- TerminalCore: 設定、SSH config、キー符号化、下書き、ログ除去、サンドボックス内ファイル操作、コマンド生成 HTTP。
- TerminalTransport: 鍵の生成・解読、SSH ホスト検証、PTY、順序付き送信、リサイズ、SFTP、踏み台、SSH agent。
- TerminalIME: azooKey の実辞書、連文節・境界調整、候補学習、ユーザー辞書。
- TerminalRenderer: SwiftTerm の UIKit / Metal 描画。
- App: Keychain、セッション管理、ネイティブ UI、独自キーボード、Speech、MetricKit。
- Tools/SSHFixture: UI 試験専用の loopback SSH + macOS PTY。アプリには含めない。

認証のシートは接続先シートの終了イベント後に開始する。秘密鍵は公開メタデータと分け、パスワード類はプロセス内だけに保持する。入力と PTY リサイズを同じ通信キューで処理し、日本語の確定時に暗号化ストリームの順序を崩さない。

iOS の background task 終了で接続を閉じ、復帰時に同じタブへ接続する。停止・回転・言語切り替えで独自キーボードのタッチ世代を更新し、古いリピート処理が発火することを防ぐ。

SwiftTerm のビルドツールは Xcode 27 の iOS ビルド時にホスト側の実行ファイルが欠落するため、同じ固定版の SwiftPM executable を先に macOS 向けにビルドし、Xcode のホストツール領域へ配置する。処理を削除せず、本来の generator で build metadata / terminfo を生成する。

シミュレーターでも Keychain を使用する。署名なしでは Keychain entitlement エラーになるため、シミュレーター専用の application-identifier / keychain group を付けて ad-hoc 署名する。実機向けは Xcode の選択 Team で署名する。

依存15件の公開日・固定版・レビューは `docs/dependency-audit.json`、同梱2件の全ファイルハッシュは `docs/vendor-audit.json`、SSH の修正は `Vendor/PATCHES.md`。ビルド前に検査する。自動 CI は追加しない。
