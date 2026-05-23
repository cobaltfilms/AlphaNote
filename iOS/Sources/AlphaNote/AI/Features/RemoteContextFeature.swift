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
    enum URLProbeOutcome: Sendable {
        case listItemsFound(count: Int)
        case accessibleNoListItems
        case unreachable
    }

    func contexts(from question: String, maxCount: Int = 2) async -> [NoteContext] {
        let urls = URLDetector.extractURLs(from: question)
        return await contexts(from: urls, maxCount: maxCount)
    }

    func contexts(from urls: [URL], maxCount: Int = 2) async -> [NoteContext] {
        guard !urls.isEmpty else { return [] }

        var contexts: [NoteContext] = []
        for url in uniqueURLs(urls).prefix(maxCount) {
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
        return await recipeIngredientItems(from: urls, maxItems: maxItems)
    }

    func recipeIngredientItems(from urls: [URL], maxItems: Int = 40) async -> [String] {
        guard !urls.isEmpty else { return [] }

        for url in uniqueURLs(urls) {
            if let html = await fetchHTML(url: url) {
                let fromJSONLD = extractRecipeIngredientsFromJSONLD(html)
                if !fromJSONLD.isEmpty {
                    return Array(fromJSONLD.prefix(maxItems))
                }
                let fallback = extractRecipeIngredientsFromText(sanitizeHTML(html))
                if !fallback.isEmpty {
                    return Array(fallback.prefix(maxItems))
                }
            }

            if let webText = await fetchWebText(from: url) {
                let fallback = extractRecipeIngredientsFromText(webText)
                if !fallback.isEmpty {
                    return Array(fallback.prefix(maxItems))
                }
            }
        }
        return []
    }

    func listItems(from urls: [URL], query: String, maxItems: Int = 40) async -> [String] {
        guard !urls.isEmpty else { return [] }
        let ingredientQuery = isIngredientStyleQuery(query)

        for url in uniqueURLs(urls) {
            var sources: [String] = []
            if let html = await fetchHTML(url: url) {
                let focusedHTML = extractPrimaryContentHTML(from: html)
                if ingredientQuery {
                    let fromJSONLD = extractRecipeIngredientsFromJSONLD(focusedHTML)
                    if !fromJSONLD.isEmpty {
                        return Array(fromJSONLD.prefix(maxItems))
                    }
                }
                sources.append(sanitizeHTML(focusedHTML))
            }
            if let webText = await fetchWebText(from: url) {
                sources.append(webText)
            }

            for source in sources {
                if ingredientQuery {
                    let recipeItems = extractRecipeIngredientsFromText(source)
                    if !recipeItems.isEmpty {
                        return Array(recipeItems.prefix(maxItems))
                    }
                }

                let genericItems = extractGenericListItems(from: source, query: query, maxItems: maxItems)
                if !genericItems.isEmpty {
                    return genericItems
                }
            }
        }

        return []
    }

    func probeRecipeURLs(_ urls: [URL], query: String = "", maxCount: Int = 3) async -> [String] {
        let targets = Array(uniqueURLs(urls).prefix(maxCount))
        guard !targets.isEmpty else { return [] }

        var lines: [String] = []
        for url in targets {
            let host = url.host ?? url.absoluteString
            let outcome = await probeRecipeURL(url, query: query)
            switch outcome {
            case let .listItemsFound(count):
                lines.append("- \(host): OK, \(count) élément(s) détecté(s)")
            case .accessibleNoListItems:
                lines.append("- \(host): URL accessible, mais aucun élément de liste détecté")
            case .unreachable:
                lines.append("- \(host): URL non accessible depuis l'app")
            }
        }
        return lines
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.absoluteString
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(url)
        }
        return result
    }

    private func probeRecipeURL(_ url: URL, query: String) async -> URLProbeOutcome {
        if let html = await fetchHTML(url: url) {
            let focusedHTML = extractPrimaryContentHTML(from: html)
            let jsonLDCount = extractRecipeIngredientsFromJSONLD(focusedHTML).count
            let normalized = sanitizeHTML(focusedHTML)
            let textCount = extractRecipeIngredientsFromText(normalized).count
            let genericCount = extractGenericListItems(from: normalized, query: query, maxItems: 20).count
            let total = max(jsonLDCount, max(textCount, genericCount))
            if total > 0 {
                return .listItemsFound(count: total)
            }
            if let webText = await fetchWebText(from: url),
               !webText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let generic = extractGenericListItems(from: webText, query: query, maxItems: 20).count
                if generic > 0 {
                    return .listItemsFound(count: generic)
                }
                return .accessibleNoListItems
            }
            return .unreachable
        }

        if let webText = await fetchWebText(from: url),
           !webText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let textCount = extractRecipeIngredientsFromText(webText).count
            let genericCount = extractGenericListItems(from: webText, query: query, maxItems: 20).count
            let total = max(textCount, genericCount)
            if total > 0 {
                return .listItemsFound(count: total)
            }
            return .accessibleNoListItems
        }

        return .unreachable
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
        text = text.replacingOccurrences(
            of: #"(?is)<li[^>]*>"#,
            with: "\n- ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?is)</li>"#,
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?is)</?(?:br|p|div|li|ul|ol|h[1-6]|section|article|tr|td|th)[^>]*>"#,
            with: "\n",
            options: .regularExpression
        )

        let stripPatterns = [
            "(?is)<script[^>]*>.*?</script>",
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<noscript[^>]*>.*?</noscript>",
            "(?is)<[^>]+>"
        ]

        for pattern in stripPatterns {
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

        text = decodeNumericHTMLEntities(text)

        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"[ ]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
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
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: #"[ ]{2,}"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
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
                if isIngredientSectionTerminator(folded) {
                    break
                }

                let cleaned = line.replacingOccurrences(
                    of: #"^\s*(?:[-*•]\s+|\d+[.)]\s+)"#,
                    with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                guard isLikelyIngredientLine(cleaned) else { continue }

                let key = cleaned.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(cleaned)
                }
            }
        }

        return result
    }

    private func isIngredientSectionTerminator(_ foldedLine: String) -> Bool {
        foldedLine.contains("preparation") ||
            foldedLine.contains("etape") ||
            foldedLine.contains("instructions") ||
            foldedLine.contains("cuisson") ||
            foldedLine.contains("realisation")
    }

    private func isLikelyIngredientLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let folded = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if folded.hasPrefix("ingredients") || folded.hasPrefix("ingredient") {
            return false
        }
        if folded.hasPrefix("pour ") || folded.hasPrefix("temps ") || folded.hasPrefix("servir ") {
            return false
        }

        let words = trimmed.split(whereSeparator: \.isWhitespace).count
        if words > 18 {
            return false
        }

        if folded.hasPrefix("facultatif") {
            return true
        }

        let hasQuantity = trimmed.range(
            of: #"(?i)\b\d+[.,]?\d*\s*(g|kg|mg|ml|cl|l|cuill(?:ere|ères?)|c\.?\s*[àa]\s*caf[eé]|gousse?s?|branche?s?|pinc[ée]e?s?|bo[iî]te?s?|sachet?s?)\b|^\d+[.,]?\d*\b"#,
            options: .regularExpression
        ) != nil
        if hasQuantity {
            return true
        }

        let shortFoodLine = words <= 6 &&
            folded.range(of: #"[a-zàâçéèêëîïôûùüÿñæœ]"#, options: .regularExpression) != nil &&
            !folded.contains("http")
        if shortFoodLine {
            return true
        }

        return false
    }

    private func extractGenericListItems(from text: String, query: String, maxItems: Int) -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let keywords = queryKeywords(from: query)
        let bulletRegex = #"^\s*(?:[-*•]\s+|\d+[.)]\s+)"#
        var candidates: [(line: String, score: Int)] = []
        var seen = Set<String>()

        for line in lines {
            let folded = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if folded.count < 2 || folded.count > 160 { continue }
            if folded.hasPrefix("http://") || folded.hasPrefix("https://") { continue }
            if isLikelyNavigationNoise(folded) { continue }

            var score = 0
            let cleaned = line.replacingOccurrences(of: bulletRegex, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if let componentList = componentSubitems(from: cleaned),
               !componentList.isEmpty {
                for item in componentList {
                    let key = item.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    if seen.contains(key) { continue }
                    seen.insert(key)
                    candidates.append((item, 6))
                }
                continue
            }

            if line.range(of: bulletRegex, options: .regularExpression) != nil {
                score += 4
            }
            if cleaned.split(whereSeparator: \.isWhitespace).count <= 16 {
                score += 1
            }
            if keywords.contains(where: { folded.contains($0) }) {
                score += 2
            }
            if cleaned.range(of: #"(?i)\b(true?nas|unraid|omv|openmediavault|proxmox|casaos|zimaos|umbrel|hexos|zfs|docker|ram|ssd|hdd|nvme|carte mere|motherboard|cpu|processeur)\b"#, options: .regularExpression) != nil {
                score += 2
            }

            guard score >= 3 else { continue }
            let key = cleaned.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if seen.contains(key) { continue }
            seen.insert(key)
            candidates.append((cleaned, score))
        }

        let sorted = candidates
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.line.count < rhs.line.count
                }
                return lhs.score > rhs.score
            }
            .map(\.line)

        return Array(sorted.prefix(maxItems))
    }

    private func queryKeywords(from query: String) -> [String] {
        let stopwords: Set<String> = [
            "liste", "moi", "les", "des", "de", "du", "la", "le", "un", "une",
            "pour", "avec", "selon", "site", "web", "internet", "ce", "cet",
            "cette", "en", "et", "a", "à", "sur", "dans", "2026"
        ]
        let normalized = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s\-]"#, with: " ", options: .regularExpression)

        return normalized
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in
                token.count >= 3 && !stopwords.contains(token)
            }
    }

    private func isIngredientStyleQuery(_ query: String) -> Bool {
        let folded = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return folded.contains("ingredient") || folded.contains("recette") || folded.contains("cuisine")
    }

    private func isLikelyNavigationNoise(_ foldedLine: String) -> Bool {
        let markers = [
            "accueil", "commentaires", "etiquettes", "étiquettes", "similaire", "image:",
            "search button", "en train de lire", "copyright", "tutos", "loisirs",
            "forum", "test du nas", "tous les articles", "guide d'achat", "produits nas",
            "os / applications pour nas", "nas & stockage"
        ]
        return markers.contains(where: { foldedLine.contains($0) })
    }

    private func extractPrimaryContentHTML(from html: String) -> String {
        let candidates = [
            #"(?is)<article\b[^>]*>(.*?)</article>"#,
            #"(?is)<main\b[^>]*>(.*?)</main>"#,
            #"(?is)<div\b[^>]*class=["'][^"']*(?:entry-content|post-content|article-content)[^"']*["'][^>]*>(.*?)</div>"#
        ]

        for pattern in candidates {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html) {
                let segment = String(html[range])
                if segment.count >= 300 {
                    return segment
                }
            }
        }

        return html
    }

    private func decodeNumericHTMLEntities(_ text: String) -> String {
        let pattern = #"&#(x[0-9a-fA-F]+|\d+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let token = nsText.substring(with: match.range(at: 1))
            let value: UInt32?
            if token.lowercased().hasPrefix("x") {
                value = UInt32(token.dropFirst(), radix: 16)
            } else {
                value = UInt32(token)
            }
            guard let scalarValue = value, let scalar = UnicodeScalar(scalarValue) else { continue }
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: String(Character(scalar)))
            }
        }
        return result
    }

    private func componentSubitems(from line: String) -> [String]? {
        let folded = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard folded.contains("composant") || folded.contains("materiel") || folded.contains("matériel") else {
            return nil
        }
        guard let start = line.firstIndex(of: "("), let end = line.firstIndex(of: ")"), start < end else {
            return nil
        }
        let content = String(line[line.index(after: start)..<end])
        let rawParts = content
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !rawParts.isEmpty else { return nil }
        return rawParts
    }
}
