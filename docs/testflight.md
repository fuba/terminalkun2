# iPhone への配信と更新

このプロジェクトは、所有者向けの **TestFlight 内部テスト**で継続更新する。App Store の一般公開は行わない。Apple Developer Program のアカウントを Xcode に登録し、同じ Team / Bundle ID を維持する。

## 初回設定

1. Xcode → Settings → Apple Accounts で Developer Program の Apple Account にサインインする。2要素認証・契約確認は Apple の画面で行い、パスワードをコードや設定ファイルへ保存しない。
2. チームを指定する。

   ```sh
   bash scripts/testflight.sh configure --team YOURTEAMID
   ```

   Bundle ID の初期値は `dev.fuba.terminalkun2`。同じ更新設定の Team / Bundle ID が変わる場合はスクリプトが停止する。チーム ID や配信状態は git 管理外の `build/Distribution/settings.json` に保存する。

3. App Store Connect に iOS アプリを登録する。名前は terminalkun2、言語は日本語、Bundle ID は上記と一致させる。既存レコードがあれば再利用する。
4. TestFlight の内部テストグループへ所有者を追加し、「自動配信」を有効にする。iPhone の TestFlight で同じ Apple Account にサインインし、このアプリの自動アップデートを有効にする。

内部テストは App Store Connect にアクセス権を持つユーザーが対象。外部テストの公開リンクや App Store 公開とは別に扱う。

## 更新

```sh
bash scripts/testflight.sh update
```

ビルド番号を予約し、固定された依存を検査して Release アーカイブを作成し、書き出し時に Apple の配布署名を付ける。IPA の署名・Team・アプリ識別子を検証してから App Store Connect へアップロードする。既存アプリをアンインストールする処理は含まない。

途中から再開する場合:

```sh
bash scripts/testflight.sh status
bash scripts/testflight.sh archive
bash scripts/testflight.sh export
bash scripts/testflight.sh upload
```

アーカイブ段階では署名せず、配布時に Xcode の管理する App Store 用署名を使う。開発用端末の登録は不要。署名を検証した後にアーカイブが変わった場合もアップロードを停止する。

同時実行はロックで防ぐ。失敗したビルド番号を再利用しない。Xcode の `manageAppVersionAndBuildNumber` を使用し、別マシンなどからアップロード済みの番号と競合する場合も Apple 側の既存番号へ対応する。

保存先:

- `build/Distribution/Archives/`: アーカイブ
- `build/Distribution/Export/`: 配布成果物
- `build/Distribution/logs/`: ビルド・署名・アップロードログ
- `build/Distribution/settings.json`: Team / Bundle ID、ビルド番号、最後に成功したアーカイブ・アップロードの状態

証明書の秘密鍵をリポジトリや GitHub Actions に持ち出さず、Xcode と Keychain の署名管理を使用する。自動 CI や常駐のリモートコード実行は追加しない。

## Apple 側の処理

アップロード成功と iPhone での配信開始は別の状態。Apple の処理完了後、TestFlight の状態と内部グループへの配信を確認する。SSH を実装するアプリなので暗号化に関する質問を無条件に「暗号化なし」として回避しない。初回は「標準的な暗号化アルゴリズム」を選び、所有者がフランスへ配信しないことを確認して申告した。この回答で Apple が書類不要とした設定を、次でローカルの配信設定へ記録する。

```sh
bash scripts/testflight.sh encryption --standard-no-france
```

このコマンドは初回アップロードと App Store Connect での申告を完了した後に使用する。以降のアーカイブでは、確認した範囲に限り `ITSAppUsesNonExemptEncryption=false` を生成した Info.plist に設定し、同じ質問による配信停止を避ける。ソースの App/Info.plist へ全利用者共通の申告をハードコードしない。暗号方式や配信地域が変わる場合は申告を再確認する。

TestFlight の各ビルドの有効期間はアップロードから90日。継続利用する場合は期間内に新しいビルドを配信する。新しいビルドの配信は、このコマンドを実行するか、今後の開発作業で実行する。

## 参照

- [Apple: Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [Apple: Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [Apple: Export compliance for beta builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds/)
- [Apple: TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

## 初回配信の検証（2026-11-01）

- Xcode に登録した Developer Team で App Store 用プロファイルを生成し、Apple の cloud-managed Distribution 署名で IPA を書き出した。`codesign --verify --deep --strict`、Apple Distribution の証明書チェーンと正しい Team、アプリ識別子・`get-task-allow=false` の検証は成功。
- 初回のアプリレコード未登録エラーを解消し、App Store Connect に terminalkun2 を登録した。実アップロードが成功し、Apple 側のビルド処理へ進んだ。「個人用」内部グループを作成し、所有者1人と Xcode ビルドの自動配信を設定した。ビルド 0.1.0 (5) がグループ内で「テスト中」となり、所有者から物理 iPhone でインストール・起動できたことを確認した。
- Xcode の IPA 書き出し時に、Homebrew rsync と macOS rsync のオプション差で Copy failed になった。Xcode の子プロセスだけシステムの PATH を先頭にし、署名・パッケージ作成を変更せず解消した。
- 配信状態、Team の実値、証明書、署名済み IPA は git 管理外。パスワードや API key を新規にリポジトリへ保存していない。

- 次回更新で同じ暗号化質問が出ないよう、確認済み申告を配信用 Info.plist にのみ反映する。未申告、フランスあり、独自暗号、ソースの明示的な非免除設定との競合は自動で免除扱いにしない。
- Xcode がローカル SwiftPM package に作る `.swiftpm/xcode/xcuserdata/*.xcuserdatad/xcschemes/xcschememanagement.plist` は実行されない UI 設定なのでハッシュ検査から除外する。それ以外の全ファイルは従来どおり照合し、`.xcscheme` やソース改変を見逃さない回帰試験を追加した。

- 更新ビルド 0.1.0 (8) の実アーカイブ・配布署名・アップロードと、Apple 処理後の自動配信を確認した。追加の暗号化質問なしで、初回 (5) と同じ「個人用」グループの「テスト中」になった。アプリを削除・別登録する処理は行っていない。

## GUI のサインインと CLI の診断（2026-11-01〜02）

ビルド12の配信準備中、`xcodebuild` が `No Accounts` を返し、旧 `DVTDeveloperAccountManagerAppleIDLists` が空でも、起動中の Xcode の Apple Accounts にはアカウントと有効な Developer Team が存在した。GUI から実際に cloud-managed Apple Distribution 署名も成功した。CLI のエラーや旧設定項目だけで「未サインイン」と断定しない。GUI の実状態と署名処理を別々に確認する。

GUI の Organizer は署名なしの中間アーカイブをそのまま配信できず、`No Team Found in Archive` になる。アーカイブの Team メタデータだけでは解消しない。既存の Apple Development 証明書で作業用コピーに実際の中間署名を付け、GUI が最終的な Apple Distribution 署名とプロファイルを適用するところまで確認した。中間署名は実機配信用とは扱わない。

ビルド12では、GUI の配布署名後に IPA 作成の `rsync` 子プロセスが Homebrew 版を選び、前述の `Copy failed` が再現した。署名済みの Payload / SwiftSupport を私有の `build/Distribution/Recovered/Root` に保管し、Apple Distribution の証明書チェーン、設定済み Team、アプリ識別子、`get-task-allow=false` と既存アプリの識別子の一致を strict 検証した。ビルド番号12も確認した。この時点では IPA 作成・アップロードが止まっていたため、TestFlight 配信完了とは扱わなかった。

Xcode をシステムツール優先の PATH で起動し直す準備では、ログインセッションの起動環境を一時的に変更し、起動直後に以前の値へ戻した。GUI の再起動後、アカウントが復元されない状態を実際に観測した。所有者の再サインイン後は登録情報が永続設定にも現れ、2026-11-02 に CLI で IPA の書き出し・strict 検証・アップロードが成功した。App Store Connect で 0.1.0 (12) が処理完了後、同じ「個人用」内部グループの「テスト中」となることを確認した。追加の暗号化質問には止まらず自動配信された。ビルド12の物理 iPhone への更新完了までは、この確認に含めない。

GUI と CLI の登録状態が異なった根本原因は未確定。アカウントの削除、Keychain の認証情報の消去、秘密鍵の書き出しは行っていない。サインイン済みと確認できた時点の事実と、その後の復元・再認証の結果を区別する。

## QR / Tailscale 更新（2026-11-02、ビルド13）

[PR #7](https://github.com/fuba/terminalkun2/pull/7) をマージし、同じ Team / Bundle ID の 0.1.0 (13) を `scripts/testflight.sh update` で実アーカイブ・配布署名・アップロードした。CLI の一連の処理は成功し、Apple のログに `Upload succeeded` と package processing を確認した。GUI のロック解除や Xcode の再サインインは今回の署名に不要だったが、画面をロックしたままの再現試験を行ったという意味ではない。

IPA の strict 署名・識別子・entitlement 検証に加え、ビルド13、カメラの用途文、単調時計の privacy reason 35F9.1、テスト用 SSHFixture と codec fixture が製品へ混入していないことを確認した。TKQR1 は既存の標準暗号 API を用いる形式であり、独自暗号アルゴリズムを追加していない。配信地域を変更せず、既存の確認済み配布設定から Info.plist を生成した。

アップロード時点では App Store Connect の **Web セッション**が期限切れだった。所有者の再サインイン後、同日、ビルド 0.1.0 (13) が Apple の処理を完了し、「個人用」内部グループ・招待1人で「テスト中」となったことを実画面で確認した。追加の暗号化質問には止まらず、自動配信された。Xcode の署名用認証は一貫して利用できていた。物理 iPhone のビルド13への更新完了は、この確認には含めない。

Tailscale の資格情報は IPA へ埋め込まない。利用者の iPhone で初回に読み取り専用 OAuth を設定する。今回の専用 simulator では実 OAuth 認証・実一覧・端末選択・再起動後の Keychain 読込まで確認し、試験後に simulator ごと削除した。物理 iPhone とデスクトップ送信側を組み合わせた QR の実機検証は別途必要。
