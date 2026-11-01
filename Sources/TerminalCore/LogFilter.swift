import Foundation

public struct LogFilter: Sendable {
    private enum State { case ground, escape, csi, string, stringEscape }
    private var state = State.ground
    public init() {}
    public mutating func consume<T: DataProtocol>(_ input: T) -> Data {
        var output = Data()
        for byte in input {
            switch state {
            case .ground:
                if byte == 0x1b { state = .escape }
                else if byte == 9 || byte == 10 || byte == 13 || byte >= 32 { output.append(byte) }
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
        return output
    }
}

public final class SessionLog {
    public private(set) var url: URL?
    private var handle: FileHandle?
    private var filter = LogFilter()
    private var bytes = 0
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    deinit { try? handle?.close() }
    public func start() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("session-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).txt")
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        handle = try FileHandle(forWritingTo: url); self.url = url; filter = LogFilter(); bytes = 0
        try prune()
    }
    public func stop() { try? handle?.close(); handle = nil }
    public func append(_ data: Data) throws {
        guard let handle else { return }
        let cleaned = filter.consume(data)
        if bytes + cleaned.count > 4 * 1024 * 1024 { stop(); try start(); try append(data); return }
        try handle.write(contentsOf: cleaned); bytes += cleaned.count
    }
    private func prune() throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("session-") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for url in files.dropFirst(20) { try FileManager.default.removeItem(at: url) }
    }
}
