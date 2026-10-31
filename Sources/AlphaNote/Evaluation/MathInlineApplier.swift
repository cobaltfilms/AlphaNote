import Foundation

/// Résultats math écrits dans le texte : calcule les remplacements ciblés (la
/// queue après le premier « = » de chaque ligne qui change), jamais le texte
/// entier. Logique pure, partagée par l'éditeur macOS (NSTextView) et iOS
/// (UITextView) ; même rôle que MathInlineApplier sur Android.
enum MathInlineApplier {
    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
    }

    /// Remplacements à appliquer, dans l'ordre inverse du texte (les plages
    /// restent valides en les appliquant une à une). Avec `caret`, une ligne dont
    /// le résultat contient le curseur est laissée telle quelle : l'utilisateur
    /// y écrit, on attend qu'il en sorte.
    static func edits(for content: String, caret: Int?, evaluator: MathDocumentEvaluator) -> [Edit] {
        let outcomes = evaluator.evaluate(content: content).filter(\.changed)
        guard !outcomes.isEmpty else { return [] }

        let nsContent = content as NSString
        var lineStarts: [Int] = [0]
        nsContent.enumerateSubstrings(in: NSRange(location: 0, length: nsContent.length), options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            lineStarts.append(enclosing.location + enclosing.length)
        }

        var edits: [Edit] = []
        for outcome in outcomes.reversed() {
            guard outcome.index < lineStarts.count else { continue }
            let lineStart = lineStarts[outcome.index]
            let original = outcome.original as NSString
            let lineRange = NSRange(location: lineStart, length: original.length)
            guard NSMaxRange(lineRange) <= nsContent.length else { continue }

            let equalIndex = original.range(of: "=").location
            guard equalIndex != NSNotFound else { continue }
            let tailRange = NSRange(location: lineStart + equalIndex + 1, length: original.length - equalIndex - 1)

            let transformed = outcome.transformed as NSString
            let transformedEqual = transformed.range(of: "=").location
            guard transformedEqual != NSNotFound else { continue }
            let newTail = transformed.substring(from: transformedEqual + 1)

            // Juste après « = », on remplace ; à l'intérieur d'un résultat, non.
            if let caret, tailRange.length > 0,
               caret > tailRange.location, caret <= NSMaxRange(tailRange) {
                continue
            }
            edits.append(Edit(range: tailRange, replacement: newTail))
        }
        return edits
    }

    /// Position du curseur après les remplacements (donnés dans l'ordre inverse).
    static func adjustedCaret(_ caret: Int, after edits: [Edit]) -> Int {
        var location = caret
        for edit in edits where edit.range.location < caret {
            location += (edit.replacement as NSString).length - edit.range.length
        }
        return max(0, location)
    }

    /// Applique les remplacements à une chaîne (tests, et éditeurs sans undo fin).
    static func apply(_ edits: [Edit], to content: String) -> String {
        let result = NSMutableString(string: content)
        for edit in edits { // déjà dans l'ordre inverse
            result.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return result as String
    }
}
