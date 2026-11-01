import SwiftUI
import TerminalCore

struct DictionaryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    var embedded = false
    @State private var reading = ""
    @State private var word = ""
    var body: some View {
        if embedded { content }
        else { NavigationStack { content.toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } } } }
    }
    private var content: some View {
        Form {
            Section("単語を登録") {
                TextField("よみ（ひらがな）", text: $reading)
                TextField("単語", text: $word)
                Button("追加") {
                    let normalized = reading.trimmingCharacters(in: .whitespacesAndNewlines).applyingTransform(.hiraganaToKatakana, reverse: true) ?? reading
                    store.configuration.dictionary.append(UserWord(reading: normalized, word: word))
                    store.sessions.forEach { $0.keyboard.setWords(store.configuration.dictionary) }; reading = ""; word = ""
                }.disabled(reading.isEmpty || word.isEmpty)
            }
            Section("ユーザー辞書") {
                ForEach(store.configuration.dictionary) { item in HStack { Text(item.reading); Spacer(); Text(item.word) }.textSelection(.enabled) }
                    .onDelete { store.configuration.dictionary.remove(atOffsets: $0); store.sessions.forEach { $0.keyboard.setWords(store.configuration.dictionary) } }
            }
        }.navigationTitle("ユーザー辞書").navigationBarTitleDisplayMode(.inline)
    }
}
