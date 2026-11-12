#if os(macOS)
import XCTest
import Foundation
import Darwin
import TerminalCore
@testable import TerminalTransport

final class SSHIntegrationTests: XCTestCase {
    @MainActor
    func testRealOpenSSHTrustEncryptedKeyJapaneseResizeAndSFTP() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tk2-ssh-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        try run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", folder.appendingPathComponent("host").path])
        try run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "integration-passphrase", "-f", folder.appendingPathComponent("client").path])
        try FileManager.default.copyItem(at: folder.appendingPathComponent("client.pub"), to: folder.appendingPathComponent("authorized_keys"))
        let port = try Self.unusedPort()
        let hostPublic = try String(contentsOf: folder.appendingPathComponent("host.pub"), encoding: .utf8).split(separator: " ").prefix(2).joined(separator: " ")
        let configuration = """
        Port \(port)
        ListenAddress 127.0.0.1
        HostKey \(folder.path)/host
        PidFile \(folder.path)/pid
        AuthorizedKeysFile \(folder.path)/authorized_keys
        StrictModes no
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        UsePAM no
        AllowUsers \(NSUserName())
        Subsystem sftp internal-sftp
        LogLevel VERBOSE
        """
        let config = folder.appendingPathComponent("sshd_config")
        try configuration.write(to: config, atomically: true, encoding: .utf8)
        let logURL = folder.appendingPathComponent("sshd.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL); defer { try? log.close() }
        let server = Process(); server.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
        server.arguments = ["-D", "-e", "-f", config.path]; server.standardOutput = log; server.standardError = log
        try server.run(); defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let deadline = Date().addingTimeInterval(5)
        var ready = false
        while Date() < deadline && server.isRunning {
            let probe = Process(); probe.executableURL = URL(fileURLWithPath: "/usr/bin/nc"); probe.arguments = ["-z", "127.0.0.1", String(port)]
            probe.standardError = FileHandle.nullDevice; probe.standardOutput = FileHandle.nullDevice
            try probe.run(); probe.waitUntilExit()
            if probe.terminationStatus == 0 { ready = true; break }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertTrue(ready, (try? String(contentsOf: logURL, encoding: .utf8)) ?? "sshd did not start")
        guard ready else { return }
        var profile = ConnectionProfile(name: "loopback", host: "127.0.0.1", user: NSUserName(), port: port)
        profile.agentForwarding = true
        let pem = try qrRoundtrip(String(contentsOf: folder.appendingPathComponent("client"), encoding: .utf8))
        let credentials = SSHCredentials(privateKey: pem, passphrase: "integration-passphrase")
        let rejected = SSHConnection()
        do {
            try await rejected.run(profile: profile, credentials: credentials, cols: 80, rows: 24,
                verify: { _, _ in throw SSHFailure.hostKeyRejected }, onReady: { XCTFail("Untrusted host must not authenticate") }, onData: { _ in XCTFail("Untrusted host must not receive output") })
            XCTFail("Untrusted host was accepted")
        } catch { /* Expected: the host validator rejects the real SSH handshake. */ }

        let shell = folder.appendingPathComponent("fixture-shell")
        try """
        unset ENV BASH_ENV
        stty -echo
        printf 'TEST-SHELL-READY\\n'
        exec /bin/sh -s +o emacs +o vi
        """.write(to: shell, atomically: true, encoding: .utf8)
        let connection = SSHConnection(), authenticated = expectation(description: "real PTY ready"), outputReady = expectation(description: "ordered Japanese output")
        let shellReady = expectation(description: "fixture shell started without user line editors")
        let forwarded = expectation(description: "real OpenSSH uses the forwarded agent")
        let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first(where: FileManager.default.isExecutableFile(atPath:))
        var detached: XCTestExpectation?
        var didDetach = false, didStartShell = false
        var received = Data(), completed = false, agentCompleted = false
        let task = Task { @MainActor in
            try await connection.run(profile: profile, credentials: credentials, cols: 80, rows: 24,
                verify: { _, key in XCTAssertEqual(key, hostPublic) },
                onReady: { authenticated.fulfill() }, onData: { data in
                    received.append(data)
                    if !didStartShell && String(decoding: received, as: UTF8.self).contains("TEST-SHELL-READY") {
                        didStartShell = true; shellReady.fulfill()
                    }
                    if !didDetach && String(decoding: received, as: UTF8.self).contains("TMUX-DETACHED-OK") { didDetach = true; detached?.fulfill() }
                    if !completed && String(decoding: received, as: UTF8.self).contains("DONE-20-日本語") { completed = true; outputReady.fulfill() }
                    if !agentCompleted {
                        let text = String(decoding: received, as: UTF8.self)
                        if text.contains("FORWARDED-AGENT-OK"), text.contains("SSH-SHELL-READY") {
                            agentCompleted = true; forwarded.fulfill()
                        }
                    }
                })
        }
        let expiry = Task { @MainActor in try? await Task.sleep(for: .seconds(30)); if !Task.isCancelled { await connection.close() } }
        defer { expiry.cancel() }
        defer { task.cancel(); Task { await connection.close() } }
        await fulfillment(of: [authenticated], timeout: 20)
        guard connection.connected else { XCTFail("SSH did not connect"); return }
        try await connection.probeLiveness(timeout: .seconds(5))
        connection.send(Data(("exec /bin/sh " + shell.path + "\r").utf8))
        await fulfillment(of: [shellReady], timeout: 5)
        for cycle in 1...20 {
            connection.resize(cols: 60 + cycle, rows: 20 + cycle)
            connection.send(Data("printf 'DONE-\(cycle)-日本語\\n'\r".utf8))
        }
        await fulfillment(of: [outputReady], timeout: 15)
        let output = try XCTUnwrap(String(data: received, encoding: .utf8))
        for cycle in 1...20 { XCTAssertTrue(output.contains("DONE-\(cycle)-日本語"), "Missing Japanese commit \(cycle)") }
        let file = folder.appendingPathComponent("日本語 ' $(touch should-not-exist).txt")
        let payload = "SFTP bytes: 日本語\n"
        try payload.write(to: file, atomically: true, encoding: .utf8)
        let paths = try await connection.upload([file])
        let uploaded = try XCTUnwrap(paths.first)
        let content = try await connection.execute("cat -- " + Shell.quote(uploaded))
        XCTAssertEqual(content, payload)
        let dimensions = try await connection.execute("printf verified")
        XCTAssertEqual(dimensions, "verified")
        _ = try await connection.execute("rm -f -- " + Shell.quote(uploaded))
        _ = try await connection.execute("rmdir -- " + Shell.quote(URL(fileURLWithPath: uploaded).deletingLastPathComponent().path))
        let known = folder.appendingPathComponent("known_hosts")
        try "[127.0.0.1]:\(port) \(hostPublic)\n".write(to: known, atomically: true, encoding: .utf8)
        let nested = "ssh -n -o UserKnownHostsFile=" + Shell.quote(known.path) + " -o StrictHostKeyChecking=yes -o IdentityFile=/dev/null -o PreferredAuthentications=publickey -p \(port) " + Shell.quote(NSUserName() + "@127.0.0.1") + " 'printf FORWARDED-AGENT-OK'; printf '\\nSSH-SHELL-READY\\n'\r"
        connection.send(Data(nested.utf8))
        await fulfillment(of: [forwarded], timeout: 15)
        FileHandle.standardError.write(Data("SSH_TEST_STAGE=agent-authenticated\n".utf8))
        if let tmux {
            let command = Shell.quote(tmux) + " -S " + Shell.quote(folder.appendingPathComponent("tmux").path)
            _ = try await connection.execute(command + " -f /dev/null new-session -d -s tk2 /bin/sh \\; set-option -g prefix C-a \\; bind-key Escape copy-mode")
            defer { try? run(tmux, ["-S", folder.appendingPathComponent("tmux").path, "kill-server"]) }
            connection.send(Data((command + " attach-session -t tk2; printf 'TMUX-DETACHED-OK\\n'\r").utf8))
            let clientCount = try await waitForTmux(connection, command: command + " display-message -p -t tk2 '#{session_attached}'", expected: "1")
            guard clientCount == "1" else {
                XCTFail("tmux did not attach. Output: " + String(decoding: received.suffix(768), as: UTF8.self))
                return
            }
            connection.send(Data(try XCTUnwrap(KeySequence.encode("^A ^[")).utf8))
            let mode = try await waitForTmux(connection, command: command + " display-message -p -t tk2 '#{pane_in_mode}'", expected: "1")
            XCTAssertEqual(mode, "1")
            let detachReady = expectation(description: "tmux detached back to the remote shell")
            detached = detachReady
            _ = try await connection.execute(command + " detach-client -s tk2")
            await fulfillment(of: [detachReady], timeout: 4)
        }
        connection.send(Data("exit\r".utf8))
        try await task.value
        FileHandle.standardError.write(Data("SSH_TEST_STAGE=first-connection-finished\n".utf8))

        // OpenSSH rejects legacy RSA/SHA-1 by default; this must use RSA/SHA-256.
        try run("/usr/bin/ssh-keygen", ["-q", "-t", "rsa", "-b", "3072", "-N", "rsa-passphrase", "-f", folder.appendingPathComponent("rsa").path])
        let rsaPublic = try Data(contentsOf: folder.appendingPathComponent("rsa.pub"))
        let authorized = try FileHandle(forWritingTo: folder.appendingPathComponent("authorized_keys"))
        _ = try authorized.seekToEnd(); try authorized.write(contentsOf: rsaPublic); try authorized.close()
        let rsaPEM = try qrRoundtrip(String(contentsOf: folder.appendingPathComponent("rsa"), encoding: .utf8))
        let rsaConnection = SSHConnection()
        var rsaAuthenticated = false
        try await rsaConnection.run(profile: profile, credentials: SSHCredentials(privateKey: rsaPEM, passphrase: "rsa-passphrase"), cols: 80, rows: 24,
            verify: { _, key in XCTAssertEqual(key, hostPublic) },
            onReady: { rsaAuthenticated = true; rsaConnection.send(Data("exit 7\r".utf8)) }, onData: { _ in })
        XCTAssertTrue(rsaAuthenticated)

        let jump = ConnectionProfile(name: "jump", host: "127.0.0.1", user: NSUserName(), port: port)
        let throughJump = SSHConnection()
        var jumpAuthenticated = false
        try await throughJump.run(profile: profile, credentials: credentials, jumps: [(jump, credentials)], cols: 80, rows: 24,
            verify: { _, key in XCTAssertEqual(key, hostPublic) },
            onReady: { jumpAuthenticated = true; throughJump.send(Data("exit\r".utf8)) }, onData: { _ in })
        XCTAssertTrue(jumpAuthenticated)
    }
    @MainActor
    private func waitForTmux(_ connection: SSHConnection, command: String, expected: String) async throws -> String {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(4)
        var value = ""
        while clock.now < deadline {
            value = try await connection.execute(command).trimmingCharacters(in: .whitespacesAndNewlines)
            if value == expected { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        return value
    }
    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    }
    private func qrRoundtrip(_ pem: String) throws -> String {
        let now = Date(), phrase = "ABCDEFGHIJKLMNOPQRSTUVWX"
        let payload = try QRKeyPayload(name: "owned SSH integration", format: "openssh", key: Data(pem.utf8))
        let frames = try QRTransfer.seal(payload, passphrase: phrase, now: now)
        var collector = QRTransferCollector(); var packet: QRTransfer?
        for frame in frames.reversed() { packet = try collector.append(frame, now: now) ?? packet }
        let imported = try XCTUnwrap(packet).open(passphrase: phrase, now: now)
        XCTAssertEqual(imported.key, Data(pem.utf8))
        return try XCTUnwrap(String(data: imported.key, encoding: .utf8))
    }
    private static func unusedPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0); guard fd >= 0 else { throw AppError.message("socket failed") }; defer { Darwin.close(fd) }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0 else { throw AppError.message("bind failed") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let status = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        guard status == 0 else { throw AppError.message("getsockname failed") }; return Int(UInt16(bigEndian: address.sin_port))
    }
}
#endif
