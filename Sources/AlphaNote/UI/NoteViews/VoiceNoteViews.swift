import SwiftUI

/// Bandeau affiché pendant l'enregistrement d'une note vocale : durée, texte
/// transcrit au fil de la voix, arrêt et abandon. Partagé macOS / iOS.
struct VoiceRecordingBanner: View {
    @ObservedObject var recorder: VoiceNoteRecorder
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative, isActive: true)
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(VoiceNotePlayer.clock(recorder.startedAt.map { context.date.timeIntervalSince($0) } ?? 0))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textColor)
                }
                Text("Note vocale en cours")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryColor)
                Spacer(minLength: 8)
                Button("Annuler", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryColor)
                Button(action: onStop) {
                    Label("Terminer", systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.red))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("voiceNoteStop")
            }
            if let issue = recorder.transcriptionIssue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryColor)
            } else {
                Text(recorder.transcript.isEmpty ? "Parle : le texte apparaît ici." : recorder.transcript)
                    .font(.system(size: 12))
                    .foregroundStyle(recorder.transcript.isEmpty ? Palette.secondaryColor : Palette.textColor)
                    .lineLimit(3)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Palette.fieldColor)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineColor).frame(height: 1) }
    }
}

/// Les notes vocales d'une note : une rangée par enregistrement (lecture,
/// durée, suppression). Un fichier absent a été enregistré sur un autre
/// appareil et n'est pas encore arrivé par la synchro Nextcloud.
struct VoiceNoteStrip: View {
    let noteUUID: String
    let names: [String]
    @ObservedObject var player: VoiceNotePlayer
    let onDelete: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(names.enumerated()), id: \.element) { index, name in
                row(name: name, number: index + 1)
            }
        }
        .background(Palette.windowColor)
        .overlay(alignment: .top) { Rectangle().fill(Palette.lineColor).frame(height: 1) }
    }

    private func row(name: String, number: Int) -> some View {
        let url = NoteAttachments.fileURL(noteUUID: noteUUID, name: name)
        let duration = VoiceNotePlayer.duration(of: url)
        let playing = player.playingURL == url
        return HStack(spacing: 10) {
            Button { player.toggle(url) } label: {
                Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(duration == nil ? Palette.secondaryColor.opacity(0.4) : Palette.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(duration == nil)
            .accessibilityLabel(playing ? "Arrêter la lecture" : "Écouter la note vocale \(number)")

            Text(names.count > 1 ? "Note vocale \(number)" : "Note vocale")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.textColor)
            Text(duration.map(VoiceNotePlayer.clock) ?? "Enregistrée sur un autre appareil")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryColor)
            Spacer(minLength: 8)
            Button { 
                if playing { player.stop() }
                onDelete(name)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.secondaryColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Supprimer l'enregistrement")
            #if os(macOS)
            .help("Supprimer l'enregistrement (le texte transcrit reste dans la note)")
            #endif
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

/// Choix du thème d'une note : un thème existant, un nouveau, ou aucun (le
/// thème redevient alors celui que le classement propose).
struct ThemeSheet: View {
    let current: String?
    let isExplicit: Bool
    let themes: [String]
    let onPick: (String?) -> Void
    let onCancel: () -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Thème de la note").font(.headline)
            if let current {
                Text(isExplicit ? "Thème actuel : \(current)" : "Thème proposé : \(current) (non écrit dans la note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("Nouveau thème", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitDraft)
                Button("Créer", action: commitDraft)
                    .disabled(NoteThemes.normalized(draft).isEmpty)
            }
            if !themes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(themes, id: \.self) { theme in
                            Button { onPick(theme) } label: {
                                HStack {
                                    Text(theme)
                                    Spacer()
                                    if let current, NoteThemes.key(current) == NoteThemes.key(theme) {
                                        Image(systemName: isExplicit ? "checkmark" : "sparkle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            HStack {
                if isExplicit {
                    Button("Aucun thème") { onPick(nil) }
                }
                Spacer()
                Button("Annuler", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        #if os(macOS)
        .frame(width: 340)
        #endif
    }

    private func commitDraft() {
        let name = NoteThemes.normalized(draft)
        if !name.isEmpty { onPick(name) }
    }
}
