# QR 鍵取り込みと Tailscale

## QR から秘密鍵を取り込む

設定 → 秘密鍵・公開鍵 → QR をカメラで読み取る。送信側で表示する TKQR1 の静止／分割 QR を読み取り、別表示の 24 文字の転送用パスフレーズで復号する。元の鍵が暗号化されていれば、その鍵のパスフレーズも入力する。実際の鍵から得たアルゴリズムと SHA256 fingerprint を確認し、「この iPhone に保存」を押す。接続先の認証設定で保存した鍵を選択できる。

鍵は device-only / when-unlocked Keychain に保管する。元ファイルの暗号化を保ち、どちらのパスフレーズも保存しない。既存鍵の fingerprint が一致する場合は重複保存を拒否する。復号・鍵解析は MainActor の外で行い、閉じる／非アクティブ化／5 分の単調時計タイムアウトで処理世代を破棄する。遅れて完了した処理で画面や保管を更新しない。

形式は [Windows 側 Issue](https://github.com/fuba/terminal/issues/3) と [macOS 側 Issue](https://github.com/fuba/terminal2/issues/6) の TKQR1 revision 1。AES-256-GCM、PBKDF2-HMAC-SHA256 600,000 回、認証された 69-byte ヘッダー、640 文字の分割を実装する。独自の暗号アルゴリズムは導入しない。単一転送のみ、64 枚・32,882 文字まで収集し、混在・競合・改ざん・非正規 base64url・JSON 重複キー・過大サイズ・期限切れを拒否する。撮影済み QR を暗号学的に失効する仕組みではない。

[共通テストベクトル](../Tests/TerminalTransportTests/Fixtures/tkqr1-v1.json) は固定入力から Apple CryptoKit / CommonCrypto で独立生成した codec 用データ。PBKDF2 の結果は Python hashlib とも照合した。復号結果は意図的に SSH 秘密鍵ではなく、鍵取り込みでは拒否されなければならない。実在する秘密鍵や接続先を含まない。両送信側は、このベクトルと相互互換を確認して実装する。

送信側の機能は別リポジトリの Issue に依頼した段階。本アプリの読み取り実装と、完成した両デスクトップアプリからの実機カメラでの相互運用完了は区別する。

## Tailscale の端末一覧

接続先 → Tailscale の端末。通信は、利用者が iPhone の公式 Tailscale アプリで同じ Tailnet に接続した状態で行う。terminalkun2 自身を新しい VPN ノードとして登録する構成ではない。

Tailscale 管理画面の Settings → Trust credentials で OAuth credential を作り、Devices → Core → Read (`devices:core:read`) だけを選ぶ。terminalkun2 に Client ID と Client secret を入力し、「接続して保存」。Tailnet は通常 `-` のままでよい。資格情報は端末内の device-only Keychain に保存する。OAuth アクセストークンは取得ごとに交換し、永続化しない。期限付きアクセストークンの直接入力にも対応する。

端末一覧は固定の `https://api.tailscale.com/api/v2/tailnet/:tailnet/devices` から取得する。接続状態は API の `connectedToControl` を使い、欠落時は「状態不明」とする。オンラインは制御サーバーへの接続状態であり、SSH ポートの到達性を保証しない。再読み込み・pull to refresh・前面復帰で更新でき、取得失敗時は直前の表示と更新時刻を残してエラーを表示する。応答は 4 MiB / 10,000 端末まで。IP アドレス、ID の重複、ホスト入力を検査する。

端末選択時に既存の接続先が一致すれば通常の SSH 認証へ進む。未登録ならホストを入力済みの接続先画面で SSH ユーザー・鍵・ポートを選び、保存して接続する。既存の認証・ホスト鍵照合・接続シートの dismissal を経由する。承認待ちの端末は選択できない。

「連携を解除」は API 資格情報をこの端末から削除する。公式 Tailscale アプリや保存済み SSH 接続先は変更しない。

API 資格情報は公式 HTTPS ホストだけへ送信し、HTTP リダイレクト、cookie、URL cache、credential storage を無効にする。シークレットを URL・設定 JSON・ログへ入れない。API 操作は OAuth トークン交換と端末一覧取得のみ。端末・鍵・ACL の管理操作は実装しない。

根拠: [公式 OAuth / trust credential scopes](https://tailscale.com/docs/reference/trust-credentials)、[Devices API の接続状態追加](https://tailscale.com/changelog#oct-8-2025)、[公式 iOS 接続手順](https://tailscale.com/docs/install/ios)。単調時計による QR の経過時間計測を [Apple の 35F9.1](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons) として PrivacyInfo に申告する。時計情報を送信しない。
