import SwiftUI

struct NoteEditorView: View {
    @State var note: Note
    @ObservedObject var store: NoteStore
    @FocusState private var isFocused: Bool
    @AppStorage("fontSize") private var fontSize: Double = 14

    var body: some View {
        VStack(spacing: 0) {
            // AI Assistant Bar
            AIAssistantBar(
                isProcessing: store.isAIProcessing,
                onCancel: { store.cancelAIOperation() },
                onSummarize: { Task { await store.summarizeCurrentNote() } },
                onRewrite: { style in Task { await store.rewriteCurrentNote(style: style) } },
                onExtractActions: { Task { await store.extractActionsCurrentNote() } }
            )

            if let aiError = store.aiError, !aiError.isEmpty {
                Text(aiError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }

            // Mode-specific note view
            Group {
                switch note.keyword.lowercased() {
                case "math":
                    MathNoteView(note: $note, store: store)
                case "list":
                    ListNoteView(note: $note, store: store)
                case "code":
                    CodeNoteView(note: $note, store: store)
                case "timer":
                    TimerNoteView(note: $note, store: store)
                default:
                    PlainNoteView(note: $note, store: store)
                }
            }
            .focused($isFocused)
        }
        .navigationTitle(note.effectiveTitle.isEmpty ? "Note" : note.effectiveTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isFocused = true }
        .onChange(of: note.content) { _ in
            store.updateNoteContent(note)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fermer") { isFocused = false }
            }
        }
    }
}
