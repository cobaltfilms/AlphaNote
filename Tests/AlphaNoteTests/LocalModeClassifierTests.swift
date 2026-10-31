import XCTest
@testable import AlphaNote

/// Classifieur de mode embarqué : évalué sur le jeu de test du dépôt
/// (ml/data/test.csv, jamais vu à l'entraînement) et comparé aux mots-clés.
final class LocalModeClassifierTests: XCTestCase {
    private func testRows() throws -> [(text: String, label: String)] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ml/data/test.csv")
        guard let csv = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("ml/data/test.csv introuvable")
        }
        return csv.components(separatedBy: .newlines).dropFirst().compactMap { line in
            guard let comma = line.lastIndex(of: ",") else { return nil }
            var text = String(line[..<comma])
            if text.hasPrefix("\""), text.hasSuffix("\"") {
                text = String(text.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
            }
            return (text, String(line[line.index(after: comma)...]))
        }
    }

    func testModelIsBundledAndAccurate() throws {
        let rows = try testRows()
        XCTAssertGreaterThan(rows.count, 150)
        var model = 0, keywords = 0
        for row in rows {
            if LocalModeClassifier.shared.classify(row.text)?.mode.rawValue == row.label { model += 1 }
            if KeywordIntentRouter.classify(row.text, noteKeyword: nil).rawValue == row.label { keywords += 1 }
        }
        let accuracy = Double(model) / Double(rows.count)
        print(String(format: "modèle local %.1f %%, mots-clés %.1f %%", accuracy * 100, Double(keywords) / Double(rows.count) * 100))
        XCTAssertGreaterThanOrEqual(accuracy, 0.95)
        XCTAssertGreaterThan(model, keywords, "le modèle doit faire mieux que les mots-clés")
    }

    func testClearRequests() {
        XCTAssertEqual(LocalModeClassifier.shared.classify("minuteur 25 minutes")?.mode, .timer)
        XCTAssertEqual(LocalModeClassifier.shared.classify("combien font 12 fois 8")?.mode, .math)
        XCTAssertEqual(LocalModeClassifier.shared.classify("ajoute du beurre à la liste")?.mode, .list)
        XCTAssertEqual(LocalModeClassifier.shared.classify("écris une fonction python qui trie une liste")?.mode, .code)
    }

    /// Sans serveur JEV, la décision vient du modèle local, plus des mots-clés.
    func testRoutingWithoutServerUsesLocalModel() async {
        UserDefaults.standard.set(false, forKey: AISettingsKeys.enabled)
        let decision = await ModeRoutingFeature().route(question: "lance un chrono pour la course", noteKeyword: nil)
        XCTAssertEqual(decision.mode, .timer)
        XCTAssertEqual(decision.source, .local)
    }
}
