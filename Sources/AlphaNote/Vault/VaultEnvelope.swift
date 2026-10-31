import CommonCrypto
import CryptoKit
import Foundation

/// Note sécurisée telle qu'elle est stockée et synchronisée :
///
///     vault: Jetons Cloudflare                 ← en clair (titre, liste, recherche)
///     ANVAULT1.<sel>.<itérations>.<scellé>     ← corps chiffré
///
/// Le corps (tout ce qui suit la première ligne) est chiffré en AES-256-GCM
/// avec une clé dérivée du mot de passe maître (PBKDF2-HMAC-SHA256). Le sel et
/// le nombre d'itérations voyagent dans l'enveloppe : n'importe quel appareil
/// qui connaît le mot de passe peut la rouvrir, sans métadonnées à synchroniser.
/// Base64 URL sans remplissage ; scellé = nonce (12) ‖ chiffré ‖ tag (16).
/// Même format sur Android (VaultEnvelope.kt).
enum VaultEnvelope {
    static let keyword = "vault"
    static let prefix = "ANVAULT1."
    static let iterations = 600_000
    static let saltLength = 16
    /// Données associées : une enveloppe d'une autre application ou d'un autre
    /// format ne s'ouvre pas par erreur.
    private static let associatedData = Data("alphanote-vault-v1".utf8)

    struct Parsed: Equatable {
        let header: String
        let salt: Data
        let iterations: Int
        let sealed: Data
    }

    enum Failure: Error, Equatable {
        case wrongKey
        case malformed
    }

    // MARK: - Lecture du format

    static func isVaultHeader(_ firstLine: String) -> Bool {
        let line = firstLine.trimmingCharacters(in: .whitespaces).lowercased()
        return line == keyword || line.hasPrefix(keyword + ":")
    }

    /// Première ligne et reste d'un contenu.
    static func split(_ content: String) -> (header: String, body: String) {
        guard let newline = content.firstIndex(of: "\n") else { return (content, "") }
        return (String(content[..<newline]), String(content[content.index(after: newline)...]))
    }

    /// Le contenu est-il déjà scellé (corps = une enveloppe) ?
    static func isSealed(_ content: String) -> Bool {
        parse(content) != nil
    }

    static func parse(_ content: String) -> Parsed? {
        let (header, body) = split(content)
        let token = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // L'en-tête peut être en cours de frappe (« vaul: … ») : seul le corps compte.
        guard token.hasPrefix(prefix) else { return nil }
        let parts = token.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let salt = Data(base64URL: String(parts[0])), salt.count == saltLength,
              let iterations = Int(parts[1]), iterations >= 100_000,
              let sealed = Data(base64URL: String(parts[2])), sealed.count >= 12 + 16 else {
            return nil
        }
        return Parsed(header: header, salt: salt, iterations: iterations, sealed: sealed)
    }

    // MARK: - Clés

    static func deriveKey(password: String, salt: Data, iterations: Int = iterations) -> SymmetricKey {
        let passwordData = Data(password.precomposedStringWithCanonicalMapping.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), 32
                    )
                }
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 a échoué (\(status))")
        return SymmetricKey(data: derived)
    }

    static func randomSalt() -> Data {
        Data((0..<saltLength).map { _ in UInt8.random(in: .min ... .max) })
    }

    // MARK: - Sceller / ouvrir

    /// Chiffre tout ce qui suit la première ligne ; celle-ci reste en clair.
    static func seal(_ content: String, key: SymmetricKey, salt: Data, iterations: Int = iterations,
                     nonce: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> String {
        let header = split(content).header
        // Tout ce qui suit le titre, saut de ligne compris : l'ouverture rend
        // exactement le texte scellé.
        let rest = String(content.dropFirst(header.count))
        let box = try AES.GCM.seal(Data(rest.utf8), using: key, nonce: nonce, authenticating: associatedData)
        guard let combined = box.combined else { throw Failure.malformed }
        return header + "\n" + prefix + salt.base64URL + "." + String(iterations) + "." + combined.base64URL
    }

    /// Contenu en clair (titre + corps) d'une note scellée.
    static func open(_ content: String, key: SymmetricKey) throws -> String {
        guard let parsed = parse(content) else { throw Failure.malformed }
        return try open(parsed, key: key)
    }

    static func open(_ parsed: Parsed, key: SymmetricKey) throws -> String {
        do {
            let box = try AES.GCM.SealedBox(combined: parsed.sealed)
            let body = try AES.GCM.open(box, using: key, authenticating: associatedData)
            guard let text = String(data: body, encoding: .utf8) else { throw Failure.malformed }
            return parsed.header + text
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.wrongKey
        }
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL: String) {
        var base64 = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
