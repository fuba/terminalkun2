import Foundation

public struct LogFilter: Sendable {
    private enum State { case ground, escape, csi, string, stringEscape }
    private var state = State.ground
    private var pendingC2 = false
    private var continuations = 0
    public init() {}
    public mutating func consume<T: DataProtocol>(_ input: T) -> Data {
        var output = Data()
        for byte in input {
            if pendingC2 {
                pendingC2 = false
                if (0x80...0x9f).contains(byte) { process(byte, c1: true, output: &output); continuations = 0; continue }
                process(0xc2, c1: false, output: &output)
                if (0xa0...0xbf).contains(byte) { process(byte, c1: false, output: &output); continuations = 0; continue }
            }
            if continuations > 0 && (0x80...0xbf).contains(byte) { continuations -= 1; process(byte, c1: false, output: &output); continue }
            continuations = 0
            if byte == 0xc2 { pendingC2 = true; continue }
            if (0xc3...0xdf).contains(byte) { continuations = 1 }
            else if (0xe0...0xef).contains(byte) { continuations = 2 }
            else if (0xf0...0xf4).contains(byte) { continuations = 3 }
            process(byte, c1: (0x80...0x9f).contains(byte), output: &output)
        }
        return output
    }
    private mutating func process(_ byte: UInt8, c1: Bool, output: inout Data) {
        if c1 {
            if state == .string || state == .stringEscape { if byte == 0x9c { state = .ground }; return }
            switch byte {
            case 0x9b: state = .csi
            case 0x90, 0x98, 0x9d, 0x9e, 0x9f: state = .string
            case 0x9c: state = .ground
            default: break
            }
            return
        }
        switch state {
            case .ground:
                if byte == 0x1b { state = .escape }
                else if byte == 9 || byte == 10 || byte == 13 || (byte >= 32 && byte != 127) { output.append(byte) }
            case .escape:
                if byte == 0x5b { state = .csi }
                else if [0x5d, 0x50, 0x5f, 0x5e, 0x58].contains(byte) { state = .string }
                else if byte >= 0x30 { state = .ground }
            case .csi:
                if byte >= 0x40 && byte <= 0x7e { state = .ground }
            case .string:
                if byte == 7 { state = .ground }
                else if byte == 0x1b { state = .stringEscape }
            case .stringEscape:
                state = byte == 0x5c ? .ground : .string
        }
    }
}

public final class SessionLog {
    public private(set) var url: URL?
    private var handle: FileHandle?
    private var filter = LogFilter()
    private var bytes = 0
    private let directory: URL
    private let byteLimit: Int
    private var pendingUTF8 = Data()
    public init(directory: URL, byteLimit: Int = 4 * 1024 * 1024) { self.directory = directory; self.byteLimit = max(16, byteLimit) }
    deinit { try? handle?.close() }
    public func start() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("session-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).txt")
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        handle = try FileHandle(forWritingTo: url); self.url = url; filter = LogFilter(); bytes = 0; pendingUTF8 = Data()
        try prune()
    }
    public func stop() { try? handle?.close(); handle = nil }
    public func append(_ data: Data) throws {
        guard handle != nil else { return }
        pendingUTF8.append(filter.consume(data))
        var safeEnd = pendingUTF8.count
        if !pendingUTF8.isEmpty {
            var lead = pendingUTF8.count - 1
            while lead > 0 && pendingUTF8[lead] & 0xc0 == 0x80 { lead -= 1 }
            let byte = pendingUTF8[lead]
            let width = byte & 0xf8 == 0xf0 ? 4 : byte & 0xf0 == 0xe0 ? 3 : byte & 0xe0 == 0xc0 ? 2 : 1
            if pendingUTF8.count - lead < width { safeEnd = lead }
        }
        let cleaned = Data(pendingUTF8.prefix(safeEnd)); pendingUTF8 = Data(pendingUTF8.dropFirst(safeEnd))
        var offset = 0
        while offset < cleaned.count {
            var count = min(byteLimit - bytes, cleaned.count - offset)
            while count > 0 && offset + count < cleaned.count && cleaned[offset + count] & 0xc0 == 0x80 { count -= 1 }
            if count == 0 {
                let streamState = filter, tail = pendingUTF8
                stop(); try start(); filter = streamState; pendingUTF8 = tail; continue
            }
            try handle?.write(contentsOf: cleaned.subdata(in: offset..<(offset + count)))
            bytes += count; offset += count
        }
    }
    private func prune() throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("session-") }.sorted {
                if $0 == url { return true }; if $1 == url { return false }
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a == b ? $0.lastPathComponent > $1.lastPathComponent : a > b
            }
        for url in files.dropFirst(20) { try FileManager.default.removeItem(at: url) }
    }
}
