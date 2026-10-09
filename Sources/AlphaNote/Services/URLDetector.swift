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
