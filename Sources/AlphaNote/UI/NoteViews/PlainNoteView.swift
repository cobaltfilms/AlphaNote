import SwiftUI

struct PlainNoteView: View {
    @Binding var note: Note
    @ObservedObject var store: NoteStore
    @AppStorage("fontSize") private var fontSize: Double = 14
    @FocusState private var isEditorFocused: Bool
    @State private var showingAIResult = false

    var body: some View {
        VStack(spacing: 0) {
            AIAssistantBar(
                isProcessing: store.isAIProcessing,
                onCancel: { store.cancelAIOperation() },
                onSummarize: {
                    Task { await store.summarizeCurrentNote() }
                },
                onRewrite: { style in
                    Task { await store.rewriteCurrentNote(style: style) }
                },
                onExtractActions: {
                    Task { await store.extractActionsCurrentNote() }
                }
            )

            if let aiError = store.aiError, !aiError.isEmpty {
                HStack {
                    Text(aiError)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            TextEditor(text: $note.content)
                .font(.system(size: fontSize))
                .scrollContentBackground(.hidden)
                .focused($isEditorFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .onAppear {
                    isEditorFocused = true
                }
                .onChange(of: note.content) {
                    note.detectKeyword()
                }
        }
        .onChange(of: store.lastAIResult?.id) {
            guard let envelope = store.lastAIResult else { return }
            showingAIResult = envelope.noteID == note.id
        }
        .sheet(isPresented: $showingAIResult, onDismiss: {
            store.clearLastAIResult()
        }) {
            if let envelope = store.lastAIResult, envelope.noteID == note.id {
                AIResultSheet(
                    title: title(for: envelope.task),
                    resultText: envelope.result.text,
                    onReplace: {
                        store.applyLastAIResult(mode: .replace)
                        showingAIResult = false
                    },
                    onInsert: {
                        store.applyLastAIResult(mode: .insertBelow)
                        showingAIResult = false
                    },
                    onCancel: {
                        store.clearLastAIResult()
                        showingAIResult = false
                    }
                )
            }
        }
    }

    private func title(for task: AITask) -> String {
        switch task {
        case .summarize:
            return "Aperçu du résumé"
        case .rewrite:
            return "Aperçu de la réécriture"
        case .extractActions:
            return "Aperçu des actions"
        case .semanticAnswer:
            return "Aperçu de la réponse"
        }
    }
}
