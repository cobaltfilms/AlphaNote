import Foundation

/// Client du serveur de décision « JEV » (jevai.net) — port fidèle de
/// cockpit/src/lib/jev.ts.
///
/// Le serveur **classe** selon un schéma strict, il ne rédige jamais.
/// Règles tirées de l'étalonnage cockpit, à ne pas oublier :
///   · le modèle répond « sûr à 99 % » même quand il se trompe — la
///     probabilité ne sert jamais, seule, à décider ;
///   · la qualité des descriptions du schéma fait presque tout le résultat ;
///   · une réponse incomplète est un échec, pas un demi-succès ;
///   · un serveur injoignable n'empêche jamais AlphaNote de tourner : il
///     retire seulement une aide, et l'écran le dit.

enum JEVValue: Equatable, Sendable {
    case string(String)
    case boolean(Bool)
    case integer(Int)
    case number(Double)
}

enum JEVField: Sendable {
    case string(choices: [String], description: String)
    case boolean(description: String)
    case integer(description: String, minimum: Int, maximum: Int)
    case number(description: String, minimum: Double, maximum: Double)

    var description: String {
        switch self {
        case let .string(_, description): return description
        case let .boolean(description): return description
        case let .integer(description, _, _): return description
        case let .number(description, _, _): return description
        }
    }

    fileprivate var json: [String: Any] {
        switch self {
        case let .string(choices, description):
            return ["type": "enum", "choices": choices, "description": description]
        case let .boolean(description):
            return ["type": "boolean", "description": description]
        case let .integer(description, minimum, maximum):
            return ["type": "integer", "description": description, "minimum": minimum, "maximum": maximum]
        case let .number(description, minimum, maximum):
            return ["type": "number", "description": description, "minimum": minimum, "maximum": maximum]
        }
    }
}

typealias JEVSchema = [String: JEVField]
typealias JEVDecision = [String: JEVValue]

enum JEVOutcome<T>: Sendable where T: Sendable {
    case ok(T)
    case erreur(String)
}

struct JEVConfig: Sendable {
    let url: String
    let delaiMs: Int
    var access: JEVAccessToken? = nil

    /// En-têtes ajoutés à chaque requête (jeton Cloudflare Access).
    var headers: [String: String] { access?.headers ?? [:] }
}

protocol JEVTransport: Sendable {
    func post(url: URL, body: Data, delaiMs: Int, headers: [String: String]) async throws -> Data
}

struct URLSessionJEVTransport: JEVTransport {
    func post(url: URL, body: Data, delaiMs: Int, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body
        request.timeoutInterval = TimeInterval(delaiMs) / 1000
        let (data, response) = try await URLSession.shared.data(for: request)
        // Sans jeton valide, Cloudflare Access renvoie vers sa page de connexion.
        if response.url?.host?.hasSuffix("cloudflareaccess.com") == true {
            throw JEVTransportError.http(status: 403)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw JEVTransportError.http(status: http.statusCode)
        }
        return data
    }
}

enum JEVTransportError: Error {
    case http(status: Int)

    func message(serveur: String) -> String {
        switch self {
        case .http(401), .http(403):
            return "Accès refusé par \(serveur) : vérifie le jeton d'accès dans les réglages IA."
        case let .http(status):
            return "\(serveur.prefix(1).uppercased() + serveur.dropFirst()) a répondu \(status)."
        }
    }
}

enum JEVClient {
    /// Configuration lue à chaque appel : nil quand aucun serveur de décision
    /// n'est configuré. AlphaNote s'en passe alors, et le dit à l'écran.
    static func config() -> JEVConfig? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: AISettingsKeys.jevURL),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let delai = defaults.object(forKey: AISettingsKeys.jevDelaiMs) as? Int ?? AISettingsKeys.jevDelaiMsDefault
        return JEVConfig(
            url: raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/+$", with: "", options: .regularExpression),
            delaiMs: delai > 0 ? delai : AISettingsKeys.jevDelaiMsDefault,
            access: JEVAccessToken.load(defaults: defaults)
        )
    }

    /// Le serveur refuse un champ enum sans description (HTTP 400). Mieux vaut
    /// le voir ici, où le message dit lequel, que dans une erreur réseau opaque.
    static func verifierSchema(_ schema: JEVSchema) -> String? {
        if schema.isEmpty {
            return "Le schéma ne décrit aucun champ."
        }
        for (nom, champ) in schema {
            if champ.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Le champ « \(nom) » n'a pas de description."
            }
            switch champ {
            case let .string(choices, _):
                if choices.count < 2 {
                    return "Le champ « \(nom) » doit proposer au moins deux valeurs."
                }
            case let .integer(description, minimum, maximum):
                _ = description
                if minimum >= maximum {
                    return "Le champ « \(nom) » doit borner ses valeurs."
                }
            case let .number(_, minimum, maximum):
                if minimum >= maximum {
                    return "Le champ « \(nom) » doit borner ses valeurs."
                }
            case .boolean:
                break
            }
        }
        return nil
    }

    /// Classe des fragments en un seul appel. Une réponse incomplète est un
    /// échec, pas un demi-succès : mieux vaut retomber franchement sur les
    /// mots-clés, et le dire.
    static func decider(
        instructions: String,
        schema: JEVSchema,
        fragments: [String],
        transport: JEVTransport = URLSessionJEVTransport()
    ) async -> JEVOutcome<[JEVDecision]> {
        guard let config = config() else {
            return .erreur("Aucun serveur de décision configuré.")
        }
        return await decider(config: config, instructions: instructions, schema: schema, fragments: fragments, transport: transport)
    }

    static func decider(
        config: JEVConfig,
        instructions: String,
        schema: JEVSchema,
        fragments: [String],
        transport: JEVTransport = URLSessionJEVTransport()
    ) async -> JEVOutcome<[JEVDecision]> {
        if fragments.isEmpty {
            return .ok([])
        }
        if let faute = verifierSchema(schema) {
            return .erreur(faute)
        }

        let body: [String: Any] = [
            "instructions": instructions,
            "schema": schema.mapValues { $0.json },
            "contexts": fragments,
            "temperature": 1.0
        ]

        guard let url = URL(string: config.url + "/v1/decision") else {
            return .erreur("L'URL du serveur de décision est invalide.")
        }

        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            let data = try await transport.post(url: url, body: bodyData, delaiMs: config.delaiMs, headers: config.headers)
            let brut = try JSONSerialization.jsonObject(with: data)
            let rendus = (brut as? [String: Any])?["results"] as? [Any]
            let rendusCount = rendus?.count ?? 0
            if rendusCount < fragments.count {
                return .erreur("Le serveur de décision n'a répondu que pour \(rendusCount) fragment(s) sur \(fragments.count).")
            }
            return .ok(lireReponse(brut, schema: schema, attendus: fragments.count))
        } catch let error as JEVTransportError {
            return .erreur(error.message(serveur: "le serveur de décision"))
        } catch {
            return .erreur("Le serveur de décision n'a pas répondu.")
        }
    }

    /// Remet la réponse à plat : une décision par fragment, dans l'ordre des
    /// fragments envoyés. Un champ manquant ou d'un type inattendu est ignoré —
    /// l'appelant traite l'absence comme il traite un serveur muet.
    static func lireReponse(_ brut: Any, schema: JEVSchema, attendus: Int) -> [JEVDecision] {
        let results = (brut as? [String: Any])?["results"] as? [[String: Any]] ?? []
        var out: [JEVDecision] = []
        for index in 0..<attendus {
            let decisionBrute = index < results.count ? (results[index]["decision"] as? [String: Any] ?? [:]) : [:]
            var decision: JEVDecision = [:]
            for (nom, champ) in schema {
                guard let valeur = decisionBrute[nom] else { continue }
                switch champ {
                case let .string(choices, _):
                    if let chaine = valeur as? String, choices.contains(chaine) {
                        decision[nom] = .string(chaine)
                    }
                case .boolean:
                    if let booleen = valeur as? Bool {
                        decision[nom] = .boolean(booleen)
                    }
                case .integer:
                    if let entier = valeur as? Int {
                        decision[nom] = .integer(entier)
                    } else if let nombre = valeur as? Double {
                        decision[nom] = .integer(Int(nombre.rounded()))
                    }
                case .number:
                    if let nombre = valeur as? Double {
                        decision[nom] = .number(nombre)
                    } else if let entier = valeur as? Int {
                        decision[nom] = .number(Double(entier))
                    }
                }
            }
            out.append(decision)
        }
        return out
    }
}
