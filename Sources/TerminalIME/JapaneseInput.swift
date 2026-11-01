import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import TerminalCore

@MainActor
public final class JapaneseInput {
    public struct Segment {
        public var reading: String
        public var text: String
    }
    private let converter = KanaKanjiConverter.withDefaultDictionary()
    private var composing = ComposingText()
    private var results: [Candidate] = []
    public private(set) var candidates: [String] = []
    public private(set) var converting = false
    public private(set) var segments: [Segment] = []
    public private(set) var selectedSegment = 0
    private var learned: [String: [String]] = [:]
    public var words: [UserWord] = []
    public var reading: String { composing.convertTarget }
    private let memory: URL
    public init(memory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("TerminalKun2-IME")) {
        self.memory = memory
        try? FileManager.default.createDirectory(at: memory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: memory.appendingPathComponent("selections.json")), let values = try? JSONDecoder().decode([String: [String]].self, from: data) { learned = values }
    }
    public func insert(_ text: String) {
        for character in text {
            if composing.isAtEndIndex, "aiueoy".contains(character), composing.input.reversed().prefix(while: { element in
                if case .character(let value) = element.piece { return value == "n" }; return false
            }).count == 2 { composing.insertAtCursorPosition("n", inputStyle: .roman2kana) }
            composing.insertAtCursorPosition(String(character), inputStyle: .roman2kana)
        }
        converting = false; segments = []; refresh()
    }
    public func deleteBackward() {
        if converting { converting = false; segments = []; refresh(); return }
        composing.deleteBackwardFromCursorPosition(count: 1); refresh()
    }
    public func moveCursor(_ count: Int) { _ = composing.moveCursorFromCursorPosition(count: count); refresh() }
    public func convert() {
        refresh(); converting = true; selectedSegment = 0
        let kana = reading.applyingTransform(.hiraganaToKatakana, reverse: false) ?? reading
        if let best = results.first(where: { $0.data.map(\.ruby).joined() == kana }), !best.data.isEmpty {
            segments = best.data.map { Segment(reading: $0.ruby.applyingTransform(.hiraganaToKatakana, reverse: true) ?? $0.ruby, text: $0.word) }
        } else { segments = [Segment(reading: reading, text: candidates.first ?? reading)] }
        refreshSegment()
    }
    public func selectSegment(_ index: Int) {
        guard segments.indices.contains(index) else { return }; selectedSegment = index; refreshSegment()
    }
    public func moveSegment(_ offset: Int) { selectSegment(max(0, min(segments.count - 1, selectedSegment + offset))) }
    public func selectCandidate(_ index: Int) {
        guard converting, segments.indices.contains(selectedSegment), candidates.indices.contains(index) else { return }
        segments[selectedSegment].text = candidates[index]
    }
    public func adjustBoundary(_ delta: Int) {
        let index = selectedSegment
        guard converting, segments.indices.contains(index), segments.indices.contains(index + 1) else { return }
        var left = segments[index].reading, right = segments[index + 1].reading
        if delta < 0, left.count > 1 { right.insert(left.removeLast(), at: right.startIndex) }
        else if delta > 0, !right.isEmpty { left.append(right.removeFirst()) }
        else { return }
        segments[index] = Segment(reading: left, text: left)
        if right.isEmpty { segments.remove(at: index + 1) }
        else { segments[index + 1] = Segment(reading: right, text: right) }
        refreshSegment()
    }
    public func cancel() { composing.stopComposition(); converter.stopComposition(); candidates = []; results = []; converting = false; segments = []; selectedSegment = 0 }
    public func commit(index: Int? = nil) -> String {
        if converting, let index { selectCandidate(index) }
        let selected = index ?? -1
        let value = converting ? segments.map(\.text).joined() : (candidates.indices.contains(selected) ? candidates[selected] : reading)
        if let candidate = results.first(where: { $0.text == value }) {
            converter.setCompletedData(candidate); converter.updateLearningData(candidate); converter.commitUpdateLearningData()
        }
        if !reading.isEmpty, !value.isEmpty {
            var history = learned[reading] ?? []; history.removeAll { $0 == value }; history.insert(value, at: 0)
            learned[reading] = Array(history.prefix(8))
            if learned.count > 4096, let key = learned.keys.sorted().first { learned.removeValue(forKey: key) }
            if let data = try? JSONEncoder().encode(learned) {
                #if os(iOS)
                try? data.write(to: memory.appendingPathComponent("selections.json"), options: [.atomic, .completeFileProtection])
                #else
                try? data.write(to: memory.appendingPathComponent("selections.json"), options: [.atomic])
                #endif
            }
        }
        cancel(); return value
    }
    private func refresh() {
        guard !composing.isEmpty else { candidates = []; results = []; return }
        let options = options(prediction: true)
        results = converter.requestCandidates(composing, options: options).mainResults
        let custom = words.filter { $0.reading == reading || $0.reading.hasPrefix(reading) }.map(\.word)
        var seen: Set<String> = []
        candidates = ((learned[reading] ?? []) + custom + results.map(\.text) + [reading, reading.applyingTransform(.hiraganaToKatakana, reverse: false) ?? reading]).filter { seen.insert($0).inserted }
    }
    private func refreshSegment() {
        guard segments.indices.contains(selectedSegment) else { return }
        let segment = segments[selectedSegment]
        var input = ComposingText(); input.insertAtCursorPosition(segment.reading, inputStyle: .direct)
        let choices = converter.requestCandidates(input, options: options(prediction: false)).mainResults
        let custom = words.filter { $0.reading == segment.reading }.map(\.word)
        var seen: Set<String> = []
        candidates = [segment.text] + (learned[segment.reading] ?? []) + custom + choices.map(\.text) + [segment.reading, segment.reading.applyingTransform(.hiraganaToKatakana, reverse: false) ?? segment.reading]
        candidates = candidates.filter { seen.insert($0).inserted }
    }
    private func options(prediction: Bool) -> ConvertRequestOptions {
        ConvertRequestOptions(
            requireJapanesePrediction: prediction, requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP, learningType: .inputAndOutput,
            memoryDirectoryURL: memory, sharedContainerURL: memory,
            textReplacer: .withDefaultEmojiDictionary(), specialCandidateProviders: nil,
            metadata: .init(versionString: "TerminalKun2 0.1"))
    }
}
