import SwiftUI

@main
struct AlphaNoteApp: App {
    @StateObject private var store = NoteStore()
    @State private var selectedNoteID: Int64?

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, selectedNoteID: $selectedNoteID)
                .onOpenURL { url in
                    // Deep link: alphanote://note/<uuid>
                    if url.host == "note", let uuid = url.pathComponents.last {
                        store.selectNote(byUUID: uuid)
                    }
                }
        }
    }
}
