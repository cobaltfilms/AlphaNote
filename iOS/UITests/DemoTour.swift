import XCTest

/// Démo commentée de l'app iOS, au rythme d'un humain. Ignorée par les tests
/// normaux ; lancée par `scripts/ios.sh demo` (TEST_RUNNER_ALPHANOTE_DEMO=1).
final class DemoTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["ALPHANOTE_DEMO"] == "1" else {
            throw XCTSkip("Démo : scripts/ios.sh demo")
        }
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = [
            "-databaseLocation", NSTemporaryDirectory() + "alphanote-demo-" + UUID().uuidString,
            "-syncEnabled", "0",
            "-aiEnabled", "1", "-jevURL", "http://100.95.198.127:8096", "-aiFormulaDraftEnabled", "1"
        ]
        // Pas de -theme / -colorTheme ici : un argument de lancement masquerait
        // le choix fait dans les Réglages. scripts/ios.sh remet l'apparence à zéro.
        app.launch()
    }

    private func pause(_ seconds: Double = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func newNote(_ text: String) -> XCUIElement {
        app.buttons["Nouvelle note"].tap()
        let editor = app.textViews["noteEditor"]
        _ = editor.waitForExistence(timeout: 5)
        editor.tap()
        pause(0.6)
        for line in text.components(separatedBy: "\n").enumerated() {
            editor.typeText((line.offset == 0 ? "" : "\n") + line.element)
            pause(0.5)
        }
        return editor
    }

    private func back() {
        if app.buttons["OK"].exists { app.buttons["OK"].tap(); pause(0.5) }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause()
    }

    private func ask(_ question: String) {
        if app.buttons["OK"].exists { app.buttons["OK"].tap(); pause(0.5) }
        let field = app.textFields["commandField"]
        field.tap()
        field.typeText(question)
        pause(0.8)
        field.typeText("\n")
        _ = app.descendants(matching: .any)["toast"].waitForExistence(timeout: 30)
        pause(3.5)
    }

    /// Picker de Réglages : son bouton s'appelle « Thème, Système ».
    private func choose(_ picker: String, _ option: String) {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", picker)).firstMatch.tap()
        pause(0.8)
        app.buttons.matching(NSPredicate(format: "label == %@", option)).firstMatch.tap()
        pause(1.5)
    }

    func testTour() {
        pause(2)

        // 1. Note math : variables et résultats écrits en ligne.
        _ = newNote("math: Budget vacances\nlogement: 640\nessence: 2 * 85\nrepas: 7 * 45\ntotal: logement + essence + repas =\npar personne: total / 4 =")
        pause(2.5)
        back()

        // 2. Liste : cases dans la marge, puces qui continuent.
        let list = newNote("list: Courses\n- pain\nlait\nœufs\ntomates")
        if app.buttons["OK"].exists { app.buttons["OK"].tap() }
        pause()
        for dy in [52.0, 82.0] {
            list.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: dy)).tap()
            pause(0.9)
        }
        pause(1.5)
        back()

        // 3. Barre de commande : JEV classe, la note applique.
        _ = newNote("")
        ask("ajoute du café, du beurre et des pommes à mes courses")
        back()
        _ = newNote("")
        ask("combien font 3 pizzas à 12,50 € plus 15 % de pourboire")
        pause(1.5)
        back()

        // 4. Minuteur : la demande crée une note minuteur.
        _ = newNote("")
        ask("minuteur 5 secondes")
        pause()
        let play = app.buttons["Démarrer"]
        if play.waitForExistence(timeout: 5) { play.tap() }
        _ = app.buttons["Arrêter la sonnerie"].waitForExistence(timeout: 12)
        pause(3)
        if app.buttons["Arrêter la sonnerie"].exists { app.buttons["Arrêter la sonnerie"].tap() }
        pause()
        back()

        // 5. Image jointe depuis la photothèque.
        _ = newNote("Inspiration jardin")
        if app.buttons["OK"].exists { app.buttons["OK"].tap() }
        app.buttons["More"].tap()
        pause(0.8)
        app.buttons["Ajouter une image"].tap()
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo")).firstMatch
        if photo.waitForExistence(timeout: 10) { photo.tap() }
        pause(2)
        if app.buttons["Image jointe"].waitForExistence(timeout: 5) {
            app.buttons["Image jointe"].tap()
            pause(2.5)
            app.buttons["Fermer"].tap()
            pause()
        }
        back()

        // 6. Recherche, puis thème Sauge en sombre.
        app.swipeDown()
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("lait")
            pause(2.5)
            for label in ["close", "Annuler", "Cancel", "Fermer"] where app.buttons[label].exists {
                app.buttons[label].tap()
                break
            }
            pause()
        }
        app.buttons["Réglages"].tap()
        pause()
        app.buttons["Apparence"].tap()
        pause()
        choose("Thème", "Sombre")
        choose("Couleurs", "Sauge")
        // iOS confirme le changement d'icône (assortie au thème).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 3) {
            pause(1.5)
            springboard.alerts.buttons.firstMatch.tap()
            pause()
        }
        if app.buttons["OK"].exists { app.buttons["OK"].tap() }
        pause(3)
    }
}
