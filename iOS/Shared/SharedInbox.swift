import Foundation

/// Texte reçu par l'extension de partage (« Partager › AlphaNote ») : elle le
/// dépose dans le conteneur du groupe d'apps, l'app en fait une note au retour
/// au premier plan. Même effet que l'intent SEND text/plain d'Android.
enum SharedInbox {
    static let appGroup = "group.be.cobaltfilms.alphanote"
    private static let folderName = "Inbox"

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// Côté extension : un fichier .txt par partage.
    static func deposit(_ text: String) throws {
        guard let folder else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
