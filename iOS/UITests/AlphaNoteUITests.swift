import XCTest

/// Parcours de bout en bout dans le simulateur, sur une base jetable
/// (`-databaseLocation`, synchro coupée) : l'éditeur unique, la marge du mode
/// liste et la barre de commande se comportent comme sur macOS et Android.
final class AlphaNoteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        let scratch = NSTemporaryDirectory() + "alphanote-uitest-" + UUID().uuidString
        app.launchArguments = ["-databaseLocation", scratch, "-syncEnabled", "0"]
        app.launch()
    }

    private func newNote() -> XCUIElement {
        app.buttons["Nouvelle note"].tap()
        let editor = app.textViews["noteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        return editor
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMathResultsAreWrittenInline() {
        let editor = newNote()
        editor.typeText("math: Budget\nloyer: 900\ncourses: 350\nloyer + courses =")
        let value = editor.value as? String ?? ""
        XCTAssertTrue(value.contains("loyer + courses = 1250"), value)
        snapshot("math")
    }

    func testListCheckboxTogglesTrigger() {
        let editor = newNote()
        editor.typeText("list: Courses\n- pain\nlait")
        // Entrée a continué la puce : « - lait ».
        XCTAssertTrue((editor.value as? String ?? "").contains("- lait"))
        app.buttons["OK"].tap()
        // Case de la première ligne d'élément, dans la marge de gauche.
        editor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: 52)).tap()
        let value = editor.value as? String ?? ""
        XCTAssertTrue(value.contains("- pain /x"), value)
        snapshot("liste")
    }

    func testCommandBarRoutesWithKeywordsWhenAIIsOff() {
        _ = newNote()
        app.buttons["OK"].tap()
        let field = app.textFields["commandField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("combien font 12 * 3\n")
        let editor = app.textViews["noteEditor"]
        let predicate = NSPredicate(format: "value CONTAINS %@", "12 * 3 = 36")
        expectation(for: predicate, evaluatedWith: editor)
        waitForExpectations(timeout: 10)
        snapshot("commande")
    }

    /// Accueil des Réglages : une rubrique par écran.
    func testSettingsOpen() {
        app.buttons["Réglages"].tap()
        snapshot("réglages")
        app.buttons["Synchronisation"].tap()
        XCTAssertTrue(app.staticTexts["Nextcloud"].waitForExistence(timeout: 5)
                      || app.staticTexts["NEXTCLOUD"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Intelligence artificielle"].tap()
        let engine = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Modèle local")).firstMatch
        XCTAssertTrue(engine.waitForExistence(timeout: 5))
        snapshot("réglages IA")
    }

    func testCountdownRingsInDarkTheme() {
        app.terminate()
        app.launchArguments += ["-theme", "dark", "-colorTheme", "sauge"]
        app.launch()
        let editor = newNote()
        editor.typeText("countdown 0:03")
        app.buttons["OK"].tap()
        app.buttons["Mode de la note : TEXTE"].tap()
        app.buttons["Timer"].tap()
        let play = app.buttons["Démarrer"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.buttons["Arrêter la sonnerie"].waitForExistence(timeout: 8))
        snapshot("minuteur sombre")
        app.buttons["Arrêter la sonnerie"].tap()
    }

    /// Nécessite le serveur JEV joignable (Tailscale) ; sinon routage mots-clés.
    func testCommandBarRoutesThroughJEV() throws {
        app.terminate()
        app.launchArguments += ["-aiEnabled", "1", "-jevURL", "http://100.95.198.127:8096", "-aiFormulaDraftEnabled", "0"]
        app.launch()
        _ = newNote()
        app.buttons["OK"].tap()
        let field = app.textFields["commandField"]
        field.tap()
        field.typeText("ajoute du lait, des oeufs et du pain à mes courses\n")
        let toast = app.descendants(matching: .any)["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 30))
        let message = toast.label
        print("PROBE toast:", message)
        if !message.contains("via JEV") {
            throw XCTSkip("JEV injoignable depuis le simulateur : \(message)")
        }
        let value = app.textViews["noteEditor"].value as? String ?? ""
        XCTAssertTrue(value.contains("lait"), value)
        snapshot("jev")
    }

    /// Sélecteur de photos du système (hors processus) : la photo d'exemple du
    /// simulateur devient une vignette sous l'éditeur.
    func testAddImageFromPhotoPicker() {
        let editor = newNote()
        editor.typeText("Recette")
        app.buttons["OK"].tap()
        app.buttons["More"].exists ? app.buttons["More"].tap() : app.buttons["ellipsis.circle"].tap()
        app.buttons["Ajouter une image"].tap()
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo")).firstMatch
        if !photo.waitForExistence(timeout: 10) { snapshot("picker"); print("PROBE", app.debugDescription.prefix(4000)) }
        XCTAssertTrue(photo.exists)
        photo.tap()
        XCTAssertTrue(app.buttons["Image jointe"].waitForExistence(timeout: 10))
        XCTAssertTrue((editor.value as? String ?? "").contains("![image](att:"))
        snapshot("image")
    }

    /// Sans argument -theme : un argument de lancement masquerait la valeur
    /// que le picker écrit.
    func testThemePickerSwitchesTheme() {
        app.buttons["Réglages"].tap()
        app.buttons["Apparence"].tap()
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Thème")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let target = (picker.label.contains("Sombre")) ? "Clair" : "Sombre"
        picker.tap()
        app.buttons[target].tap()
        XCTAssertTrue(app.buttons["Thème, \(target)"].waitForExistence(timeout: 5))
        snapshot("thème \(target)")
        picker.tap()
        app.buttons["Système"].tap()

        // Changer de couleurs reconstruit l'interface, sans fermer les Réglages.
        let colors = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Couleurs")).firstMatch
        let swatch = colors.label.contains("Lavande") ? "Corail" : "Lavande"
        colors.tap()
        app.buttons[swatch].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 3) {
            springboard.alerts.buttons.firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["Couleurs, \(swatch)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Apparence"].exists)
    }

    /// App en arrière-plan : la fin du compte à rebours arrive en notification.
    func testCountdownNotifiesInBackground() {
        let editor = newNote()
        editor.typeText("countdown 0:06")
        app.buttons["OK"].tap()
        app.buttons["Mode de la note : TEXTE"].tap()
        app.buttons["Timer"].tap()
        let play = app.buttons["Démarrer"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        // Première fois : iOS demande l'autorisation des notifications.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Autoriser", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCUIDevice.shared.press(.home)
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Minuteur terminé")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 15))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "notification"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Coffre : la note passe en mode Coffre, mot de passe maître, verrouillage,
    /// réouverture. Sur disque, le secret n'apparaît jamais en clair.
    func testVaultNoteIsEncryptedAndLocks() throws {
        let dbDir = NSTemporaryDirectory() + "alphanote-vault-" + UUID().uuidString
        app.terminate()
        app.launchArguments = ["-databaseLocation", dbDir, "-syncEnabled", "0", "-resetVault"]
        app.launch()

        let editor = newNote()
        editor.typeText("Banque\ncode 4321")
        app.buttons["OK"].tap()
        app.buttons["Mode de la note : TEXTE"].tap()
        app.buttons["Coffre"].tap()

        // Première fois : choix du mot de passe maître.
        let password = app.secureTextFields["vaultPassword"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("correct horse")
        let confirmation = app.secureTextFields["vaultConfirmation"]
        confirmation.tap()
        confirmation.typeText("correct horse\n")

        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains("code 4321"))
        snapshot("coffre ouvert")

        // Sur disque (et donc pour la synchro) : chiffré.
        sleep(1)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dbDir)) ?? []
        XCTAssertFalse(files.isEmpty, "base introuvable dans \(dbDir)")
        for file in files {
            let data = FileManager.default.contents(atPath: dbDir + "/" + file) ?? Data()
            XCTAssertNil(data.range(of: Data("code 4321".utf8)), "\(file) contient le secret en clair")
        }

        // Verrouiller, puis rouvrir avec le mot de passe maître.
        app.buttons["More"].tap()
        app.buttons["Verrouiller le coffre"].tap()
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        XCTAssertFalse(editor.exists)
        snapshot("coffre fermé")
        password.tap()
        password.typeText("correct horse\n")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains("code 4321"))
    }

    /// Titre modifiable en tête de note, y compris pour un minuteur.
    func testTimerNoteCanBeTitled() {
        let editor = newNote()
        editor.typeText("countdown 0:30")
        app.buttons["OK"].tap()
        app.buttons["Mode de la note : TEXTE"].tap()
        app.buttons["Timer"].tap()
        let title = app.textFields["noteTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.placeholderValue, "Minuteur")
        title.tap()
        title.typeText("Pâtes\n")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Pâtes"].waitForExistence(timeout: 5))
        snapshot("minuteur titré")
    }
}
