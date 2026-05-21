import Foundation

enum URLDetector {
    static func extractURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = detector.matches(in: text, options: [], range: range)
        let urls = matches.compactMap { $0.url }
            .filter { $0.scheme?.hasPrefix("http") == true }

        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
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

    private func fetchContext(from url: URL) async -> NoteContext? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("AlphaNote/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let raw = String(data: data, encoding: .utf8) ?? ""
            let cleaned = sanitizeHTML(raw)
            let clipped = clip(cleaned, maxCharacters: 7000)
            guard !clipped.isEmpty else { return nil }

            let host = url.host ?? url.absoluteString
            return NoteContext(
                uuid: "url:\(url.absoluteString.hashValue)",
                title: "[SOURCE URL] \(host)",
                content: clipped
            )
        } catch {
            return nil
        }
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
}
