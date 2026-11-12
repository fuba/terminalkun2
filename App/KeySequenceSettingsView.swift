// MIT License
import SwiftUI
import TerminalCore

struct KeySequenceSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: KeySequence?

    var body: some View {
        let sequences = store.configuration.effectiveKeySequences
        List {
            Section {
                ForEach(sequences) { sequence in
                    Button { editing = sequence } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sequence.name).foregroundStyle(.primary)
                            Text(sequence.keys).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    var updated = sequences
                    updated.remove(atOffsets: offsets)
                    store.configuration.keySequences = updated
                }
                .onMove { offsets, index in
                    var updated = sequences
                    updated.move(fromOffsets: offsets, toOffset: index)
                    store.configuration.keySequences = updated
                }
            } footer: {
                Text("端末のキーボード上部で「キー」を押すと、この順番で表示されます。")
            }
            Section {
                Button("初期値に戻す") { store.configuration.keySequences = nil }
            }
        }
        .navigationTitle("キー列")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("キー列を追加", systemImage: "plus") { editing = .init(name: "", keys: "") }
                    .disabled(sequences.count >= KeySequence.maximumCount)
            }
            ToolbarItem(placement: .secondaryAction) { EditButton() }
        }
        .sheet(item: $editing) { sequence in
            KeySequenceEditor(sequence: sequence) { value in
                var updated = store.configuration.effectiveKeySequences
                if let index = updated.firstIndex(where: { $0.id == value.id }) { updated[index] = value }
                else if updated.count < KeySequence.maximumCount { updated.append(value) }
                store.configuration.keySequences = updated
            }
        }
    }
}

private struct KeySequenceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var sequence: KeySequence
    let save: (KeySequence) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("ボタン名", text: $sequence.name)
                Section {
                    TextField("キー列", text: $sequence.keys)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("キーを空白で区切ります。例は ^A ^[、^B [、Escape、Space、Enter、Up、M-x です。Enter を入れると改行も送ります。")
                }
            }
            .navigationTitle("キー列を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(sequence); dismiss() }.disabled(!sequence.isValid)
                }
            }
        }
    }
}
