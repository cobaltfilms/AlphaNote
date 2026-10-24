import XCTest
@testable import AlphaNote

private struct CannedTransport: JEVTransport {
    let data: Data
    func post(url: URL, body: Data, delaiMs: Int) async throws -> Data { data }
}

private func chatCompletion(_ content: String, model: String = "/models/Qwen3-8B-Q4_K_M.gguf") -> Data {
    let object: [String: Any] = [
        "model": model,
        "choices": [["message": ["role": "assistant", "content": content]]]
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}

final class RecipeIngredientExtractorTests: XCTestCase {

    func testJSONLDRecipeIsRead() {
        let html = """
        <html><head><script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Recipe","name":"Crêpes",
         "recipeIngredient":["250 g de farine","4 œufs","50 cl de lait"]}
        </script></head></html>
        """
        let recipe = RecipeIngredientExtractor.extract(fromHTML: html)
        XCTAssertEqual(recipe?.title, "Crêpes")
        XCTAssertEqual(recipe?.ingredients, ["250 g de farine", "4 œufs", "50 cl de lait"])
    }

    func testRecipeInsideGraphWithTypeArrayAndEntities() {
        let html = """
        <script type='application/ld+json'>
        {"@graph":[{"@type":"WebPage","name":"Site"},
                   {"@type":["Recipe","NewsArticle"],"name":"Tarte &amp; pommes",
                    "recipeIngredient":["1 p&acirc;te bris&eacute;e","4 pommes","4 pommes"," "]}]}
        </script>
        """
        let recipe = RecipeIngredientExtractor.extract(fromHTML: html)
        XCTAssertEqual(recipe?.title, "Tarte & pommes")
        XCTAssertEqual(recipe?.ingredients, ["1 pâte brisée", "4 pommes"], "doublons et vides retirés")
    }

    func testInvalidJSONLDFallsBackToMicrodata() {
        let html = """
        <script type="application/ld+json">{ cassé </script>
        <ul><li itemprop="recipeIngredient"><span>200 g</span> de sucre</li>
        <li itemprop="recipeIngredient">1 pincée de sel</li></ul>
        """
        XCTAssertEqual(RecipeIngredientExtractor.extract(fromHTML: html)?.ingredients, ["200 g de sucre", "1 pincée de sel"])
    }

    func testPageWithoutRecipeIsNil() {
        let html = #"<script type="application/ld+json">{"@type":"Article","name":"x"}</script>"#
        XCTAssertNil(RecipeIngredientExtractor.extract(fromHTML: html))
    }

    func testURLRoutesToListBeforeMath() {
        XCTAssertEqual(
            KeywordIntentRouter.classify("https://www.marmiton.org/recettes/recette_crepes-1234.aspx", noteKeyword: nil),
            .list
        )
    }
}

final class FormulaDraftFeatureTests: XCTestCase {

    func testParseLinesStripsThinkAndFences() {
        let content = "<think>\n</think>\n```json\n{\"lignes\": [\"pi * 3^2 =\"]}\n```"
        guard case let .ok(lines) = FormulaDraftFeature.parseLines(content) else {
            return XCTFail("formule attendue")
        }
        XCTAssertEqual(lines, ["pi * 3^2 ="])
    }

    func testValidFormulaWithVariablesIsAccepted() {
        XCTAssertNil(FormulaDraftFeature.validate([
            "taux: 0.03 / 12",
            "mois: 20 * 12",
            "200000 * taux / (1 - (1 + taux)^(-mois)) ="
        ]))
    }

    func testNamedResultLineIsAccepted() {
        XCTAssertNil(FormulaDraftFeature.validate(["rayon: 3", "aire: pi * rayon^2 ="]))
    }

    func testUnknownWordIsRejected() {
        // L'évaluateur ignorerait « rayon » et rendrait 9 : on refuse.
        XCTAssertNotNil(FormulaDraftFeature.validate(["pi * rayon^2 ="]))
    }

    func testMissingResultLineIsRejected() {
        XCTAssertNotNil(FormulaDraftFeature.validate(["r: 3"]))
    }

    func testReservedVariableNameIsRejected() {
        XCTAssertNotNil(FormulaDraftFeature.validate(["sqrt: 3", "sqrt * 2 ="]))
    }

    func testDraftHappyPathKeepsModelName() async {
        let outcome = await FormulaDraftFeature().draft(
            question: "aire d'un cercle de rayon 3",
            config: JEVConfig(url: "http://test", delaiMs: 1_000),
            transport: CannedTransport(data: chatCompletion(#"{"lignes": ["pi * 3^2 ="]}"#))
        )
        guard case let .ok(draft) = outcome else { return XCTFail("formule attendue") }
        XCTAssertEqual(draft.lines, ["pi * 3^2 ="])
        XCTAssertEqual(draft.model, "Qwen3-8B-Q4_K_M.gguf")
    }

    func testDraftWithUnknownWordIsAFrankError() async {
        let outcome = await FormulaDraftFeature().draft(
            question: "aire d'un cercle de rayon 3",
            config: JEVConfig(url: "http://test", delaiMs: 1_000),
            transport: CannedTransport(data: chatCompletion(#"{"lignes": ["pi * rayon^2 ="]}"#))
        )
        guard case let .erreur(message) = outcome else { return XCTFail("rejet attendu") }
        XCTAssertTrue(message.contains("rayon"), message)
    }
}
