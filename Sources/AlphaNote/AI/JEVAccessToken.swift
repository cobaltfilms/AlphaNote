import Foundation

/// Jeton de service Cloudflare Access : le serveur JEV publié
/// (https://jev.cobaltfilms.be) refuse toute requête qui ne le présente pas.
/// L'identifiant reste dans les réglages, le secret dans le trousseau.
struct JEVAccessToken: Sendable, Equatable {
    static let clientIDKey = "jevAccessClientID"
    private static let keychainServer = "cloudflare-access"

    let clientID: String
    let clientSecret: String

    var headers: [String: String] {
        ["CF-Access-Client-Id": clientID, "CF-Access-Client-Secret": clientSecret]
    }

    /// Nil tant que l'identifiant ou le secret manque : JEV est alors appelé
    /// sans jeton (serveur sur le réseau local ou Tailscale).
    static func load(defaults: UserDefaults = .standard) -> JEVAccessToken? {
        let id = (defaults.string(forKey: clientIDKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty,
              let secret = try? KeychainService.shared.readPassword(serverURL: keychainServer, username: id),
              !secret.isEmpty else {
            return nil
        }
        return JEVAccessToken(clientID: id, clientSecret: secret)
    }

    static func storedSecret(clientID: String) -> String {
        (try? KeychainService.shared.readPassword(serverURL: keychainServer, username: clientID)) ?? ""
    }

    static func save(clientID: String, secret: String, defaults: UserDefaults = .standard) {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = defaults.string(forKey: clientIDKey) ?? ""
        if !previous.isEmpty, previous != id {
            try? KeychainService.shared.deletePassword(serverURL: keychainServer, username: previous)
        }
        defaults.set(id, forKey: clientIDKey)
        guard !id.isEmpty else { return }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? KeychainService.shared.deletePassword(serverURL: keychainServer, username: id)
        } else {
            try? KeychainService.shared.savePassword(trimmed, serverURL: keychainServer, username: id)
        }
    }
}
