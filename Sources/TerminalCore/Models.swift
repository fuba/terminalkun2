import Foundation

public enum AppError: LocalizedError, Equatable {
    case message(String)
    public var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

public struct ConnectionProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var user: String
    public var port: Int
    public var favorite: Bool
    public var keyID: UUID?
    public var jumpHost: String?
    public var startupCommand: String
    public var unsupportedOptions: [String]
    public var canConnect: Bool { unsupportedOptions.isEmpty }
    public var address: String { "\(user)@\(host)\(port == 22 ? "" : ":\(port)")" }
    public init(id: UUID = UUID(), name: String, host: String, user: String = "", port: Int = 22, favorite: Bool = false, keyID: UUID? = nil, jumpHost: String? = nil, startupCommand: String = "", unsupportedOptions: [String] = []) {
        self.id = id; self.name = name; self.host = host; self.user = user; self.port = port
        self.favorite = favorite; self.keyID = keyID; self.jumpHost = jumpHost
        self.startupCommand = startupCommand; self.unsupportedOptions = unsupportedOptions
    }
    public func validate() throws {
        guard !host.isEmpty, !user.isEmpty, (1...65535).contains(port), !host.hasPrefix("-"),
              !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              !user.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }), canConnect else {
            throw AppError.message(unsupportedOptions.isEmpty ? "ホスト名・ユーザー名・ポートを確認してください。" : "未対応の SSH 設定: " + unsupportedOptions.joined(separator: ", "))
        }
    }
}

public struct SavedKey: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var publicKey: String
    public var createdAt: Date
    public init(id: UUID = UUID(), name: String, publicKey: String, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.publicKey = publicKey; self.createdAt = createdAt
    }
}

public struct SessionRecord: Codable, Identifiable, Sendable {
    public var id: UUID
    public var profileID: UUID?
    public var title: String
    public var draft: String
    public init(id: UUID = UUID(), profileID: UUID?, title: String, draft: String = "") {
        self.id = id; self.profileID = profileID; self.title = title; self.draft = draft
    }
}

public struct UserWord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var reading: String
    public var word: String
    public init(id: UUID = UUID(), reading: String, word: String) { self.id = id; self.reading = reading; self.word = word }
}

public struct Appearance: Codable, Equatable, Sendable {
    public var theme = "Carbon"
    public var fontSize = 14.0
    public var fontName = ""
    public var opacity = 1.0
    public var scrollback = 10000
    public var customKeyboard = false
    public var autoReconnect = true
    public var keepScreenAwake = false
    public var tmuxMouse = true
    public init() {}
}

public struct AppConfiguration: Codable, Sendable {
    public var version = 1
    public var profiles: [ConnectionProfile] = []
    public var keys: [SavedKey] = []
    public var sessions: [SessionRecord] = []
    public var selectedSession: UUID?
    public var appearance = Appearance()
    public var dictionary: [UserWord] = []
    public var shortcuts = ShortcutBinding.defaults
    public var aiEndpoint = ""
    public var aiModel = ""
    public var sshConfigBookmark: Data?
    public init() {}
}

public enum Shell {
    public static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

public enum ReconnectPolicy {
    public static func delay(attempt: Int) -> Double { min(60, pow(2, Double(min(max(0, attempt), 6)))) }
    public static func shouldRetry(wasConnected: Bool, userClosed: Bool, trustFailure: Bool) -> Bool { wasConnected && !userClosed && !trustFailure }
}

public struct DisconnectedDraft: Sendable {
    public private(set) var text = ""
    private var filter = LogFilter()
    public init() {}
    public mutating func append(_ input: String) {
        let data = filter.consume(Data(input.utf8))
        for char in String(decoding: data, as: UTF8.self) {
            if char == "\n" || char == "\r" || char == "\r\n" { if text.last != " " { text += " " } }
            else if !char.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { text.append(char) }
        }
        while text.utf8.count > 16384 { text.removeFirst() }
    }
    public mutating func take() -> String { defer { text = "" }; return text }
}

public struct ShortcutBinding: Codable, Equatable, Identifiable, Sendable {
    public var action: String
    public var input: String
    public var modifiers: Modifiers
    public var id: String { action }
    public init(_ action: String, _ input: String, _ modifiers: Modifiers = [.command]) {
        self.action = action; self.input = input; self.modifiers = modifiers
    }
    public static let defaults: [ShortcutBinding] = [
        .init("newTab", "t"), .init("closeTab", "w"), .init("connections", "k"),
        .init("settings", ","), .init("search", "f"), .init("nextTab", "]", [.command, .shift]),
        .init("previousTab", "[", [.command, .shift]), .init("paste", "v"), .init("copy", "c"),
        .init("fontLarger", "+"), .init("fontSmaller", "-"), .init("fontReset", "0"),
        .init("logging", "l", [.command, .shift]), .init("upload", "u", [.command, .shift])
    ]
}
