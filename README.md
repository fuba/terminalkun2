# terminalkun2

[fuba/terminalkun](https://github.com/fuba/terminalkun) の iPhone / iPad 向け移植です。[terminal2](https://github.com/fuba/terminal2) の配色・アイコンを引き継ぎ、接続先、設定、鍵、共有は iOS の標準 UI に合わせています。iOS 17 以降に対応します。

実 SSH の PTY、パスワード・公開鍵認証、ProxyJump、SFTP、複数タブ、日本語入力、プログラミング用キーボード、スクロールバック検索、画像表示、音声入力、コマンド生成を実装しています。デモ接続はありません。

## 使う

1. 最初に `bash scripts/dev.sh resolve` と `bash scripts/dev.sh build` を実行します。
2. Xcode で `TerminalKun2.xcodeproj` を開き、File → Project Settings の Derived Data を、このリポジトリの `build/DerivedData` に指定します。TerminalKun2 ターゲットの Signing Team を選び、接続した iPhone で Run します。固定版 SwiftTerm のホスト generator を共有するため、このビルド領域を使用します。
3. 「接続先」からホスト・ユーザーを登録します。鍵を使う場合は「設定 → 秘密鍵・公開鍵」で生成または取り込み、公開鍵をサーバーの `~/.ssh/authorized_keys` に登録します。
4. 初回接続ではホスト鍵の指紋を確認します。

標準の iOS キーボードが初期値です。「設定 → 独自キーボード」または入力補助バーの ⌨ から切り替えます。「あいう」で日本語12キーフリック、「ABC」で英数 QWERTY。かなをタップまたは上下左右へフリックし、「小゛゜」で濁点・半濁点・小書きを変更できます。変換中の「確定」は文字の確定だけを行い、次の「改行」で端末へ改行を送ります。

独自キーボードの入力文字・候補は、入力中だけカーソルのそばに表示します。常設の変換欄はなく、入力開始・確定で端末やキーの位置は変わりません。長い入力や候補は横スクロールできます。

フリックの数字・記号、取消、VoiceOver 操作は [日本語フリック](docs/japanese-flick.md) を参照。

SSH agent 転送は接続先ごとに明示的に有効にできます。選択した鍵だけを公開し、アプリが前面にある間だけ署名します。ハードウェア保護鍵には iPhone の Secure Enclave を使います。**外付け FIDO2 / `sk-*` 鍵は未対応です。**

コマンド生成には Ollama の URL、または OpenAI 互換の `/v1` URL とモデル名を設定します。依頼文だけを送信し、応答を確認してから入力欄へ挿入します。自動実行はしません。

## TestFlight でインストール・更新する

所有者向けの配信は TestFlight の内部テストを使います。[初回設定と更新手順](docs/testflight.md)に従って Team と App Store Connect のアプリを設定した後は、次で署名検証とアップロードを繰り返せます。

```sh
bash scripts/testflight.sh update
```

同じ Team / Bundle ID を保持し、ビルド番号を更新します。iPhone の TestFlight で自動アップデートを有効にすると、新しい配信を受け取れます。

## 開発と検証

Xcode 27.2 / Swift 6.2、XcodeGen、Python 3 を使用して検証しました。署名なしの実機向けビルドも可能です。

```sh
bash scripts/dev.sh resolve
bash scripts/dev.sh test
bash scripts/dev.sh build
bash scripts/dev.sh device
bash scripts/ssh-ui-test.sh
```

最後のコマンドは専用の一時 iPhone シミュレーターを作成し、loopback の実 SSH サーバーと macOS PTY を使って UI を操作します。終了時にサーバーと一時シミュレーターを削除し、既存シミュレーターのデータは変更しません。シミュレーター ID は `scripts/dev.sh ui <UDID>` で指定できます。実 API の生成試験は次で実行します。

```sh
TERMINALKUN2_AI_TEST_ENDPOINT=https://your-server.example/v1 \
TERMINALKUN2_AI_TEST_MODEL=your-model \
bash scripts/ai-integration-test.sh
```

ビルド・試験のログと成果物は `build/` に保存します。依存は固定し、ビルド前に公開後24時間以上・レビュー済みリビジョン・同梱ソースのハッシュを検査します。GitHub Actions は自動実行しません。

## iOS での違い

iOS は任意のローカルプログラムの fork/exec と、無期限のバックグラウンド SSH を提供しません。ローカルタブはアプリの Documents/Workspace 内で実ファイル操作、パイプ、リダイレクト、HTTP を行うコマンド環境です。任意のシェル・プロセスは SSH 接続先で動かしてください。復帰後は同じタブで再接続し、切断中の入力は自動実行しない下書きとして戻せます。

詳細は [機能対応表](docs/feature-parity.md)、[検証記録](docs/validation.md)、[実装構成](docs/implementation.md)、[SSH ライブラリ修正](Vendor/PATCHES.md) を参照してください。

初回実装では署名なしの実機向けビルドを検証し、その後 TestFlight 用の Apple Distribution 署名済み IPA も作成しました。TestFlight での配信後、所有者の iPhone へのインストールと起動を確認しました。自動更新の設定は [配信記録](docs/testflight.md)を参照してください。Secure Enclave とマイク入力の実機確認は未実施です。

## ライセンス

MIT。第三者ライブラリ・辞書の表記は [ThirdPartyNotices.txt](Resources/ThirdPartyNotices.txt) に収録し、アプリ内の「使い方」からも読めます。
