// MIT License
import Foundation

public enum FlickDirection: String, CaseIterable, Sendable {
    case center, left, up, right, down
}

public struct FlickGesture: Sendable {
    public let start: CGPoint
    public private(set) var direction: FlickDirection = .center
    public private(set) var cancelled = false
    public init(start: CGPoint) { self.start = start }
    public mutating func move(to point: CGPoint) {
        guard !cancelled else { return }
        let dx = point.x - start.x, dy = point.y - start.y
        let x = abs(dx), y = abs(dy)
        if hypot(dx, dy) > 160 { cancelled = true; return }
        if max(x, y) < 11 { direction = .center; return }
        if direction == .center && max(x, y) < 18 { return }
        // Keep a selected axis near a diagonal, but allow deliberate direction changes.
        let horizontal: Bool
        if direction == .left || direction == .right { horizontal = y < x * 1.2 }
        else if direction == .up || direction == .down { horizontal = x > y * 1.2 }
        else { horizontal = x > y }
        direction = horizontal ? (dx < 0 ? .left : .right) : (dy < 0 ? .up : .down)
    }
}

public struct FlickKey: Sendable {
    public let id: String
    public let choices: [String]
    public init(_ id: String, _ choices: [String]) { self.id = id; self.choices = choices }
    public func text(_ direction: FlickDirection) -> String? {
        guard let index = FlickDirection.allCases.firstIndex(of: direction), choices.indices.contains(index), !choices[index].isEmpty else { return nil }
        return choices[index]
    }
}

public enum JapaneseFlickLayout {
    public static let kana: [FlickKey] = [
        FlickKey("kana-a", ["あ","い","う","え","お"]), FlickKey("kana-ka", ["か","き","く","け","こ"]),
        FlickKey("kana-sa", ["さ","し","す","せ","そ"]), FlickKey("kana-ta", ["た","ち","つ","て","と"]),
        FlickKey("kana-na", ["な","に","ぬ","ね","の"]), FlickKey("kana-ha", ["は","ひ","ふ","へ","ほ"]),
        FlickKey("kana-ma", ["ま","み","む","め","も"]), FlickKey("kana-ya", ["や","（","ゆ","）","よ"]),
        FlickKey("kana-ra", ["ら","り","る","れ","ろ"]), FlickKey("kana-wa", ["わ","を","ん","ー","〜"]),
        FlickKey("kana-punctuation", ["、","。","？","！","…"])
    ]
    public static let numbers: [FlickKey] = [
        FlickKey("number-1", ["1","@","#","$","%"]), FlickKey("number-2", ["2","[","]","{","}"]),
        FlickKey("number-3", ["3","<",">","|","\\"]), FlickKey("number-4", ["4","-","_","/","~"]),
        FlickKey("number-5", ["5",":",";","'","\""]), FlickKey("number-6", ["6","+","=","*","^"]),
        FlickKey("number-7", ["7","(",")","`","&"]), FlickKey("number-8", ["8","?","!","「","」"]),
        FlickKey("number-9", ["9","¥","€","£","¢"]), FlickKey("number-0", ["0","-","+","/","="]),
        FlickKey("number-punctuation", [".",",",":",";","/"])
    ]
}

public enum KanaVariant: Sendable {
    case cycle, voiced, semiVoiced, small, large
    public func apply(to character: Character) -> String? {
        let original = String(character).precomposedStringWithCanonicalMapping
        let katakana = original.unicodeScalars.contains { (0x30A0...0x30FF).contains($0.value) }
        let kana = katakana ? (original.applyingTransform(.hiraganaToKatakana, reverse: true) ?? original) : original
        let cycles = ["あぁ","いぃ","うぅゔ","えぇ","おぉ","かが","きぎ","くぐ","けげ","こご","さざ","しじ","すず","せぜ","そぞ","ただ","ちぢ","つっづ","てで","とど","はばぱ","ひびぴ","ふぶぷ","へべぺ","ほぼぽ","やゃ","ゆゅ","よょ","わゎ"]
        let smalls = ["あぁ","いぃ","うぅ","えぇ","おぉ","つっ","やゃ","ゆゅ","よょ","わゎ","かゕ","けゖ"]
        let voiced = ["うゔ","かが","きぎ","くぐ","けげ","こご","さざ","しじ","すず","せぜ","そぞ","ただ","ちぢ","つづ","てで","とど","はばぱ","ひびぴ","ふぶぷ","へべぺ","ほぼぽ"]
        let groups = self == .cycle ? cycles : (self == .small || self == .large) ? smalls : voiced
        guard let group = groups.first(where: { $0.map(String.init).contains(kana) }) else { return nil }
        let values = group.map(String.init), index = values.firstIndex(of: kana)!
        let result: String
        switch self {
        case .cycle: result = values[(index + 1) % values.count]
        case .voiced: result = values[index == 1 ? 0 : 1]
        case .semiVoiced: guard values.count == 3 else { return nil }; result = values[index == 2 ? 0 : 2]
        case .small: result = values[index == 0 ? 1 : 0]
        case .large: guard index == 1 else { return nil }; result = values[0]
        }
        return katakana ? result.applyingTransform(.hiraganaToKatakana, reverse: false) : result
    }
}
