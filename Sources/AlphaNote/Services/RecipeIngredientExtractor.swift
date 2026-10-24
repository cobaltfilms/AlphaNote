import Foundation

/// Lit la liste d'ingrédients d'une page de recette, sans IA : la plupart des
/// sites publient la recette en données structurées schema.org
/// (`recipeIngredient`, en JSON-LD ou en microdonnées). On lit cette liste
/// telle quelle ; une page qui n'en publie pas est un échec franc.
enum RecipeIngredientExtractor {

    struct Recipe: Equatable {
        let title: String?
        let ingredients: [String]
    }

    enum Failure: Error, Equatable {
        case http(Int)
        case unreadable
        case noStructuredRecipe

        var message: String {
            switch self {
            case let .http(status): return "la page répond HTTP \(status)"
            case .unreadable: return "page illisible"
            case .noStructuredRecipe: return "aucune liste d'ingrédients structurée sur la page"
            }
        }
    }

    static let maxIngredients = 60

    // MARK: - Réseau

    static func fetch(_ url: URL, timeout: TimeInterval = 15) async -> Result<Recipe, Failure> {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        // Certains sites refusent les clients sans User-Agent de navigateur.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("fr,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(.http(http.statusCode))
            }
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return .failure(.unreadable)
            }
            guard let recipe = extract(fromHTML: html) else {
                return .failure(.noStructuredRecipe)
            }
            return .success(recipe)
        } catch {
            return .failure(.unreadable)
        }
    }

    // MARK: - Analyse (pure)

    static func extract(fromHTML html: String) -> Recipe? {
        if let recipe = extractFromJSONLD(html) {
            return recipe
        }
        return extractFromMicrodata(html)
    }

    private static func extractFromJSONLD(_ html: String) -> Recipe? {
        let pattern = #"<script[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsHTML = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            let raw = nsHTML.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let recipe = findRecipe(in: json) else { continue }
            return recipe
        }
        return nil
    }

    /// Parcourt le JSON-LD (objets, tableaux, `@graph`) jusqu'au premier
    /// objet `Recipe` qui porte des ingrédients.
    private static func findRecipe(in object: Any) -> Recipe? {
        if let array = object as? [Any] {
            for element in array {
                if let recipe = findRecipe(in: element) { return recipe }
            }
            return nil
        }
        guard let dictionary = object as? [String: Any] else { return nil }

        if isRecipeType(dictionary["@type"]) {
            let rawItems = (dictionary["recipeIngredient"] ?? dictionary["ingredients"]) as? [Any] ?? []
            let items = clean(rawItems.compactMap { $0 as? String })
            if !items.isEmpty {
                let title = (dictionary["name"] as? String).map(cleanText).flatMap { $0.isEmpty ? nil : $0 }
                return Recipe(title: title, ingredients: items)
            }
        }
        for value in dictionary.values {
            if let recipe = findRecipe(in: value) { return recipe }
        }
        return nil
    }

    private static func isRecipeType(_ value: Any?) -> Bool {
        if let type = value as? String {
            return type.lowercased().hasSuffix("recipe")
        }
        if let types = value as? [Any] {
            return types.contains { ($0 as? String)?.lowercased().hasSuffix("recipe") == true }
        }
        return false
    }

    private static func extractFromMicrodata(_ html: String) -> Recipe? {
        // <meta itemprop="recipeIngredient" content="…"> ou
        // <li itemprop="recipeIngredient">…</li> (balises internes possibles).
        let patterns = [
            #"<meta[^>]*itemprop\s*=\s*["']recipeIngredient["'][^>]*content\s*=\s*["']([^"']*)["']"#,
            #"<(\w+)[^>]*itemprop\s*=\s*["']recipeIngredient["'][^>]*>(.*?)</\1>"#
        ]
        var items: [String] = []
        let nsHTML = html as NSString
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
                items.append(nsHTML.substring(with: match.range(at: index == 0 ? 1 : 2)))
            }
        }
        let cleaned = clean(items)
        return cleaned.isEmpty ? nil : Recipe(title: nil, ingredients: cleaned)
    }

    // MARK: - Nettoyage

    private static func clean(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            let text = cleanText(item)
            guard !text.isEmpty else { continue }
            let key = text.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(text)
            if result.count == maxIngredients { break }
        }
        return result
    }

    static func cleanText(_ raw: String) -> String {
        let withoutTags = raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeEntities(withoutTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë", "agrave": "à",
        "acirc": "â", "ccedil": "ç", "icirc": "î", "iuml": "ï", "ocirc": "ô",
        "ucirc": "û", "ugrave": "ù", "oelig": "œ", "deg": "°", "frac12": "½",
        "frac14": "¼", "frac34": "¾", "rsquo": "’", "lsquo": "‘", "hellip": "…",
        "times": "×"
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        guard let regex = try? NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z0-9]+);"#) else {
            return text
        }
        let nsText = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            result += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let entity = nsText.substring(with: match.range(at: 1))
            var replacement: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                replacement = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if entity.hasPrefix("#") {
                replacement = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = namedEntities[entity.lowercased()]
            }
            result += replacement ?? nsText.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        result += nsText.substring(from: cursor)
        return result
    }
}
