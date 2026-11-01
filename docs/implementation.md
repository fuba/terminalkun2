# iPhone 移植作業

参照元: fuba/terminalkun@3d61cd82885e5c39c47a41c2613bae3c49011cb5。
macOS 移植の参照: fuba/terminal2@8354ec9c1c3420a0dfae83181195c3798f546cd4。

## 方針

SwiftUI の NavigationStack / Form / sheet と UIKit の端末・入力を使用する。
WebView やデモ接続は使用しない。端末は SwiftTerm、SSH は Citadel / NIOSSH、
独自キーボードの日本語入力は実辞書を含む azooKey を使用する。
既定は iOS の日本語入力、独自キーボードは切り替えて使用可能。

元のアプリの試作機能も検証対象に含める。特に切断中の入力、ホスト鍵の変更、
日本語確定と改行の分離、複数指とキーリピート、画像プロトコルを確認する。

## 構成

- TerminalCore: 設定モデル、SSH config、キー符号化、下書き、ログ除去、実ファイル操作、コマンド生成 HTTP。
- TerminalTransport: 鍵の生成・解読、SSH ホスト検証、PTY、順序付き送信、リサイズ、SFTP、踏み台。
- TerminalIME: 実辞書によるローマ字・かな漢字変換、候補・ユーザー辞書。
- TerminalRenderer: SwiftTerm の UIKit / Metal 描画。
- App: ネイティブ UI、Keychain、セッション管理、独自キーボード、音声入力。

## iOS の境界

iOS は fork/exec による任意のシェル実行と、無期限のバックグラウンド SSH 維持を提供しない。
ローカルはアプリの Documents 内の実ファイル操作と HTTP 通信を行うコマンド環境。
リモートの任意コマンドは実 SSH の PTY へ送信する。バックグラウンドは OS の猶予期間を使い、
復帰時に同じタブで再接続する。切断中の入力は明示的に戻す下書きにし、Enter を自動送信しない。

## 作業中の検証

2026-11-01: macOS の単体試験で設定・入力・ログ・実ファイル操作・実辞書変換を確認。
一時 loopback OpenSSH との暗号化 Ed25519 鍵、未知鍵拒否、日本語20回・PTY連続リサイズ、
SFTP の引用を要するファイル名と内容一致を検証。SSH 終了時の Citadel の二重 close を修正中。
iOS SDK / iPhone シミュレーターでのビルドと UI 試験を実施中。

SwiftTerm のビルドツールは Xcode 27 の iOS ビルド時にホスト側の実行ファイルが欠落するため、
同じ固定版の SwiftPM executable を先に macOS 向けにビルドして、Xcode のホストツール領域へ配置する。
ツールの処理は削除せず、build metadata / terminfo を本来の generator で生成する。
自動 CI は追加しない。依存全17件の公開時刻・固定リビジョン・ソースレビューを記録する。
