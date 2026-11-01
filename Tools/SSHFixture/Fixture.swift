#if os(macOS)
import Foundation
import Darwin
import Citadel
import Crypto
import NIO
import NIOSSH

/// Test-only loopback SSH service backed by a real macOS PTY and zsh.
@main struct Fixture {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/ssh-fixture").standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let keyURL = root.appendingPathComponent("host-key")
        let key: Curve25519.Signing.PrivateKey
        if let data = try? Data(contentsOf: keyURL) { key = try .init(rawRepresentation: data) }
        else { key = .init(); try key.rawRepresentation.write(to: keyURL, options: [.atomic]); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path) }
        let port = Int(ProcessInfo.processInfo.environment["TERMINALKUN2_FIXTURE_PORT"] ?? "22292") ?? 22292
        let server = try await SSHServer.host(host: "127.0.0.1", port: port,
            hostKeys: [NIOSSHPrivateKey(ed25519Key: key)], authenticationDelegate: Auth())
        server.enableShell(withDelegate: Shell(root: root))
        server.enableExec(withDelegate: Exec(root: root))
        print("READY loopback port=\(port) root=\(root.path)"); fflush(stdout)
        try await server.closeFuture.get()
    }
}

private final class Auth: NIOSSHServerUserAuthenticationDelegate {
    let supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods = [.password]
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        if case .password(let password) = request.request, request.username == "ios-test", password.password == "test-only-password" { responsePromise.succeed(.success) }
        else { responsePromise.succeed(.failure) }
    }
}

private struct Shell: ShellDelegate {
    let root: URL
    func startShell(inbound: AsyncStream<ShellClientEvent>, outbound: ShellOutboundWriter, context: SSHShellContext) async throws {
        var master: Int32 = -1, slave: Int32 = -1
        var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh"); process.arguments = ["-f", "-i"]
        process.currentDirectoryURL = root
        process.environment = ["HOME": root.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "xterm-256color", "LANG": "ja_JP.UTF-8", "PS1": "fixture$ "]
        process.standardInput = slaveHandle; process.standardOutput = slaveHandle; process.standardError = slaveHandle
        masterHandle.readabilityHandler = { handle in let data = handle.availableData; if !data.isEmpty { outbound.write(Array(data)) } }
        try process.run(); try slaveHandle.close()
        print("PTY pid=\(process.processIdentifier)"); fflush(stdout)
        let resizing = Task {
            for await window in context.windowSize {
                var size = winsize(ws_row: UInt16(clamping: window.rows), ws_col: UInt16(clamping: window.columns), ws_xpixel: 0, ws_ypixel: 0)
                _ = ioctl(master, TIOCSWINSZ, &size)
            }
        }
        defer {
            resizing.cancel(); masterHandle.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            try? masterHandle.close()
        }
        for await event in inbound {
            if case .stdin(let buffer) = event { try masterHandle.write(contentsOf: Data(buffer.readableBytesView)) }
        }
    }
}

private final class Exec: ExecDelegate, @unchecked Sendable {
    let root: URL
    init(root: URL) { self.root = root }
    func setEnvironmentValue(_ value: String, forKey key: String) async throws {}
    func start(command: String, outputHandler: ExecOutputHandler) async throws -> ExecCommandContext {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh"); process.arguments = ["-f", "-c", command]
        process.currentDirectoryURL = root
        process.standardInput = outputHandler.stdinPipe; process.standardOutput = outputHandler.stdoutPipe; process.standardError = outputHandler.stderrPipe
        process.terminationHandler = { outputHandler.succeed(exitCode: Int($0.terminationStatus)) }
        try process.run(); return ProcessContext(process: process)
    }
}
private final class ProcessContext: ExecCommandContext, @unchecked Sendable {
    let process: Process
    init(process: Process) { self.process = process }
    func terminate() async throws { if process.isRunning { process.terminate() } }
    func inputClosed() async throws {}
}
#else
@main struct Fixture { static func main() { fatalError("The SSH test fixture runs on macOS only") } }
#endif
