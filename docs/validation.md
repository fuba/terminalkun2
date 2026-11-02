# 検証記録

2026-11-01、Apple Silicon macOS、Xcode 27.2 / iOS 27.2 SDK、Swift 6.2。

## 実行した検証

| 対象 | 結果・内容 |
| --- | --- |
| SwiftPM | 22件。通常実行は21件成功、実推論 API の1件は環境変数なしでは明示 skip。API 指定時の別実行でその1件も成功 |
| iOS 表示単体試験 | 3件。実 UIFont / CoreText / SwiftTerm の文字幅・行高・列数、変換パネルの非表示と長文保持、低い画面での候補操作領域 |
| 実 OpenSSH | 一時 loopback sshd。未知ホスト拒否、暗号化 Ed25519、RSA 3072 + SHA-256、実 ProxyJump、20回の日本語送信と連続 PTY リサイズ、SFTP バイト一致、シェル引用、転送 agent で実 OpenSSH の二段認証、正常 EOF |
| 実推論 API | 既存 llama-swap / Qwen3.5-2B 系モデルの OpenAI 互換 API に実 HTTP 接続。「現在のディレクトリ」の依頼から `pwd` を含む単一行コマンドを生成。Ollama 応答形式と危険な改行の拒否は単体試験 |
| iPhone UI | 独立した一時 iPhone simulator で5件。プロフィール保存・再起動、実 Keychain 鍵生成・公開鍵表示、実ファイルの保存・再読込・検索、独自キーボードの日本語変換・確定・回転・記号、実 SSH パスワード・ホスト鍵確認・PTY コマンド実行 |
| 実機向けビルド | arm64 / iphoneos。署名なし。Debug と Release のビルドを確認 |
| 成果物検査 | アプリ内にアイコン、実辞書、PrivacyInfo.xcprivacy、ThirdPartyNotices.txt を同梱。UI 専用 SSHFixture は含めない |
| 依存 | remote15件を版・revision・公開後24時間・レビュー記録と照合。同梱2件は全ファイルの SHA-256 と公開後24時間を照合 |

試験コマンドは README に記載。通常ログは `build/logs/`、UI の詳細は `build/DerivedData/Logs/Test/*.xcresult`。試験用の秘密鍵、PTY の作業ファイル、接続設定は公開しない。

UI は再起動をまたぐ保存を実際に検証する。繰り返し実行時に既存アプリのデータを消さず、専用シミュレーターを作成・終了時削除して独立させる。実 API 試験では推論サービスをモックに置き換えていない。

## 修正して再検証した問題

- シミュレーターの Keychain entitlement 不足。ad-hoc 署名と simulator 専用の識別子で実保管を確認。
- 接続先シートから認証シートへの競合。onDismiss 後に接続を開始する。
- 日本語候補ボタンの幅ゼロと読み上げ対象欠落。実サイズ計算と accessibility 階層を明示。
- 回転や言語変更後に古い長押しコールバックが実行される問題。タッチの世代検証を追加。
- 日本語 UTF-8 のログ分割と、ローテーション時に OSC 本文が漏れる問題。パーサー状態と未完文字を保存し、全バイト境界・小容量ローテーションで検証。
- RSA の鍵 blob と認証アルゴリズムの混同。RFC 8332 の SHA-256 で実 OpenSSH 認証。
- SSH 正常終了の二重 close。正常 EOF 後の alreadyClosed だけを許容し、他のエラーは伝える。
- ローカルコマンドの引用済み `|` / `>` / `;` を演算子と誤認する問題。字句に演算子属性を保持して、実ファイル試験で確認。
- 設定 JSON の異常な文字サイズ・履歴行数・重複 ID。読込前検証と上書き停止を追加。

## 自己レビュー

変更範囲の UI、通信、鍵、agent、ログ、ファイル、依存ビルド処理を直接確認した。

- ホスト鍵は一致確認が済むまで認証しない。変更鍵は中止する。秘密鍵を JSON、共有、診断ログへ出力しない。
- agent は接続先ごとの opt-in、鍵一つ、署名のみ。前面以外では拒否し、入力サイズと頻度を制限。
- SFTP はランダムな private 送信先、排他ファイル作成、シンボリックリンク拒否、引用済みパス挿入。ローカルファイル解決は symlink を含め sandbox の外を拒否。
- OSC 52 はプレビュー・許可必須。クリップボード読み出しと graphics のローカルファイルアクセスは無効。
- 自由文 API の応答はサイズ・単一行を検査する。確認操作後も Enter を送らない。端末のスクロールバックや認証情報を推論サーバーに送信しない。
- 自動 CI、外部通知、外部への診断自動送信は追加していない。

## 未検証・未対応

初回時点では Tailscale ネットワーク連携が未実装だった。2026-11-02 に公式 API と iOS の既存 Tailscale VPN を使う端末一覧・接続先選択を追加した。今回の検証と、物理 iPhone の追加確認事項は末尾に記載する。

初回移植の検証時点では、この Mac に有効な開発者署名 ID と接続済み物理 iPhone がなかった。その後の TestFlight 配信で、所有者の物理 iPhone へのインストールと起動を確認した。Secure Enclave の物理鍵生成、日本語マイク入力、長時間の OS suspension、MetricKit による実クラッシュ配信は未検証。署名なし app はそのまま実機にインストールできず、Xcode で Team を選んで署名する必要がある。

外付け FIDO2 / OpenSSH `sk-*` は未実装。任意のローカル fork/exec、Android foreground service、リモートからのローカル画像ファイル・共有メモリ読み出しは iOS の設計へ置き換えている。全 VT/xterm 拡張の完全互換、全画像形式の実機表示、すべての SSH サーバーとの互換までは確認していない。Ollama サーバー自体への実接続は未確認で、実推論には OpenAI 互換経路を使った。

## UI 記録

専用の試験データで撮影した画面: [ローカル作業](screenshots/local.png)、[日本語キーボード](screenshots/keyboard.png)、[実 SSH 接続](screenshots/ssh.png)。

字間の調整と、入力中だけ表示する変換パネルの設計・検証は [文字密度と日本語入力](compact-input.md) を参照。

同日の追加検証で、SwiftPM 22件（21成功、実AI 1件は環境未指定でskip）、配信・依存監査14件、iOS表示単体3件とiPhone UI 5件が成功した。実辞書による変換中に端末・キーの位置が動かず、縦横の候補操作と確定、横画面の設定メニュー、実SSHを確認。Releaseアーカイブ12の作成も成功した。最終UI結果は `Test-TerminalKun2-2026.11.01_23-21-31-+0900.xcresult`。

## TestFlight 配信準備の追加検証

同日、Xcode の Developer Team で App Store 用の配布署名済み IPA を作成し、codesign の strict 検証と Team / アプリ識別子 / 配布 entitlement を確認した。配信・依存監査スクリプトの14件と既存 SwiftPM 試験（18件成功、実 AI 1件は環境未指定で skip）が成功。Xcode の中間アーカイブは署名前の状態で、書き出した IPA に配布署名を付ける。

App Store Connect のアプリ登録を完了し、実アップロードが成功した。「個人用」の内部グループに所有者1人を登録し、今後の Xcode ビルドの自動配信を有効にした。初回ビルド 0.1.0 (5) の「テスト中」状態を確認し、所有者から物理 iPhone へインストール・起動できたことを確認した。確認済み暗号化申告を引き継ぐ後続ビルド 0.1.0 (8) も実アップロードし、追加の暗号化質問に止まらず、同じ「個人用」グループで「テスト中」となることを確認した。詳細・再開手順は [TestFlight 配信](testflight.md) を参照。

2026-11-02、字間と変換表示の改善を含む 0.1.0 (12) も配布署名済み IPA の strict 検証・実アップロードが成功し、同じ「個人用」グループで「テスト中」となることを確認した。GUI のサインイン済み状態と CLI の `No Accounts` が一致しない事象、GUI の中間署名と rsync による IPA 作成エラー、その後の復旧経過は配信ドキュメントに記録した。アプリのコード・依存はこの配信確認では変更していない。

## QR と Tailscale の追加検証（2026-11-02）

- SwiftPM 29 件（28 成功、既存の実 AI 1 件は環境未指定で skip）、既存の配信・依存監査 14 件が成功。新規・更新依存はない。Package.resolved と vendor は変更していない。
- TKQR1 は独立した固定 CryptoKit ベクトル、日本語名、順不同・重複・混在・競合、誤パスフレーズ、改ざん、期限切れ・単調時計タイムアウト、サイズ・base64url・JSON 重複キーを検証した。生成した実 Ed25519 鍵のバイト一致、公開鍵導出も確認した。
- 実 OpenSSH 統合試験では、元から暗号化された Ed25519 / RSA 3072 を一旦 QR のフレーム形式へ符号化し、収集・復号後の鍵で実認証した。既存のホスト鍵拒否、PTY、日本語・resize、SFTP、ProxyJump、転送 agent も成功。
- iOS 表示単体 4 件が成功。Core Image で QR 画像を生成し、実 CIDetector で文字列へ戻してから TKQR1 認証付き復号を確認した。Vision はこの simulator の inference context 初期化が失敗したため、製品の AVFoundation カメラとは独立した、モデル推論を要しないネイティブ QR 画像の検証に変更した。検証自体を skip にはしていない。
- 既存 UI 5 件と Tailscale 設定画面の新規 UI 試験が成功。QR の新規 UI 試験は、設定リストの画面外項目をスクロールする修正後、専用 simulator の別実行で成功。カメラ画面の開始・キャンセル・鍵管理への復帰を確認した。最終 QR 結果は `Test-TerminalKun2-2026.11.02_11-21-41-+0900.xcresult`。
- 専用 simulator の製品アプリ画面で、実 Tailscale の読み取り専用 OAuth credential を入力した。実 token 交換・HTTPS devices API による所有 Tailnet の一覧とオンライン状態、一覧選択から正しい Tailnet IP が入った SSH 接続先画面へ進むことを確認した。資格情報・実端末一覧・私有画面は公開成果物へ含めない。
- `bash scripts/dev.sh build` と `bash scripts/dev.sh device` が成功。カメラ用途の説明と、QR タイムアウトの単調時計用途の privacy reason 35F9.1 を同梱する。

自己レビューでは、JSON 重複キーと入力上限、AAD・nonce・KDF の固定条件、期限の二重確認、キャンセル後の遅延結果の破棄、実鍵解析後の明示保存、Keychain の保管属性と重複鍵拒否を確認した。API は公式 HTTPS のみに送り、リダイレクト・cookie・cache・URL credential storage を使わず、OAuth では読み取り scope だけを要求する。既存の認証・ホスト鍵検証を迂回せず、プロフィール編集後は dismissal 後に接続する。

物理 iPhone のカメラと完成した Windows / macOS 送信側を組み合わせた読み取り、物理 iPhone の VPN 越しの SSH、長時間の実機 suspension は今回の simulator 検証とは別の追加確認対象。デスクトップ側は実装依頼 Issue の段階である。Tailscale の API 接続状態は SSH ポートの疎通保証ではない。

同日、QR / Tailscale を含む 0.1.0 (13) の配布署名・IPA 検証・実アップロード後、App Store Connect の処理完了と「個人用」内部グループでの「テスト中」を確認した。追加の暗号化質問なしで自動配信された。詳細は [TestFlight 配信](testflight.md) を参照。物理 iPhone の更新完了は未確認。
