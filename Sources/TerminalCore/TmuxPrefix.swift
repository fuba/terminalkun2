import Foundation

public enum TmuxPrefix {
    public static func parse(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 32 else { return nil }
        if value.hasPrefix("M-") { return parse(String(value.dropFirst(2))).map { "\u{1b}" + $0 } }
        if value.hasPrefix("C-"), value.count == 3 {
            let key = String(value.suffix(1))
            guard let byte = key.uppercased().utf8.first, (64...95).contains(byte) || byte == 63 || byte == 32 else { return nil }
            return KeyEncoder.text(key, modifiers: [.control])
        }
        if let key: String = ["Space": " ", "Escape": "\u{1b}", "Tab": "\t", "Enter": "\r", "BSpace": "\u{7f}"][value] { return key }
        if value.utf8.count == 1, let byte = value.utf8.first, byte >= 32, byte < 127 { return value }
        return nil
    }
}
