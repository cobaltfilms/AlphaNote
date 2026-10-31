import SwiftUI
import PhotosUI

/// Écran d'une note : l'éditeur unique, la puce de mode, le minuteur (mode
/// timer), les images jointes et la barre de commande. Suit toujours la note
/// courante du NoteStore : une demande « minuteur 5 min » qui crée une note
/// l'affiche aussitôt, comme sur macOS et Android.
struct NoteEditScreen: View {
    @EnvironmentObject private var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = 17.0
    @AppStorage(AppSettings.listCheckTriggerKey) private var checkTrigger = "/x"
    @AppStorage(AppSettings.confirmDeleteKey) private var confirmDelete = true

    @State private var editorFocused = false
    @State private var renaming: Note?
    @State private var renameDraft = ""
    @State private var deleting: Note?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var sharing: ShareContent?
    @State private var viewing: AttachmentRef?

    var body: some View {
        Group {
            if let note = store.currentNote {
                content(for: note)
            } else {
                ContentUnavailableView("Aucune note", systemImage: "note.text")
            }
        }
        .background(Palette.contentColor.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                ToastView(toast: toast).padding(.bottom, 84)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toast)
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await addImage(from: item) }
        }
        .alert("Renommer la note", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titre", text: $renameDraft)
            Button("Renommer") {
                if let note = renaming { store.renameNote(note, to: renameDraft) }
                renaming = nil
            }
            Button("Annuler", role: .cancel) { renaming = nil }
        } message: {
            Text("Un titre vide reprend la première ligne.")
        }
        .confirmationDialog("Supprimer cette note ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let note = deleting { delete(note) }
                deleting = nil
            }
        }
        .sheet(item: $sharing) { content in
            ActivityView(items: content.items).presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $viewing) { ref in
            ImageViewer(ref: ref) {
                removeImage(ref)
                viewing = nil
            }
        }
        .onDisappear { store.flushPendingSaves() }
    }

    @ViewBuilder
    private func content(for note: Note) -> some View {
        let mode = NoteMode(rawValue: note.keyword) ?? .plain
        VStack(spacing: 0) {
            if mode == .timer {
                timerView(for: note)
                    .padding(.vertical, 12)
                Divider()
            }
            NoteTextView(text: contentBinding, fontSize: fontSize, checkTrigger: checkTrigger, isFocused: $editorFocused)
            let images = NoteAttachments.names(in: note.content)
            if !images.isEmpty {
                ImageStrip(noteUUID: note.uuid, names: images) { name in
                    viewing = AttachmentRef(noteUUID: note.uuid, name: name)
                }
            }
            CommandBar()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.windowColor)
        }
    }

    private func timerView(for note: Note) -> some View {
        let parameters = store.timerParameters(for: note)
        let session = TimerRegistry.shared.session(for: note.uuid, defaultMode: parameters.mode, defaultSeconds: parameters.seconds)
        return TimerNoteView(session: session) { mode, seconds in
            store.updateTimerLine(noteID: note.id, mode: mode, seconds: seconds)
        }
        .id(note.uuid)
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { store.currentNote?.content ?? "" },
            set: { newValue in
                guard var note = store.currentNote, note.content != newValue else { return }
                note.content = newValue
                store.edit(note)
            }
        )
    }

    // MARK: - Barre d'outils

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if let note = store.currentNote {
                modeChip(for: note)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if editorFocused {
                Button("OK") { editorFocused = false; hideKeyboard() }
            }
            if let note = store.currentNote {
                Menu {
                    noteMenu(for: note)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func modeChip(for note: Note) -> some View {
        let current = NoteMode(rawValue: note.keyword) ?? .plain
        return Menu {
            ForEach(NoteMode.allCases, id: \.self) { mode in
                Button {
                    store.setMode(mode, for: note)
                } label: {
                    if mode == current {
                        Label(mode.label.capitalized, systemImage: "checkmark")
                    } else {
                        Text(mode.label.capitalized)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Palette.modeColor(current)).frame(width: 8, height: 8)
                Text(current.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ModePalette.foreground(current))
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(ModePalette.background(current), in: Capsule())
        }
        .accessibilityLabel("Mode de la note : \(current.label)")
    }

    @ViewBuilder
    private func noteMenu(for note: Note) -> some View {
        Button { showPhotoPicker = true } label: { Label("Ajouter une image", systemImage: "photo.badge.plus") }
        Button { share(note) } label: { Label("Partager", systemImage: "square.and.arrow.up") }
        Button {
            UIPasteboard.general.string = note.content
            store.showToast("Contenu copié", symbol: "doc.on.doc")
        } label: { Label("Copier le contenu", systemImage: "doc.on.doc") }
        Divider()
        Button {
            renameDraft = note.title.isEmpty ? NoteFormatting.displayTitle(note) : note.title
            renaming = note
        } label: { Label("Renommer", systemImage: "pencil") }
        Button { store.togglePin(note) } label: {
            Label(note.isPinned ? "Désépingler" : "Épingler", systemImage: note.isPinned ? "pin.slash" : "pin")
        }
        Button { store.duplicateNote(note) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
        Button {
            store.archiveNote(note)
            dismiss()
        } label: { Label("Archiver", systemImage: "archivebox") }
        Divider()
        Button(role: .destructive) {
            if confirmDelete, !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                deleting = note
            } else {
                delete(note)
            }
        } label: { Label("Supprimer", systemImage: "trash") }
    }

    private func delete(_ note: Note) {
        for name in NoteAttachments.names(in: note.content) {
            NoteAttachments.remove(noteUUID: note.uuid, name: name)
        }
        store.deleteNote(note)
        dismiss()
    }

    // MARK: - Images

    private func addImage(from item: PhotosPickerItem) async {
        guard let note = store.currentNote,
              let data = try? await item.loadTransferable(type: Data.self),
              let name = NoteAttachments.importImage(data, noteUUID: note.uuid) else {
            store.showToast("Image illisible", symbol: "exclamationmark.triangle")
            return
        }
        guard var current = store.currentNote, current.uuid == note.uuid else { return }
        let trimmed = current.content.replacingOccurrences(of: #"\n+$"#, with: "", options: .regularExpression)
        current.content = (trimmed.isEmpty ? "" : trimmed + "\n") + NoteAttachments.markdown(name) + "\n"
        store.updateNote(current)
    }

    private func removeImage(_ ref: AttachmentRef) {
        guard var note = store.currentNote, note.uuid == ref.noteUUID else { return }
        note.content = note.content
            .components(separatedBy: "\n")
            .filter { !($0.contains("(att:\(ref.name))") && NoteAttachments.isImageLine($0)) }
            .joined(separator: "\n")
        store.updateNote(note)
        NoteAttachments.remove(noteUUID: ref.noteUUID, name: ref.name)
    }

    // MARK: - Partage

    /// Titre + texte sans les lignes d'images, et les images en pièces jointes
    /// (comme le partage Android).
    private func share(_ note: Note) {
        store.flushPendingSaves()
        let body = NoteAttachments.textWithoutImages(note.content)
        let title = NoteFormatting.displayTitle(note)
        let text = body.hasPrefix(title) ? body : "\(title)\n\n\(body)"
        var items: [Any] = [text]
        for name in NoteAttachments.names(in: note.content) {
            let url = NoteAttachments.fileURL(noteUUID: note.uuid, name: name)
            if FileManager.default.fileExists(atPath: url.path) { items.append(url) }
        }
        sharing = ShareContent(items: items)
    }
}

struct ShareContent: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
