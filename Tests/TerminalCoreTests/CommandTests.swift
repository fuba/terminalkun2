import XCTest
@testable import TerminalCore

final class CommandTests: XCTestCase {
    func testBothAPIResponsesAndUnsafeOutputRejection() throws {
        let ollama = Data(#"{"message":{"content":"{\"command\":\"ls -la\"}"}}"#.utf8)
        let openAI = Data(#"{"choices":[{"message":{"content":"{\"command\":\"pwd\"}"}}]}"#.utf8)
        XCTAssertEqual(try CommandSuggestion.decode(ollama), "ls -la")
        XCTAssertEqual(try CommandSuggestion.decode(openAI), "pwd")
        let unsafe = Data(#"{"message":{"content":"{\"command\":\"ls\\nrm -rf /\"}"}}"#.utf8)
        XCTAssertThrowsError(try CommandSuggestion.decode(unsafe))
    }
    func testLiveCommandAPI() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["TERMINALKUN2_AI_TEST_ENDPOINT"], let model = environment["TERMINALKUN2_AI_TEST_MODEL"] else {
            throw XCTSkip("Set a real inference endpoint and model to run the live API test")
        }
        let command = try await CommandSuggestion.generate(request: "現在のディレクトリを表示してください", endpoint: endpoint, model: model)
        XCTAssertTrue(command.contains("pwd"))
        XCTAssertFalse(command.contains("\n"))
    }
}
