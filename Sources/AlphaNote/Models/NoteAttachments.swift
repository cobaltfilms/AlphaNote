import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pièces jointes des notes (images et notes vocales), même format qu'Android
/// (domain/NoteAttachments.kt).
///
/// Les octets vivent dans `Application Support/AlphaNote/attachments/<uuid de la
/// note>/<nom>` ; le texte de la note ne garde qu'une ligne
/// `![image](att:<nom>.jpg)` ou `![audio](att:<nom>.m4a)`. La synchro Nextcloud
/// fait circuler les fichiers à côté des notes (`Sync/AttachmentSync.swift`) :
/// envoyés s'ils manquent sur le serveur, téléchargés s'ils manquent ici,
/// jamais modifiés. La synchro Wi-Fi directe ne transporte que le texte.
enum NoteAttachments {
    private static let reference = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(att:([A-Za-z0-9._-]+)\)"#)
    static let maxSide = 1600

    /// Noms des images référencées par le texte, dans l'ordre d'apparition.
    static func names(in content: String) -> [String] {
        let ns = content as NSString
        return reference.matches(in: content, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }

    /// Extensions des enregistrements (m4a sur Apple et Android, wav en repli).
    static let audioExtensions: Set<String> = ["m4a", "wav"]

    static func isAudio(_ name: String) -> Bool {
        audioExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Images seulement, dans l'ordre d'apparition (galeries).
    static func imageNames(in content: String) -> [String] {
        names(in: content).filter { !isAudio($0) }
    }

    /// Notes vocales seulement, dans l'ordre d'apparition.
    static func audioNames(in content: String) -> [String] {
        names(in: content).filter(isAudio)
    }

    static func markdown(_ name: String) -> String {
        isAudio(name) ? "![audio](att:\(name))" : "![image](att:\(name))"
    }

    /// Nom de fichier d'un nouvel enregistrement.
    static func newAudioName() -> String { UUID().uuidString.lowercased() + ".m4a" }

    /// Ligne faite d'une seule référence vers une note vocale.
    static func isAudioLine(_ line: String) -> Bool {
        guard isImageLine(line) else { return false }
        return names(in: line).first.map(isAudio) ?? false
    }

    /// macOS : l'éditeur montre tout sauf les lignes de notes vocales (elles ont
    /// leur propre barre de lecture). Inverse : `withAudio`.
    static func textHidingAudio(_ content: String) -> String {
        content.components(separatedBy: "\n").filter { !isAudioLine($0) }.joined(separator: "\n")
    }

    /// Contenu stocké : le texte de l'éditeur macOS, puis les notes vocales de `content`.
    static func withAudio(_ visible: String, content: String) -> String {
        let refs = audioNames(in: content)
        guard !refs.isEmpty else { return visible }
        return visible + "\n" + refs.map(markdown).joined(separator: "\n")
    }

    /// Ajoute une note vocale : la transcription rejoint le texte (paragraphe à
    /// part), la référence du fichier va en fin de note avec les autres pièces
    /// jointes. Le thème éventuel reste la dernière ligne de texte.
    static func addingVoiceNote(to content: String, audioName: String, transcript: String) -> String {
        let theme = NoteThemes.explicit(in: content)
        let lines = NoteThemes.removingTheme(from: content).components(separatedBy: "\n")
        var body = lines.filter { !isImageLine($0) }.joined(separator: "\n")
        while body.hasSuffix("\n") || body.hasSuffix(" ") { body.removeLast() }
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spoken.isEmpty {
            body += body.isEmpty ? spoken : "\n\n" + spoken
        }
        body = NoteThemes.settingTheme(theme, in: body)
        let refs = names(in: content) + [audioName]
        let tail = refs.map(markdown).joined(separator: "\n")
        return body.isEmpty ? tail : body + "\n" + tail
    }

    /// Retire la référence d'une pièce jointe (la ligne entière).
    static func removingReference(_ name: String, from content: String) -> String {
        content.components(separatedBy: "\n")
            .filter { !($0.contains("(att:\(name))") && isImageLine($0)) }
            .joined(separator: "\n")
    }

    /// Supprime tous les fichiers joints d'une note.
    static func removeAll(noteUUID: String) {
        try? FileManager.default.removeItem(at: rootDirectory.appendingPathComponent(noteUUID, isDirectory: true))
    }

    /// Ligne faite d'une seule pièce jointe (image ou note vocale).
    static func isImageLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let ns = trimmed as NSString
        guard let match = reference.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) else { return false }
        return match.range.location == 0 && match.range.length == ns.length
    }

    /// Texte sans les lignes d'images (pour le partage et l'aperçu).
    /// Texte montré dans l'éditeur : la note sans ses lignes d'images (elles
    /// s'affichent à part). Inverse exact de `withImages` tant que les images
    /// sont en fin de note, ce que `withImages` garantit. Même règle qu'Android.
    static func visibleText(_ content: String) -> String {
        content.components(separatedBy: "\n").filter { !isImageLine($0) }.joined(separator: "\n")
    }

    /// Contenu stocké : le texte de l'éditeur, puis les références des images de `content`.
    static func withImages(_ visible: String, content: String) -> String {
        let refs = names(in: content)
        guard !refs.isEmpty else { return visible }
        return visible + "\n" + refs.map(markdown).joined(separator: "\n")
    }

    static func textWithoutImages(_ content: String) -> String {
        content.components(separatedBy: "\n")
            .filter { !isImageLine($0) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var rootDirectory: URL {
        URL(fileURLWithPath: DatabaseManager.defaultDatabaseDirectoryPath(), isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
    }

    static func fileURL(noteUUID: String, name: String) -> URL {
        rootDirectory.appendingPathComponent(noteUUID, isDirectory: true).appendingPathComponent(name)
    }

    /// Copie l'image dans le stockage de l'app, réduite à `maxSide` px et
    /// réencodée en JPEG 85 % (orientation EXIF appliquée). Retourne le nom, ou
    /// nil si les données ne sont pas une image lisible.
    static func importImage(_ data: Data, noteUUID: String) -> String? {
        guard let jpeg = normalizedJPEG(from: data) else { return nil }
        let name = UUID().uuidString.lowercased() + ".jpg"
        let target = fileURL(noteUUID: noteUUID, name: name)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jpeg.write(to: target, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func remove(noteUUID: String, name: String) {
        try? FileManager.default.removeItem(at: fileURL(noteUUID: noteUUID, name: name))
    }

    static func normalizedJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
