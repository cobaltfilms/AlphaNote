import XCTest
@testable import AlphaNote

/// Rédaction de formules par Apple Intelligence (sur l'appareil). Ignoré là
/// où le modèle n'existe pas (machine sans Apple Intelligence, CI).
final class AppleFormulaDrafterTests: XCTestCase {
    private func result(of lines: [String]) -> String {
        let content = (["math"] + lines).joined(separator: "\n")
        let evaluator = MathDocumentEvaluator()
        let applied = MathInlineApplier.apply(MathInlineApplier.edits(for: content, caret: nil, evaluator: evaluator), to: content)
        return applied.components(separatedBy: "\n").last ?? ""
    }

    func testDraftsComputableFormulas() async throws {
        guard AppleFormulaDrafter.isAvailable else { throw XCTSkip("Apple Intelligence indisponible") }
        #if targetEnvironment(simulator)
        // Le simulateur se dit « disponible » mais n'a pas le modèle installé.
        throw XCTSkip("Foundation Models : pas de modèle dans le simulateur")
        #endif
        let cases: [(String, Double)] = [
            ("aire d'un cercle de rayon 3", 28.27),
            ("combien de secondes dans une semaine", 604_800),
            ("prix de 3 pizzas à 12,50 € avec 15 % de pourboire", 43.125),
        ]
        for (question, expected) in cases {
            guard case let .ok(lines) = await AppleFormulaDrafter.draft(question: question) else {
                return XCTFail("pas de formule pour « \(question) »")
            }
            XCTAssertNil(FormulaDraftFeature.validate(lines), "\(question) : \(lines)")
            let last = result(of: lines)
            print("«\(question)» → \(lines) → \(last)")
            let value = Double(last.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".") ?? "")
            XCTAssertEqual(value ?? .nan, expected, accuracy: expected * 0.001, "\(question) : \(lines)")
        }
    }
}
