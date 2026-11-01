import XCTest
@testable import TerminalCore

final class CoreTests: XCTestCase {
    func testOpenSSHFirstValueWinsWildcardNegationAndQuotedHost() throws {
        let result = try SSHConfig.parse("""
        Host bastion
          HostName gateway.example
          User jump
        Host work !work-old
          HostName "work.example"
          Port 2222
          ProxyJump bastion
        Host *
          User alice
          Port 22
        """)
        let work = try XCTUnwrap(result.profiles.first { $0.name == "work" })
        XCTAssertEqual(work.host, "work.example")
        XCTAssertEqual(work.port, 2222)
        XCTAssertEqual(work.user, "alice")
        XCTAssertEqual(work.jumpHost, "bastion")
        XCTAssertEqual(result.profiles.count, 2)
    }

    func testUnsafeAndUnsupportedSSHConfigIsVisible() throws {
        let result = try SSHConfig.parse("Host test\n HostName localhost\n ProxyCommand sh -c nope\n Include secrets/*\n")
        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertFalse(result.profiles[0].canConnect)
        XCTAssertThrowsError(try ConnectionProfile(name: "x", host: "a\nb", user: "root").validate())
    }

    func testStickyModifiersAndInputBoundary() {
        var state = ModifierState()
        state.tap(.control, at: 1)
        XCTAssertTrue(state.active.contains(.control))
        state.tap(.control, at: 1.2)
        state.consume()
        XCTAssertTrue(state.active.contains(.control))
        state.reset()
        XCTAssertTrue(state.active.isEmpty)
        state.tap(.shift, at: 2)
        XCTAssertEqual(KeyEncoder.text("1", modifiers: state.active), "!")
        XCTAssertEqual(KeyEncoder.text("c", modifiers: [.control]), "\u{3}")
        XCTAssertEqual(KeyEncoder.special(.left, modifiers: [.alt], applicationCursor: true), "\u{1b}[1;3D")
        XCTAssertEqual(KeyEncoder.special(.up, modifiers: [], applicationCursor: true), "\u{1b}OA")
    }

    func testDisconnectedDraftNeverReplaysEnterOrControls() {
        var draft = DisconnectedDraft()
        draft.append("日本語\r\nls\u{1b}[31m\u{3}")
        XCTAssertEqual(draft.text, "日本語 ls")
        draft.append(String(repeating: "あ", count: 20000))
        XCTAssertLessThanOrEqual(draft.text.utf8.count, 16384)
        XCTAssertFalse(draft.text.contains("\n"))
    }

    func testLogParserAcrossEveryByteBoundary() {
        let payload = Data("前\u{1b}[31m赤\u{1b}[0m\u{1b}]52;c;c2VjcmV0\u{7}後\u{1b}_Gpayload\u{1b}\\!".utf8)
        for split in 0...payload.count {
            var filter = LogFilter()
            let data = filter.consume(payload.prefix(split)) + filter.consume(payload.suffix(payload.count - split))
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "前赤後!")
        }
    }

    func testShellQuotingDoesNotEvaluateFilenames() {
        XCTAssertEqual(Shell.quote("a' $(touch x)"), "'a'\\'' $(touch x)'")
    }

    func testReconnectStopsForTrustFailureAndUserClose() {
        XCTAssertEqual(ReconnectPolicy.delay(attempt: 20), 60)
        XCTAssertFalse(ReconnectPolicy.shouldRetry(wasConnected: true, userClosed: true, trustFailure: false))
        XCTAssertFalse(ReconnectPolicy.shouldRetry(wasConnected: true, userClosed: false, trustFailure: true))
        XCTAssertTrue(ReconnectPolicy.shouldRetry(wasConnected: true, userClosed: false, trustFailure: false))
    }

    func testLocalWorkspaceUsesRealFilesAndRejectsEscape() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let shell = LocalWorkspace(root: root)
        _ = try await shell.execute("mkdir folder")
        _ = try await shell.execute("echo '日本語' > folder/test.txt")
        let output = try await shell.execute("cat folder/test.txt")
        XCTAssertEqual(output, "日本語\n")
        XCTAssertThrowsError(try shell.resolve("../../etc/passwd"))
        let link = root.appendingPathComponent("outside")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc"))
        XCTAssertThrowsError(try shell.resolve("outside/passwd"))
    }
}
