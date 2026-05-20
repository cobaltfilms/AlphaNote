import SwiftUI

struct NoteListView: View {
    @StateObject private var store = NoteStore()

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            if store.notes.isEmpty {
                Text("No notes")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else if let note = store.currentNote {
                store.viewForNote(note)
                    .id(note.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let horizontalAmount = value.translation.width
                    if horizontalAmount < -30 {
                        store.navigateNext()
                    } else if horizontalAmount > 30 {
                        store.navigatePrevious()
                    }
                }
        )
        .onAppear {
            store.loadNotes()
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}