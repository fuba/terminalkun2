import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import TerminalCore

@MainActor
public final class JapaneseInput {
    private let converter = KanaKanjiConverter.withDefaultDictionary()
    private var composing = ComposingText()
    private var results: [Candidate] = []
    public private(set) var candidates: [String] = []
    public private(set) var converting = false
    public var words: [UserWord] = []
    public var reading: String { composing.convertTarget }
    private let memory: URL
    public init(memory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("TerminalKun2-IME")) {
        self.memory = memory
        try? FileManager.default.createDirectory(at: memory, withIntermediateDirectories: true)
    }
    public func insert(_ text: String) {
        composing.insertAtCursorPosition(text, inputStyle: .roman2kana); converting = false; refresh()
    }
    public func deleteBackward() {
        if converting { converting = false; return }
        composing.deleteBackwardFromCursorPosition(count: 1); refresh()
    }
    public func moveCursor(_ count: Int) { _ = composing.moveCursorFromCursorPosition(count: count); refresh() }
    public func convert() { converting = true; refresh() }
    public func cancel() { composing.stopComposition(); converter.stopComposition(); candidates = []; results = []; converting = false }
    public func commit(index: Int? = nil) -> String {
        let selected = index ?? (converting ? 0 : -1)
        let value = candidates.indices.contains(selected) ? candidates[selected] : reading
        if let candidate = results.first(where: { $0.text == value }) {
            converter.setCompletedData(candidate); converter.updateLearningData(candidate)
        }
        cancel(); return value
    }
    private func refresh() {
        guard !composing.isEmpty else { candidates = []; results = []; return }
        let options = ConvertRequestOptions(
            requireJapanesePrediction: true, requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP, learningType: .inputAndOutput,
            memoryDirectoryURL: memory, sharedContainerURL: memory,
            textReplacer: .withDefaultEmojiDictionary(), specialCandidateProviders: nil,
            metadata: .init(versionString: "TerminalKun2 0.1"))
        results = converter.requestCandidates(composing, options: options).mainResults
        let custom = words.filter { $0.reading == reading || $0.reading.hasPrefix(reading) }.map(\.word)
        var seen: Set<String> = []
        candidates = (custom + results.map(\.text) + [reading, reading.applyingTransform(.hiraganaToKatakana, reverse: false) ?? reading]).filter { seen.insert($0).inserted }
    }
}
