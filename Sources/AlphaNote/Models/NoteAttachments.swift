import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images attachées aux notes, même format qu'Android (domain/NoteAttachments.kt).
///
/// Les octets vivent dans `Application Support/AlphaNote/attachments/<uuid de la
/// note>/<nom>.jpg` ; le texte de la note ne garde qu'une ligne
/// `![image](att:<nom>)`. Pas encore synchronisées vers Nextcloud : seule la
/// ligne circule.
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

    static func markdown(_ name: String) -> String { "![image](att:\(name))" }

    static func isImageLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let ns = trimmed as NSString
        guard let match = reference.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) else { return false }
        return match.range.location == 0 && match.range.length == ns.length
    }

    /// Texte sans les lignes d'images (pour le partage et l'aperçu).
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
