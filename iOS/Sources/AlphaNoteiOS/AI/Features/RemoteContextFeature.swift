import Foundation

/// URL detection and web search features — iOS compatible (URLSession, no AppKit).
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

/// Remote context feature — fetches web content for AI enrichment.
/// Simplifié pour iOS (URLSession, pas de processus externes).
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

        var links = await searchWebLinksDuckDuckGo(query: cleanedQuery, limit: maxCount)
        if links.isEmpty {
            // Bing RSS search removed; DuckDuckGo only for iOS simplicity
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

    private func fetchWebText(from url: URL) async -> String? {
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
            return sanitizeHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
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

    private func resolvedSearchLink(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.hasPrefix("javascript:"),
              let url = URL(string: trimmed) else {
            return nil
        }
        return url
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
}
