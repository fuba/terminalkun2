import XCTest

final class TerminalKun2UITests: XCTestCase {
    func testLocalWorkspaceKeyboardSearchAndSettings() throws {
        let app = XCUIApplication(); app.launchEnvironment["TERMINALKUN2_UI_TESTS"] = "1"; app.launch()
        if app.buttons["openLocal"].waitForExistence(timeout: 8) { app.buttons["openLocal"].tap() }
        else { app.buttons["新しいタブ"].tap(); app.buttons["openLocalFromConnections"].tap() }
        let surface = app.descendants(matching: .any)["terminalSurface"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        app.buttons["キーボード"].tap()
        app.typeText("echo terminalkun2-ui-check > ui-check.txt\ncat ui-check.txt\n")
        app.buttons["端末内を検索"].tap()
        let search = app.textFields["terminalSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap(); search.typeText("terminalkun2-ui-check\n")
        XCTAssertNotEqual(app.staticTexts["searchMatchCount"].label, "0/0")
        app.buttons["検索を閉じる"].tap()
        app.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 3))
        let modeSwitch = app.switches["customKeyboardMode"]
        if modeSwitch.switches.firstMatch.exists { modeSwitch.switches.firstMatch.tap() } else { modeSwitch.tap() }
        app.buttons["完了"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "iPhone terminal"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testConnectionProfilePersists() {
        let app = XCUIApplication(); app.launchEnvironment["TERMINALKUN2_UI_TESTS"] = "1"; app.launch()
        app.buttons["接続先"].tap()
        app.buttons["接続先を追加"].firstMatch.tap()
        let host = app.textFields["profileHost"]; XCTAssertTrue(host.waitForExistence(timeout: 3)); host.tap(); host.typeText("localhost")
        let user = app.textFields["profileUser"]; user.tap(); user.typeText("test")
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "test@localhost").firstMatch.waitForExistence(timeout: 3))
        app.terminate(); app.launch(); app.buttons["接続先"].tap()
        XCTAssertTrue(app.staticTexts["test@localhost"].waitForExistence(timeout: 3))
    }
    func testSSHPasswordHostTrustAndRealRemoteCommand() throws {
        guard ProcessInfo.processInfo.environment["TERMINALKUN2_SSH_UI"] == "1" else { throw XCTSkip("Run scripts/ssh-ui-test.sh to start the real loopback SSH fixture") }
        let app = XCUIApplication(); app.launchEnvironment["TERMINALKUN2_UI_TESTS"] = "1"; app.launch()
        app.buttons["接続先"].tap(); app.buttons["接続先を追加"].firstMatch.tap()
        let name = app.textFields["profileName"]; name.tap(); name.typeText("iPhone SSH integration")
        let host = app.textFields["profileHost"]; host.tap(); host.typeText("127.0.0.1")
        let user = app.textFields["profileUser"]; user.tap(); user.typeText("ios-test")
        let fixturePort = ProcessInfo.processInfo.environment["TERMINALKUN2_FIXTURE_PORT"] ?? "22292"
        let port = app.textFields["profilePort"]
        port.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        port.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + fixturePort)
        app.buttons["saveProfile"].tap()
        let connection = app.buttons.containing(.staticText, identifier: "ios-test@127.0.0.1:" + fixturePort).firstMatch
        guard connection.waitForExistence(timeout: 5) else { XCTFail(app.debugDescription); return }
        connection.tap()
        let password = app.secureTextFields["sshPassword"]; XCTAssertTrue(password.waitForExistence(timeout: 8)); password.tap(); password.typeText("test-only-password")
        app.buttons["authenticateSSH"].tap()
        if app.buttons["trustHost"].waitForExistence(timeout: 5) { app.buttons["trustHost"].tap() }
        XCTAssertTrue(app.staticTexts["接続済み"].waitForExistence(timeout: 15))
        app.buttons["キーボード"].tap()
        app.typeText("printf 'IPHONE-SSH-OK\\n' > iphone.txt\ncat iphone.txt\n")
        app.buttons["端末内を検索"].tap()
        let search = app.textFields["terminalSearch"]; search.tap(); search.typeText("IPHONE-SSH-OK\n")
        XCTAssertNotEqual(app.staticTexts["searchMatchCount"].label, "0/0")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Real SSH on iPhone"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testProgramKeyboardJapaneseCommitAndRotation() {
        let app = XCUIApplication(); app.launchEnvironment["TERMINALKUN2_UI_TESTS"] = "1"; app.launch()
        app.buttons["新しいタブ"].tap(); app.buttons["openLocalFromConnections"].tap()
        app.buttons["設定"].tap()
        let toggle = app.switches["customKeyboardMode"]
        if toggle.value as? String != "オン" {
            if toggle.switches.firstMatch.exists { toggle.switches.firstMatch.tap() } else { toggle.tap() }
        }
        XCTAssertEqual(toggle.value as? String, "オン")
        app.buttons["完了"].tap(); app.buttons["キーボード"].tap()
        func key(_ name: String) -> XCUIElement { app.descendants(matching: .any)["program-key-" + name].firstMatch }
        XCTAssertTrue(key("e").waitForExistence(timeout: 5))
        for name in ["e", "c", "h", "o", "space", "language", "n", "i", "h", "o", "n", "g", "o", "space"] { key(name).tap() }
        XCTAssertTrue(app.buttons["candidate-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["candidate-0"].label.contains("日本語"))
        key("enter").tap()
        let preedit = app.descendants(matching: .any)["compositionText"].firstMatch
        XCTAssertFalse(preedit.exists && preedit.label.contains("日本語"))
        key("enter").tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(key("symbols").waitForExistence(timeout: 5)); key("symbols").tap()
        XCTAssertTrue(key("=").waitForExistence(timeout: 3))
        XCUIDevice.shared.orientation = .portrait
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Japanese programmer keyboard"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testKeychainKeyGenerationExposesOnlyPublicKey() {
        let app = XCUIApplication(); app.launchEnvironment["TERMINALKUN2_UI_TESTS"] = "1"; app.launch()
        app.buttons["設定"].tap()
        let keys = app.buttons["秘密鍵・公開鍵"]
        for _ in 0..<4 where !keys.isHittable { app.swipeUp() }
        XCTAssertTrue(keys.exists); keys.tap()
        let generate = app.buttons["generateKey"]
        for _ in 0..<4 where !generate.isHittable { app.swipeUp() }
        generate.tap()
        let publicKey = app.staticTexts["publicKeyText"]
        XCTAssertTrue(publicKey.waitForExistence(timeout: 5))
        XCTAssertTrue(publicKey.label.hasPrefix("ssh-ed25519 "))
        XCTAssertFalse(publicKey.label.contains("PRIVATE"))
    }
}
