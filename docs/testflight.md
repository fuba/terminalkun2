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

アップロード成功と iPhone での配信開始は別の状態。Apple の処理完了後、TestFlight の状態と内部グループへの配信を確認する。SSH を実装するアプリなので暗号化に関する質問を無条件に「暗号化なし」として回避しない。必要な書類や回答は App Store Connect の暗号化設定へ記録する。

TestFlight の各ビルドの有効期間はアップロードから90日。継続利用する場合は期間内に新しいビルドを配信する。新しいビルドの配信は、このコマンドを実行するか、今後の開発作業で実行する。

## 参照

- [Apple: Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [Apple: Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [Apple: Export compliance for beta builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds/)
- [Apple: TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

## 初回配信の検証（2026-11-01）

- Xcode に登録した Developer Team で App Store 用プロファイルを生成し、Apple の cloud-managed Distribution 署名で IPA を書き出した。`codesign --verify --deep --strict` とアプリ識別子・Team・`get-task-allow=false` の検証は成功。
- アップロードを実行し、App Store Connect にアプリレコードが未登録のため Apple から明確なエラーを受け取った。アプリ登録・内部グループ設定は未完了で、iPhone への配信成功とは扱わない。
- Xcode の IPA 書き出し時に、Homebrew rsync と macOS rsync のオプション差で Copy failed になった。Xcode の子プロセスだけシステムの PATH を先頭にし、署名・パッケージ作成を変更せず解消した。
- 配信状態、Team の実値、証明書、署名済み IPA は git 管理外。パスワードや API key を新規にリポジトリへ保存していない。
