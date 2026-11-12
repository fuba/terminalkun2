// MIT License
import Foundation

public struct KeySequence: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var keys: String

    public init(name: String, keys: String) {
        self.name = name
        self.keys = keys
    }

    public static let maximumCount = 12
    public static let defaults: [Self] = [
        .init(name: "コピー (^A)", keys: "^A ^["),
        .init(name: "コピー (^B)", keys: "^B [")
    ]

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 24 &&
        !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
        Self.encode(keys) != nil
    }

    public static func encode(_ keys: String, applicationCursor: Bool = false) -> String? {
        guard keys.utf8.count <= 256,
              !keys.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let tokens = keys.split(separator: " ")
        guard (1...32).contains(tokens.count) else { return nil }
        var result = ""
        for raw in tokens {
            var token = raw
            var modifiers: Modifiers = []
            if token.hasPrefix("M-") { modifiers.insert(.alt); token = token.dropFirst(2) }
            if token.count == 2, token.hasPrefix("^") {
                token = token.dropFirst()
                guard let byte = token.uppercased().utf8.first, token.utf8.count == 1,
                      (64...95).contains(byte) || byte == 63 else { return nil }
                modifiers.insert(.control)
            }
            if !modifiers.contains(.control), let key = SpecialKey.allCases.first(where: {
                $0.rawValue.lowercased() == token.lowercased() || ($0 == .escape && token.lowercased() == "esc")
            }) {
                result += KeyEncoder.special(key, modifiers: modifiers, applicationCursor: applicationCursor)
            } else if !modifiers.contains(.control), token.lowercased() == "space" {
                result += KeyEncoder.text(" ", modifiers: modifiers)
            } else if token.count == 1 {
                result += KeyEncoder.text(String(token), modifiers: modifiers)
            } else {
                return nil
            }
        }
        return result
    }
}
