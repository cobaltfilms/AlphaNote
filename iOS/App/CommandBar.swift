import SwiftUI
import UIKit

/// Barre de commande : une demande en langage naturel (tapée ou dictée) que
/// JEV classe (math, liste, minuteur, code) puis applique à la note courante.
/// Même rôle que CommandField sur Android ; la dictée reprend le bouton micro
/// du premier essai iOS (PlainNoteView).
struct CommandBar: View {
    @EnvironmentObject private var store: NoteStore
    @StateObject private var speech = SpeechRecognizer()
    @State private var query = ""
    @State private var showMicPermissionAlert = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            if speech.isListening {
                HStack(spacing: 8) {
                    ProgressView().tint(.red)
                    Text("Écoute…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.opacity)
            }

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Palette.accentColor)
                TextField("Demande : « 3 × 12 € », lien de recette…", text: $query)
                    .focused($fieldFocused)
                    .accessibilityIdentifier("commandField")
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .disabled(store.isAIProcessing)
                if store.isAIProcessing {
                    ProgressView()
                } else if !query.isEmpty, !speech.isListening {
                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("Envoyer la demande")
                }
                micButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.fieldColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.lineColor))
        }
        .animation(.easeInOut(duration: 0.15), value: speech.isListening)
        // Texte partiel affiché pendant la dictée ; envoi quand elle s'arrête.
        .onChange(of: speech.transcript) { _, newValue in
            if !newValue.isEmpty { query = newValue }
        }
        .onChange(of: speech.isListening) { wasListening, isListening in
            if wasListening, !isListening, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                submit()
            }
        }
        // startListening() ne lève pas : les échecs arrivent par `error`.
        .onChange(of: speech.error != nil) { _, hasError in
            if hasError { showMicPermissionAlert = true }
        }
        .alert("Reconnaissance vocale", isPresented: $showMicPermissionAlert) {
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text(speech.error?.errorDescription
                 ?? "AlphaNote a besoin d'accéder au microphone et à la reconnaissance vocale. Active ces permissions dans les Réglages.")
        }
    }

    private var micButton: some View {
        Button {
            if speech.isListening {
                speech.stopListening()
            } else {
                fieldFocused = false
                query = ""
                Task { try? await speech.startListening() }
            }
        } label: {
            Image(systemName: speech.isListening ? "waveform.circle.fill" : "mic.fill")
                .font(.title2)
                .foregroundStyle(speech.isListening ? .red : Palette.accentColor)
                .symbolEffect(.pulse, isActive: speech.isListening)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(store.isAIProcessing)
        .accessibilityLabel(speech.isListening ? "Arrêter l'écoute" : "Dictée vocale")
    }

    private func submit() {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !store.isAIProcessing else { return }
        fieldFocused = false
        Task {
            await store.routeQuestion(question)
            query = ""
        }
    }
}

/// Message transitoire du NoteStore (mode choisi, synchro…), en bas d'écran.
struct ToastView: View {
    let toast: Toast

    var body: some View {
        Label(toast.text, systemImage: toast.symbol)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("toast")
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
