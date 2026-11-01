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
