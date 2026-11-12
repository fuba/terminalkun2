// MIT License
import Foundation
import SwiftTerm

public enum TerminalWebLink {
    private static let pattern = try! NSRegularExpression(pattern: #"https?://[^\s<>"'`\x00-\x20\\]+"#, options: .caseInsensitive)

    public static func safeURL(_ value: String) -> URL? {
        guard value.utf8.count <= 4096, let components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else { return nil }
        return components.url
    }

    /// Find a web link under a cell, retaining VT soft wraps and the full-width
    /// line seams produced when screen/tmux redraw wrapped terminal output.
    public static func at(row: Int, col: Int, rows: [TerminalContentRowSnapshot]) -> URL? {
        guard rows.indices.contains(row), rows[row].cells.indices.contains(col) else { return nil }
        let start = max(0, row - 8), end = min(rows.count - 1, row + 8)
        var text = ""
        var target: Int?
        var offset = 0
        for index in start...end {
            let line = rows[index]
            if index > start {
                let previous = rows[index - 1]
                let continued = line.isWrapped || isFullWidthSeam(previous: previous, next: line)
                if !continued { text.append("\n"); offset += 1 }
            }
            var column = 0
            while column < line.cells.count {
                let cell = line.cells[column]
                let width = max(1, cell.width)
                let value = cell.text.isEmpty || cell.text == "\0" ? " " : cell.text
                if index == row && (column..<column + width).contains(col) { target = offset }
                text += value
                offset += value.utf16.count
                column += width
            }
        }
        guard let target else { return nil }
        let nsText = text as NSString
        let match = pattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)).first {
            NSLocationInRange(target, $0.range)
        }
        guard let match, match.range.length <= 4096 else { return nil }
        var value = nsText.substring(with: match.range)
        let opening: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        var counts: [Character: Int] = [:]
        for char in value where "()[]{}".contains(char) { counts[char, default: 0] += 1 }
        while let last = value.last {
            if ".,;:!?".contains(last) { value.removeLast() }
            else if let open = opening[last], counts[last, default: 0] > counts[open, default: 0] {
                counts[last, default: 0] -= 1
                value.removeLast()
            } else { break }
        }
        guard target < match.range.location + value.utf16.count else { return nil }
        return safeURL(value)
    }

    private static func isFullWidthSeam(previous: TerminalContentRowSnapshot, next: TerminalContentRowSnapshot) -> Bool {
        guard let last = previous.cells.last?.text.last,
              let first = next.cells.first?.text.first,
              isURLCharacter(last), isURLCharacter(first) else { return false }
        let prefix = next.cells.prefix(8).map(\.text).joined().lowercased()
        return !prefix.hasPrefix("http://") && !prefix.hasPrefix("https://")
    }

    private static func isURLCharacter(_ char: Character) -> Bool {
        char.isASCII && (char.isLetter || char.isNumber || "-._~:/?#[]@!$&()*+,;=%".contains(char))
    }
}
