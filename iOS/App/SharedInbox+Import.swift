import Foundation
import UIKit

extension SharedInbox {
    /// Côté app : crée une note par texte en attente, puis vide la boîte.
    @MainActor
    static func importPending(into store: NoteStore) {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter({ $0.pathExtension == "txt" })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }),
              !files.isEmpty else { return }
        var created = 0
        for file in files {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if store.addNote(content: text) != nil { created += 1 }
        }
        if created > 0 {
            store.showToast(created == 1 ? "Note créée depuis un partage" : "\(created) notes créées depuis des partages",
                            symbol: "square.and.arrow.down")
        }
    }
}

/// Icône de l'app assortie au thème de couleur, comme les icônes de lancement
/// par thème d'Android. L'icône principale est la corail.
enum AppIconSwitcher {
    @MainActor
    static func apply(theme: String) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        let wanted: String? = theme == ColorTheme.corail.rawValue ? nil : "AppIcon-\(theme)"
        guard app.alternateIconName != wanted else { return }
        app.setAlternateIconName(wanted) { error in
            if let error { print("[AppIconSwitcher] \(error.localizedDescription)") }
        }
    }
}
