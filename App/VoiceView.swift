import SwiftUI
import Speech
import AVFoundation
import TerminalCore

@MainActor
final class SpeechInput: ObservableObject {
    @Published var transcript = ""
    @Published var recording = false
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    func start() async {
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard speech == .authorized else { error = "設定から音声認識を許可してください。"; return }
        let microphone = await withCheckedContinuation { continuation in AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) } }
        guard microphone else { error = "設定からマイクを許可してください。"; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")), recognizer.isAvailable else { error = "日本語の音声認識を利用できません。"; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers); try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw AppError.message("マイクから音声を取得できません。") }
            let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }; hasTap = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in Task { @MainActor in
                if let result { self?.transcript = result.bestTranscription.formattedString }
                if let error { self?.error = error.localizedDescription; self?.stop() }
                else if result?.isFinal == true { self?.stop() }
            } }
            engine.prepare(); try engine.start(); recording = true
        } catch { self.error = error.localizedDescription; stop() }
    }
    func stop() {
        engine.stop(); if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct VoiceView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @StateObject private var speech = SpeechInput()
    @State private var generated = ""
    @State private var generating = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("依頼・入力する文章") {
                    TextEditor(text: $speech.transcript).frame(minHeight: 100).accessibilityIdentifier("commandRequest")
                    Button(speech.recording ? "録音を止める" : "日本語で音声入力", systemImage: speech.recording ? "stop.circle.fill" : "mic") {
                        if speech.recording { speech.stop() } else { Task { await speech.start() } }
                    }
                }
                Section {
                    Button("文字として端末へ挿入") { insert(speech.transcript) }.disabled(speech.transcript.isEmpty || store.selected == nil)
                    Button("定型コマンド候補を作成") {
                        if let command = CommandSuggestion.offline(speech.transcript) { generated = command; error = nil }
                        else { error = "定型候補がありません。自由文の生成には 生成 API を設定してください。" }
                    }.disabled(speech.transcript.isEmpty)
                    Button("AI でコマンドを生成") {
                        generating = true; error = nil
                        Task {
                            defer { generating = false }
                            do { generated = try await CommandSuggestion.generate(request: speech.transcript, endpoint: store.configuration.aiEndpoint, model: store.configuration.aiModel) }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(generating || speech.transcript.isEmpty)
                    if generating { ProgressView() }
                }
                if !generated.isEmpty {
                    Section("コマンドを確認") {
                        TextEditor(text: $generated).font(.system(.body, design: .monospaced)).frame(minHeight: 100)
                        Button("確認して入力欄へ挿入") { insert(generated.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")) }.disabled(store.selected == nil)
                        Text("Enter は送信しません。実行前に接続先とコマンドの内容を確認できます。").font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let error = error ?? speech.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("音声・コマンド作成").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }.onDisappear { speech.stop() }
    }
    private func insert(_ value: String) {
        let line = value.components(separatedBy: .newlines).joined(separator: " ")
        let clean = String(String.UnicodeScalarView(line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        store.selected?.terminal.pasteText(clean); dismiss()
    }
}
