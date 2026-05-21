import Foundation

enum URLDetector {
    static func extractURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return fallbackURLs(from: text)
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = detector.matches(in: text, options: [], range: range)
        var urls = matches.compactMap { $0.url }
            .filter { $0.scheme?.hasPrefix("http") == true }
        urls.append(contentsOf: fallbackURLs(from: text))

        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private static func fallbackURLs(from text: String) -> [URL] {
        let pattern = #"(?:\b(?:https?|htrp|htp|ttps)://[^\s<>()]+)|(?:\bwww\.[^\s<>()]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var result: [URL] = []
        var seen = Set<String>()

        for match in matches {
            let raw = nsText.substring(with: match.range)
            guard let normalized = normalizeURLLikeString(raw),
                  let url = URL(string: normalized) else { continue }
            let key = url.absoluteString
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(url)
        }

        return result
    }

    private static func normalizeURLLikeString(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)\"]}"))
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "([{\""))
        guard !value.isEmpty else { return nil }

        let lower = value.lowercased()
        if lower.hasPrefix("htrp://") || lower.hasPrefix("htp://") || lower.hasPrefix("ttps://") {
            if let range = value.range(of: "://") {
                value = "https://" + value[range.upperBound...]
            }
        } else if lower.hasPrefix("www.") {
            value = "https://" + value
        }

        guard value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") else {
            return nil
        }
        return value
    }
}

actor RemoteContextFeature {
    func contexts(from question: String, maxCount: Int = 2) async -> [NoteContext] {
        let urls = URLDetector.extractURLs(from: question)
        guard !urls.isEmpty else { return [] }

        var contexts: [NoteContext] = []
        for url in urls.prefix(maxCount) {
            if let context = await fetchContext(from: url) {
                contexts.append(context)
            }
        }
        return contexts
    }

    func webResearchContexts(query: String, maxCount: Int = 3) async -> [NoteContext] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return [] }

        var links = await searchWebLinksBingRSS(query: cleanedQuery, limit: maxCount)
        if links.isEmpty {
            links = await searchWebLinksDuckDuckGo(query: cleanedQuery, limit: maxCount)
        }
        guard !links.isEmpty else { return [] }

        var contexts: [NoteContext] = []
        let sourceList = links
            .prefix(maxCount)
            .map { "- \($0.absoluteString)" }
            .joined(separator: "\n")

        contexts.append(
            NoteContext(
                uuid: "web:search:\(cleanedQuery.hashValue)",
                title: "[WEB SEARCH] Résultats",
                content: "Requête: \(cleanedQuery)\nSources:\n\(sourceList)"
            )
        )

        for url in links.prefix(maxCount) {
            if let context = await fetchContext(from: url) {
                contexts.append(context)
            }
        }
        return contexts
    }

    func recipeIngredientItems(from question: String, maxItems: Int = 40) async -> [String] {
        let urls = URLDetector.extractURLs(from: question)
        guard !urls.isEmpty else { return [] }

        for url in urls {
            guard let html = await fetchHTML(url: url) else { continue }
            let fromJSONLD = extractRecipeIngredientsFromJSONLD(html)
            if !fromJSONLD.isEmpty {
                return Array(fromJSONLD.prefix(maxItems))
            }
            let fallback = extractRecipeIngredientsFromText(sanitizeHTML(html))
            if !fallback.isEmpty {
                return Array(fallback.prefix(maxItems))
            }
        }
        return []
    }

    private func fetchContext(from url: URL) async -> NoteContext? {
        if let text = await fetchWebText(from: url),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let host = url.host ?? url.absoluteString
            let encodedURL = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString
            return NoteContext(
                uuid: "url:\(encodedURL)",
                title: "[SOURCE URL] \(host)",
                content: clip(text, maxCharacters: 7000)
            )
        }
        return nil
    }

    private func sanitizeHTML(_ html: String) -> String {
        var text = html
        let patterns = [
            "(?is)<script[^>]*>.*?</script>",
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<noscript[^>]*>.*?</noscript>",
            "(?is)<[^>]+>"
        ]

        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        let entities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clip(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let index = text.index(text.startIndex, offsetBy: maxCharacters)
        return String(text[..<index])
    }

    private func fetchWebText(from url: URL) async -> String? {
        if let direct = await fetchWebTextViaHTTP(url), direct.count >= 300 {
            return direct
        }
        if let reader = readerMirrorURL(for: url),
           let mirrored = await fetchPlainText(url: reader),
           mirrored.count >= 120 {
            return mirrored
        }
        return await fetchWebTextViaHTTP(url)
    }

    private func fetchHTML(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 AlphaNote/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("fr-FR,fr;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func fetchWebTextViaHTTP(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 AlphaNote/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("fr-FR,fr;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let raw = String(data: data, encoding: .utf8) ?? ""
            let cleaned = sanitizeHTML(raw)
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func fetchPlainText(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 AlphaNote/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain,text/html;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            let raw = String(data: data, encoding: .utf8) ?? ""
            return raw
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func readerMirrorURL(for url: URL) -> URL? {
        URL(string: "https://r.jina.ai/\(url.absoluteString)")
    }

    private func searchWebLinksDuckDuckGo(query: String, limit: Int) async -> [URL] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("AlphaNote/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }

            let html = String(data: data, encoding: .utf8) ?? ""
            return extractSearchResultLinks(from: html, limit: limit)
        } catch {
            return []
        }
    }

    private func searchWebLinksBingRSS(query: String, limit: Int) async -> [URL] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.bing.com/search?q=\(encoded)&format=rss") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("AlphaNote/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }

            let xml = String(data: data, encoding: .utf8) ?? ""
            return extractBingRSSLinks(from: xml, limit: limit)
        } catch {
            return []
        }
    }

    private func extractSearchResultLinks(from html: String, limit: Int) -> [URL] {
        guard let regex = try? NSRegularExpression(
            pattern: #"href="([^"]+)""#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let nsHTML = html as NSString
        let matches = regex.matches(
            in: html,
            options: [],
            range: NSRange(location: 0, length: nsHTML.length)
        )

        var urls: [URL] = []
        var seen = Set<String>()

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let value = nsHTML.substring(with: match.range(at: 1))
            guard let resolved = resolvedSearchLink(value) else { continue }
            let key = resolved.absoluteString
            if seen.contains(key) { continue }
            seen.insert(key)
            urls.append(resolved)
            if urls.count >= limit {
                break
            }
        }

        return urls
    }

    private func extractBingRSSLinks(from xml: String, limit: Int) -> [URL] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<item\b[^>]*>.*?<link>(.*?)</link>.*?</item>"#
        ) else {
            return []
        }

        let nsXML = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: nsXML.length))
        var urls: [URL] = []
        var seen = Set<String>()

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let raw = nsXML.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let url = URL(string: raw), isValidExternalURL(url) else { continue }
            let key = url.absoluteString
            if seen.contains(key) { continue }
            seen.insert(key)
            urls.append(url)
            if urls.count >= limit { break }
        }

        return urls
    }

    private func resolvedSearchLink(_ rawHref: String) -> URL? {
        let decoded = rawHref
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decoded.isEmpty else { return nil }

        if decoded.hasPrefix("http://") || decoded.hasPrefix("https://") {
            guard let url = URL(string: decoded),
                  isValidExternalURL(url) else { return nil }
            return url
        }

        if decoded.hasPrefix("//") {
            guard let url = URL(string: "https:\(decoded)"),
                  isValidExternalURL(url) else { return nil }
            return url
        }

        if decoded.hasPrefix("/l/?"),
           let components = URLComponents(string: "https://duckduckgo.com\(decoded)"),
           let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value?.removingPercentEncoding,
           let target = URL(string: uddg),
           isValidExternalURL(target) {
            return target
        }

        return nil
    }

    private func isValidExternalURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased() else { return false }
        if host.contains("duckduckgo.com") { return false }
        return true
    }

    private func extractRecipeIngredientsFromJSONLD(_ html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        ) else {
            return []
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var ingredients: [String] = []
        var seen = Set<String>()

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let raw = nsHTML.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }

            let normalized = raw
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&amp;", with: "&")

            guard let data = normalized.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }

            collectRecipeIngredients(from: object, into: &ingredients, seen: &seen)
        }

        return ingredients
    }

    private func collectRecipeIngredients(from object: Any, into ingredients: inout [String], seen: inout Set<String>) {
        if let dictionary = object as? [String: Any] {
            if let value = dictionary["recipeIngredient"] {
                if let items = value as? [Any] {
                    for item in items {
                        if let text = normalizedIngredientText(from: item),
                           !text.isEmpty,
                           !seen.contains(text.lowercased()) {
                            seen.insert(text.lowercased())
                            ingredients.append(text)
                        }
                    }
                } else if let single = normalizedIngredientText(from: value),
                          !single.isEmpty,
                          !seen.contains(single.lowercased()) {
                    seen.insert(single.lowercased())
                    ingredients.append(single)
                }
            }

            for value in dictionary.values {
                collectRecipeIngredients(from: value, into: &ingredients, seen: &seen)
            }
        } else if let array = object as? [Any] {
            for item in array {
                collectRecipeIngredients(from: item, into: &ingredients, seen: &seen)
            }
        }
    }

    private func normalizedIngredientText(from value: Any) -> String? {
        if let text = value as? String {
            let cleaned = text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        }

        if let dictionary = value as? [String: Any] {
            if let name = dictionary["name"] as? String, !name.isEmpty {
                return name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let val = dictionary["value"] as? String, !val.isEmpty {
                return val.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    private func extractRecipeIngredientsFromText(_ text: String) -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result: [String] = []
        var seen = Set<String>()
        var isInIngredientSection = false

        for line in lines {
            let folded = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

            if folded.contains("ingredient") {
                isInIngredientSection = true
                continue
            }

            if isInIngredientSection {
                if folded.contains("preparation") || folded.contains("etape") || folded.contains("instructions") {
                    break
                }
                if let regex = try? NSRegularExpression(pattern: #"^\s*(?:[-*•]\s+|\d+[.)]\s+)"#),
                   regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    let cleaned = line.replacingOccurrences(
                        of: #"^\s*(?:[-*•]\s+|\d+[.)]\s+)"#,
                        with: "",
                        options: .regularExpression
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = cleaned.lowercased()
                    if !cleaned.isEmpty, !seen.contains(key) {
                        seen.insert(key)
                        result.append(cleaned)
                    }
                }
            }
        }

        return result
    }
}
