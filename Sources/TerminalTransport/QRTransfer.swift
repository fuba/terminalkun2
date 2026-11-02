// MIT License
import Foundation
import Crypto
import CommonCrypto
import Security
import TerminalCore

public struct QRKeyPayload: Sendable {
    public let name: String
    public let format: String
    public let key: Data

    public init(name: String, format: String, key: Data) throws {
        guard (1...128).contains(name.utf8.count), !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              ["openssh", "pem"].contains(format), (1...16384).contains(key.count) else { throw QRTransfer.failure }
        self.name = name; self.format = format; self.key = key
    }

    static func decode(_ data: Data) throws -> Self {
        // Parse the small, string-only object without accepting duplicate JSON keys.
        let bytes = Array(data); var index = 0; var fields: [String: String] = [:]
        func space() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        func consume(_ byte: UInt8) throws {
            space(); guard index < bytes.count, bytes[index] == byte else { throw QRTransfer.failure }; index += 1
        }
        func string() throws -> String {
            space(); let start = index
            guard index < bytes.count, bytes[index] == 34 else { throw QRTransfer.failure }; index += 1
            var escaped = false
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
            }
            throw QRTransfer.failure
        }
        try consume(123)
        while true {
            let key = try string(); try consume(58); let value = try string()
            guard fields[key] == nil else { throw QRTransfer.failure }; fields[key] = value
            space(); guard index < bytes.count else { throw QRTransfer.failure }
            if bytes[index] == 125 { index += 1; break }
            try consume(44)
        }
        space()
        guard index == bytes.count, Set(fields.keys) == Set(["kind", "name", "format", "key"]), fields["kind"] == "ssh-private-key",
              let name = fields["name"], let format = fields["format"], let key = fields["key"] else { throw QRTransfer.failure }
        return try Self(name: name, format: format, key: QRTransfer.decodeBase64URL(key))
    }
}

public struct QRTransfer: Sendable {
    static var failure: AppError { .message("QR の形式・内容を確認してください。TKQR1 の暗号化された秘密鍵に対応しています。") }
    public let expiresAt: Date
    public let id: Data
    let data: Data

    init(_ data: Data, now: Date = Date()) throws {
        guard (86...24661).contains(data.count), data.prefix(5) == Data([84,75,81,82,1]) else { throw Self.failure }
        let length = Self.integer(data[65..<69])
        guard (1...24576).contains(length), data.count == 85 + Int(length) else { throw Self.failure }
        let created = Self.integer(data[21..<29]), expires = Self.integer(data[29..<37])
        guard created <= UInt64.max - 300, expires == created + 300 else { throw Self.failure }
        self.data = data; id = data.subdata(in: 5..<21); expiresAt = Date(timeIntervalSince1970: Double(expires))
        try validateTime(now)
    }

    public func validateTime(_ now: Date = Date()) throws {
        let created = Double(Self.integer(data[21..<29]))
        guard created <= now.timeIntervalSince1970 + 60, now <= expiresAt.addingTimeInterval(60) else {
            throw AppError.message("QR の有効期限が切れているか、端末の時刻が合っていません。送信側で再生成してください。")
        }
    }

    public func open(passphrase: String, now: Date = Date()) throws -> QRKeyPayload {
        try validateTime(now)
        let key = try Self.derive(passphrase, salt: data.subdata(in: 37..<53))
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: data[53..<65]), ciphertext: data[69..<(data.count-16)], tag: data.suffix(16))
        var plaintext: Data
        do { plaintext = try AES.GCM.open(box, using: key, authenticating: data.prefix(69)) }
        catch { throw AppError.message("転送用パスフレーズが違うか、QR が破損しています。") }
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        try validateTime(now)
        return try QRKeyPayload.decode(plaintext)
    }

    // Used by interoperability tests and fixture tooling, never as a private-key sharing UI.
    static func seal(_ payload: QRKeyPayload, passphrase: String, now: Date) throws -> [String] {
        let plaintext = try JSONSerialization.data(withJSONObject: ["kind":"ssh-private-key", "name":payload.name, "format":payload.format, "key":base64URL(payload.key)], options: [.sortedKeys, .withoutEscapingSlashes])
        guard plaintext.count <= 24576 else { throw failure }
        let id = try random(16), salt = try random(16), nonce = try random(12)
        var header = Data([84,75,81,82,1]); header.append(id)
        for value in [UInt64(now.timeIntervalSince1970), UInt64(now.timeIntervalSince1970) + 300] { var be = value.bigEndian; withUnsafeBytes(of: &be) { header.append(contentsOf: $0) } }
        header.append(salt); header.append(nonce)
        var length = UInt32(plaintext.count).bigEndian; withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }
        let box = try AES.GCM.seal(plaintext, using: derive(passphrase, salt: salt), nonce: AES.GCM.Nonce(data: nonce), authenticating: header)
        let packet = header + box.ciphertext + box.tag
        let encoded = Array(base64URL(packet).utf8), count = (encoded.count + 639) / 640
        let hash = SHA256.hash(data: packet).map { String(format: "%02x", $0) }.joined()
        return (0..<count).map { index in
            "TKQR1/\(base64URL(id))/\(index+1)/\(count)/\(hash)/" + String(decoding: encoded[(index*640)..<min(encoded.count, (index+1)*640)], as: UTF8.self)
        }
    }

    static func derive(_ phrase: String, salt: Data) throws -> SymmetricKey {
        let bytes = Array(phrase.utf8)
        guard bytes.count == 24, bytes.allSatisfy(isBase64URL) else { throw AppError.message("送信側に表示された 24 文字の転送用パスフレーズを入力してください。") }
        var output = Data(count: 32)
        let status = output.withUnsafeMutableBytes { out in salt.withUnsafeBytes { salt in bytes.withUnsafeBytes { password in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.baseAddress!.assumingMemoryBound(to: Int8.self), password.count,
                salt.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600000,
                out.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
        } } }
        defer { output.resetBytes(in: 0..<output.count) }
        guard status == kCCSuccess else { throw Self.failure }; return SymmetricKey(data: output)
    }
    static func integer(_ bytes: Data.SubSequence) -> UInt64 { bytes.reduce(0) { ($0 << 8) | UInt64($1) } }
    static func isBase64URL(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95 }
    static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func decodeBase64URL(_ string: String) throws -> Data {
        guard !string.isEmpty, string.utf8.allSatisfy(isBase64URL), string.count % 4 != 1 else { throw failure }
        let padded = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - string.count % 4) % 4)
        guard let result = Data(base64Encoded: padded), base64URL(result) == string else { throw failure }; return result
    }
    static func random(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard result == errSecSuccess else { throw failure }; return data
    }
}

public struct QRTransferCollector: Sendable {
    struct Frame {
        let id: String, hash: String, chunk: String
        let index: Int, count: Int
        init(_ text: String) throws {
            guard text.utf8.count <= 768 else { throw QRTransfer.failure }
            let parts = text.components(separatedBy: "/")
            guard parts.count == 6, parts[0] == "TKQR1", parts[1].count == 22, try QRTransfer.decodeBase64URL(parts[1]).count == 16,
                  let index = Int(parts[2]), let count = Int(parts[3]), String(index) == parts[2], String(count) == parts[3],
                  (1...64).contains(count), (1...count).contains(index), parts[4].utf8.count == 64,
                  parts[4].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  (1...640).contains(parts[5].utf8.count), parts[5].utf8.allSatisfy(QRTransfer.isBase64URL),
                  index == count || parts[5].count == 640 else { throw QRTransfer.failure }
            self.id = parts[1]; self.index = index; self.count = count; hash = parts[4]; chunk = parts[5]
        }
    }
    public private(set) var received = 0
    public private(set) var total = 0
    private var first: Frame?
    private var started: TimeInterval?
    private var chunks: [Int: String] = [:]
    public init() {}
    public mutating func append(_ text: String, now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) throws -> QRTransfer? {
        let frame = try Frame(text)
        if let started, uptime < started || uptime - started > 300 { throw AppError.message("読み取りがタイムアウトしました。最初から読み直してください。") }
        if let first {
            guard first.id == frame.id, first.hash == frame.hash, first.count == frame.count else { throw AppError.message("別の転送の QR です。読み取りをやり直してください。") }
        } else { first = frame; started = uptime; total = frame.count }
        if let previous = chunks[frame.index], previous != frame.chunk { throw QRTransfer.failure }
        chunks[frame.index] = frame.chunk
        guard chunks.values.reduce(0, { $0 + $1.count }) <= 32882 else { throw QRTransfer.failure }
        received = chunks.count
        guard received == total else { return nil }
        let encoded = (1...total).compactMap { chunks[$0] }.joined()
        let data = try QRTransfer.decodeBase64URL(encoded)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == frame.hash else { throw QRTransfer.failure }
        let packet = try QRTransfer(data, now: now)
        guard QRTransfer.base64URL(packet.id) == frame.id else { throw QRTransfer.failure }
        return packet
    }
}
