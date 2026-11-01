import XCTest

final class TerminalKun2UITests: XCTestCase {
    func testLocalWorkspaceKeyboardSearchAndSettings() throws {
        let app = XCUIApplication(); app.launch()
        if app.buttons["openLocal"].waitForExistence(timeout: 8) { app.buttons["openLocal"].tap() }
        else { app.buttons["新しいタブ"].tap(); app.buttons["openLocalFromConnections"].tap() }
        let surface = app.scrollViews["terminalSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        app.buttons["キーボード"].tap()
        surface.typeText("echo terminalkun2-ui-check\n")
        app.buttons["端末内を検索"].tap()
        let search = app.textFields["terminalSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap(); search.typeText("terminalkun2-ui-check\n")
        app.buttons["検索を閉じる"].tap()
        app.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 3))
        app.switches["プログラミング用キーボード"].tap()
        app.buttons["完了"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "iPhone terminal"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testConnectionProfilePersists() {
        let app = XCUIApplication(); app.launch()
        app.buttons["接続先"].tap()
        app.buttons["接続先を追加"].firstMatch.tap()
        let host = app.textFields["profileHost"]; XCTAssertTrue(host.waitForExistence(timeout: 3)); host.tap(); host.typeText("localhost")
        let user = app.textFields["profileUser"]; user.tap(); user.typeText("test")
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "test@localhost").firstMatch.waitForExistence(timeout: 3))
        app.terminate(); app.launch(); app.buttons["接続先"].tap()
        XCTAssertTrue(app.staticTexts["test@localhost"].waitForExistence(timeout: 3))
    }
}
