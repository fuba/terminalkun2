import XCTest
import TerminalRenderer

final class RendererTests: XCTestCase {
    private final class Delegate: TerminalDelegate { func send(source: Terminal, data: ArraySlice<UInt8>) {} }
    func testTrueColorAlternateScreenAndWideCharacters() {
        let delegate = Delegate()
        let terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: 40, rows: 10))
        terminal.feed(text: "\u{1b}[38;2;10;20;30m日本語\u{1b}[0m")
        XCTAssertEqual(terminal.getCharData(col: 0, row: 0)?.getCharacter(), "日")
        terminal.feed(text: "\u{1b}[?1049hALT\u{1b}[?1049l")
        XCTAssertEqual(terminal.getCharData(col: 0, row: 0)?.getCharacter(), "日")
    }
}

extension RendererTests {
    func testLinksAcrossScreenRedrawAndVTWrap() {
        let delegate = Delegate()
        let terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: 24, rows: 6))
        terminal.feed(text: "\u{1b}[?1049h日  https://example.test\u{1b}[2;1H/path?q=123\r\n次の行\r\nhttps://example.test/soft-wrapped")
        let rows = terminal.contentSnapshot(region: .viewport).rows
        XCTAssertEqual(TerminalWebLink.at(row: 0, col: 9, rows: rows)?.absoluteString, "https://example.test/path?q=123")
        XCTAssertEqual(TerminalWebLink.at(row: 1, col: 2, rows: rows)?.absoluteString, "https://example.test/path?q=123")
        XCTAssertEqual(TerminalWebLink.at(row: 4, col: 2, rows: rows)?.absoluteString, "https://example.test/soft-wrapped")
        XCTAssertNil(TerminalWebLink.at(row: 0, col: 2, rows: rows))
        XCTAssertNil(TerminalWebLink.at(row: 2, col: 0, rows: rows))
    }

    func testLinksDoNotJoinShortHardLinesOrSeparateURLs() {
        let delegate = Delegate()
        let terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: 24, rows: 6))
        terminal.feed(text: "https://short.test\r\nother\r\nhttps://example.test/abc\r\nhttps://two.test\r\n(https://punct.test/x).")
        let rows = terminal.contentSnapshot(region: .viewport).rows
        XCTAssertEqual(TerminalWebLink.at(row: 0, col: 2, rows: rows)?.host, "short.test")
        XCTAssertNil(TerminalWebLink.at(row: 1, col: 2, rows: rows))
        XCTAssertEqual(TerminalWebLink.at(row: 2, col: 2, rows: rows)?.absoluteString, "https://example.test/abc")
        XCTAssertEqual(TerminalWebLink.at(row: 3, col: 2, rows: rows)?.host, "two.test")
        XCTAssertEqual(TerminalWebLink.at(row: 4, col: 2, rows: rows)?.absoluteString, "https://punct.test/x")
        XCTAssertNil(TerminalWebLink.safeURL("https://trusted.test@other.test"))
        XCTAssertNil(TerminalWebLink.safeURL("file:///private/test"))
    }
}
