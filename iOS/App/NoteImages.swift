import SwiftUI
import UIKit

/// Une image jointe : `attachments/<uuid de la note>/<nom>`.
struct AttachmentRef: Identifiable, Hashable {
    let noteUUID: String
    let name: String
    var id: String { "\(noteUUID)/\(name)" }
    var url: URL { NoteAttachments.fileURL(noteUUID: noteUUID, name: name) }
}

/// Vignettes des images de la note, sous l'éditeur (Android : NoteImages.kt).
/// Une image référencée mais absente (ajoutée sur un autre appareil : les
/// images ne sont pas synchronisées) apparaît en gris.
struct ImageStrip: View {
    let noteUUID: String
    let names: [String]
    let onOpen: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    Button { onOpen(name) } label: {
                        thumbnail(AttachmentRef(noteUUID: noteUUID, name: name))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Palette.windowColor)
    }

    @ViewBuilder
    private func thumbnail(_ ref: AttachmentRef) -> some View {
        Group {
            if let image = UIImage(contentsOfFile: ref.url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.fieldColor)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.lineColor))
        .accessibilityLabel("Image jointe")
    }
}

/// Visionneuse plein écran : zoom au pincement, partage, suppression.
struct ImageViewer: View {
    let ref: AttachmentRef
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = UIImage(contentsOfFile: ref.url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(MagnifyGesture()
                            .onChanged { scale = max(1, $0.magnification) }
                            .onEnded { _ in withAnimation { scale = 1 } })
                } else {
                    ContentUnavailableView("Image absente de cet appareil", systemImage: "photo",
                                           description: Text("Les images ne sont pas synchronisées : elle est restée sur l'appareil où elle a été ajoutée."))
                        .foregroundStyle(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if FileManager.default.fileExists(atPath: ref.url.path) {
                        ShareLink(item: ref.url)
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog("Retirer cette image de la note ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Retirer", role: .destructive, action: onDelete)
            }
        }
    }
}
