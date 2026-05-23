import Foundation

enum ListModeFormatter {
    static func normalizeForListMode(content: String, forceListHeader: Bool) -> String {
        let rawLines = content.components(separatedBy: .newlines)
        let nonEmpty = rawLines.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        let lower = nonEmpty.lowercased()

        let hasListHeader = lower == "list" || lower.hasPrefix("list:")

        var headerLine = hasListHeader ? nonEmpty : "list"
        if forceListHeader && !hasListHeader {
            headerLine = "list"
        }

        let bodySource: [String]
        if hasListHeader, let firstIndex = rawLines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lower
        }) {
            bodySource = Array(rawLines.dropFirst(firstIndex + 1))
        } else {
            bodySource = rawLines
        }

        var bodyLines: [String] = []
        for line in bodySource {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if isComment(trimmed) || isHeading(trimmed) {
                bodyLines.append(trimmed)
                continue
            }

            let commaParts = trimmed
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if commaParts.isEmpty {
                bodyLines.append(trimmed)
            } else {
                bodyLines.append(contentsOf: commaParts)
            }
        }

        if headerLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "list",
           bodyLines.count == 1,
           bodyLines[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "list" {
            bodyLines.removeAll()
        }

        if bodyLines.isEmpty {
            return headerLine
        }

        return ([headerLine] + bodyLines).joined(separator: "\n")
    }

    static func isListHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "list" || trimmed.hasPrefix("list:")
    }

    static func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("//")
    }

    static func isHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("###") || trimmed.hasPrefix("##") || trimmed.hasPrefix("#")
    }
}
