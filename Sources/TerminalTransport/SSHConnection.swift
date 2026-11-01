import Foundation
import Citadel
import NIO
import NIOSSH
import Crypto
import TerminalCore

public enum SSHFailure: LocalizedError {
    case hostKeyRejected, disconnected
    public var errorDescription: String? {
        switch self { case .hostKeyRejected: return "ホスト鍵を確認できなかったため接続を中止しました。"; case .disconnected: return "SSH 接続が切断されました。" }
    }
}

private final class HostValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let check: @Sendable (String) async throws -> Void
    init(check: @escaping @Sendable (String) async throws -> Void) { self.check = check }
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let text = String(openSSHPublicKey: hostKey)
        validationCompletePromise.completeWithTask { try await self.check(text) }
    }
}

public struct SSHCredentials: Sendable {
    public var password: String
    public var privateKey: String?
    public var passphrase: String
    public init(password: String = "", privateKey: String? = nil, passphrase: String = "") {
        self.password = password; self.privateKey = privateKey; self.passphrase = passphrase
    }
}

/// Owns one authenticated connection. UI events share one ordered SSH write queue.
@MainActor
public final class SSHConnection {
    public typealias VerifyHost = @Sendable (_ profile: ConnectionProfile, _ publicKey: String) async throws -> Void
    private enum WriteEvent { case data(Data), resize(Int, Int) }
    private var continuation: AsyncStream<WriteEvent>.Continuation?
    private var client: SSHClient?
    private var parents: [SSHClient] = []
    private var writerTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var heartbeatProbe: Task<Void, Never>?
    private var generation = UUID()
    public var connected: Bool { client?.isConnected == true }
    public init() {}

    public func run(profile: ConnectionProfile, credentials: SSHCredentials,
                    jumps: [(ConnectionProfile, SSHCredentials)] = [], cols: Int, rows: Int,
                    verify: @escaping VerifyHost,
                    onReady: @escaping @MainActor () -> Void,
                    onData: @escaping @MainActor (Data) -> Void) async throws {
        try profile.validate()
        let token = UUID(); generation = token
        func settings(_ profile: ConnectionProfile, _ credentials: SSHCredentials) throws -> SSHClientSettings {
            try profile.validate()
            let method: () -> SSHAuthenticationMethod
            if let pem = credentials.privateKey {
                // Parsing validates the passphrase before any remote authentication attempt.
                let authentication = try KeyMaterial.authentication(pem: pem, passphrase: credentials.passphrase, user: profile.user)
                method = { authentication }
            } else { method = { .passwordBased(username: profile.user, password: credentials.password) } }
            var value = SSHClientSettings(host: profile.host, port: profile.port,
                authenticationMethod: { method() },
                hostKeyValidator: .custom(HostValidator { key in try await verify(profile, key) }))
            value.connectTimeout = .seconds(20)
            return value
        }
        var active: SSHClient?
        do {
            for (jump, auth) in jumps {
                let next: SSHClient
                if let active { next = try await active.jump(to: settings(jump, auth)) }
                else { next = try await SSHClient.connect(to: settings(jump, auth)) }
                parents.append(next); active = next
            }
            let settings = try settings(profile, credentials)
            let connection: SSHClient
            if let active { connection = try await active.jump(to: settings) }
            else { connection = try await SSHClient.connect(to: settings) }
            guard token == generation, !Task.isCancelled else { try? await connection.close(); throw CancellationError() }
            client = connection
            defer { writerTask?.cancel(); heartbeatTask?.cancel(); heartbeatProbe?.cancel(); continuation?.finish(); continuation = nil }
            let request = SSHChannelRequestEvent.PseudoTerminalRequest(wantReply: true, term: "xterm-256color",
                terminalCharacterWidth: max(1, cols), terminalRowHeight: max(1, rows),
                terminalPixelWidth: 0, terminalPixelHeight: 0, terminalModes: .init([.ECHO: 1, .ICANON: 1, .ISIG: 1]))
            var outputEndedNormally = false
            do { try await connection.withPTY(request) { output, writer in
                let (stream, continuation) = AsyncStream<WriteEvent>.makeStream()
                self.continuation = continuation
                self.writerTask = Task { @MainActor in
                    do {
                        for await event in stream {
                            try Task.checkCancellation()
                            switch event {
                            case .data(let data): try await writer.write(ByteBuffer(bytes: data))
                            case .resize(let cols, let rows): try await writer.changeSize(cols: max(1, cols), rows: max(1, rows), pixelWidth: 0, pixelHeight: 0)
                            }
                        }
                    } catch { try? await connection.close() }
                }
                self.heartbeatTask = Task { @MainActor in
                    var missedReplies = 0
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(15)); try Task.checkCancellation() }
                        catch { return }
                        if self.heartbeatProbe != nil { missedReplies += 1 }
                        if missedReplies >= 3 || !connection.isConnected { try? await connection.close(); return }
                        if self.heartbeatProbe == nil {
                            self.heartbeatProbe = Task { @MainActor in
                                defer { self.heartbeatProbe = nil }
                                do { _ = try await connection.executeCommand("true", maxResponseSize: 1024); missedReplies = 0 }
                                catch { missedReplies += 1 }
                            }
                        }
                    }
                }
                onReady()
                for try await chunk in output {
                    try Task.checkCancellation()
                    guard self.generation == token else { break }
                    switch chunk {
                    case .stdout(let buffer), .stderr(let buffer): onData(Data(buffer.readableBytesView))
                    }
                }
                outputEndedNormally = true
            } } catch {
                // Citadel closes the PTY again after receiving the server's EOF.
                guard outputEndedNormally, case ChannelError.alreadyClosed = error else { throw error }
            }
            try? await connection.close()
            for parent in parents.reversed() { try? await parent.close() }
            parents = []; client = nil
        } catch {
            if generation == token { await close() }
            throw error
        }
    }
    public func send(_ data: Data) { continuation?.yield(.data(data)) }
    public func resize(cols: Int, rows: Int) { continuation?.yield(.resize(cols, rows)) }
    public func close() async {
        generation = UUID(); continuation?.finish(); continuation = nil
        writerTask?.cancel(); heartbeatTask?.cancel(); heartbeatProbe?.cancel(); heartbeatProbe = nil
        let connection = client; client = nil
        try? await connection?.close()
        for parent in parents.reversed() { try? await parent.close() }; parents = []
    }
    public func execute(_ command: String) async throws -> String {
        guard let client, client.isConnected else { throw SSHFailure.disconnected }
        return String(decoding: try await client.executeCommand(command, maxResponseSize: 1024 * 1024).readableBytesView, as: UTF8.self)
    }
    public func upload(_ urls: [URL], progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws -> [String] {
        guard let client, client.isConnected else { throw SSHFailure.disconnected }
        let sftp = try await client.openSFTP()
        let directory = "/tmp/terminalkun2." + UUID().uuidString.lowercased()
        do {
            try await sftp.createDirectory(atPath: directory, attributes: Self.attributes(0o700))
            var paths: [String] = []
            for (index, url) in urls.enumerated() {
                guard !url.lastPathComponent.isEmpty, !url.lastPathComponent.contains(where: { $0 == "\n" || $0 == "\r" }) else { throw AppError.message("ファイル名に改行は使用できません。") }
                let destination = directory + "/" + url.lastPathComponent
                try await uploadItem(url, path: destination, sftp: sftp)
                paths.append(destination); progress(Double(index + 1) / Double(urls.count))
            }
            try await sftp.close(); return paths
        } catch { try? await sftp.close(); throw error }
    }
    private func uploadItem(_ url: URL, path: String, sftp: SFTPClient) async throws {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw AppError.message("シンボリックリンクは送信しません。") }
        if values.isDirectory == true {
            try await sftp.createDirectory(atPath: path, attributes: Self.attributes(0o700))
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                try await uploadItem(child, path: path + "/" + child.lastPathComponent, sftp: sftp)
            }
        } else {
            let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
            let remote = try await sftp.openFile(filePath: path, flags: [.write, .create, .truncate, .forceCreate], attributes: Self.attributes(0o600))
            do {
                var offset: UInt64 = 0
                while let data = try input.read(upToCount: 32768), !data.isEmpty {
                    try Task.checkCancellation(); try await remote.write(ByteBuffer(bytes: data), at: offset); offset += UInt64(data.count)
                }
                try await remote.close()
            } catch { try? await remote.close(); throw error }
        }
    }
    private static func attributes(_ permissions: UInt32) -> SFTPFileAttributes {
        var value = SFTPFileAttributes(); value.permissions = permissions; return value
    }
}
