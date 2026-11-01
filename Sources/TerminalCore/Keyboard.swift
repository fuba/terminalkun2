import Foundation

public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = Self(rawValue: 1)
    public static let alt = Self(rawValue: 2)
    public static let control = Self(rawValue: 4)
    public static let command = Self(rawValue: 8)
}

public struct ModifierState: Sendable {
    public private(set) var active: Modifiers = []
    public private(set) var locked: Modifiers = []
    private var lastTap: [Int: TimeInterval] = [:]
    public init() {}
    public mutating func tap(_ modifier: Modifiers, at time: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        if locked.contains(modifier) { locked.remove(modifier); active.remove(modifier) }
        else if active.contains(modifier), time - (lastTap[modifier.rawValue] ?? 0) < 0.35 {
            locked.insert(modifier)
        } else if active.contains(modifier) { active.remove(modifier) }
        else { active.insert(modifier) }
        lastTap[modifier.rawValue] = time
    }
    public mutating func consume() { active = locked }
    public mutating func reset() { active = []; locked = []; lastTap = [:] }
}

public enum SpecialKey: String, CaseIterable, Sendable {
    case escape, tab, enter, backspace, up, down, left, right, home, end, pageUp, pageDown, delete
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
}

public enum KeyEncoder {
    private static let shifted = Dictionary(uniqueKeysWithValues: zip(Array("`1234567890-=[]\\;',./"), Array("~!@#$%^&*()_+{}|:\"<>?")))
    public static func text(_ value: String, modifiers: Modifiers) -> String {
        var text = value
        if modifiers.contains(.shift) { text = value.map { shifted[$0].map(String.init) ?? String($0).uppercased() }.joined() }
        if modifiers.contains(.control), text.utf8.count == 1, let byte = text.uppercased().utf8.first {
            if byte >= 64 && byte <= 95 { text = String(UnicodeScalar(byte & 31)) }
            else if byte == 32 { text = "\0" }
            else if byte == 63 { text = "\u{7f}" }
        }
        if modifiers.contains(.alt) { text = "\u{1b}" + text }
        return text
    }
    public static func special(_ key: SpecialKey, modifiers: Modifiers = [], applicationCursor: Bool = false) -> String {
        let m = 1 + (modifiers.contains(.shift) ? 1 : 0) + (modifiers.contains(.alt) ? 2 : 0) + (modifiers.contains(.control) ? 4 : 0)
        let esc = "\u{1b}"
        switch key {
        case .escape: return esc
        case .enter: return modifiers.contains(.alt) ? esc + "\r" : "\r"
        case .backspace: return modifiers.contains(.alt) ? esc + "\u{7f}" : "\u{7f}"
        case .tab: return modifiers.contains(.shift) ? esc + "[Z" : "\t"
        case .up, .down, .left, .right, .home, .end:
            let suffix: String = [.up: "A", .down: "B", .right: "C", .left: "D", .home: "H", .end: "F"][key]!
            return m == 1 ? esc + (applicationCursor ? "O" : "[") + suffix : esc + "[1;\(m)" + suffix
        case .f1, .f2, .f3, .f4:
            let suffix: String = [.f1: "P", .f2: "Q", .f3: "R", .f4: "S"][key]!
            return m == 1 ? esc + "O" + suffix : esc + "[1;\(m)" + suffix
        default:
            let code: Int = [.delete: 3, .pageUp: 5, .pageDown: 6, .f5: 15, .f6: 17, .f7: 18, .f8: 19, .f9: 20, .f10: 21, .f11: 23, .f12: 24][key]!
            return esc + "[\(code)" + (m == 1 ? "~" : ";\(m)~")
        }
    }
}
