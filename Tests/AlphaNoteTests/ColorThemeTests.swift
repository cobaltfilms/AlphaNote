import XCTest
import AppKit
@testable import AlphaNote

final class ColorThemeTests: XCTestCase {

    /// « Encre & or » reste le thème d'avant les thèmes (valeurs 0…1 d'origine).
    func testInkAndGoldKeepsLegacyColors() {
        let night = ColorTheme.or.night, day = ColorTheme.or.day
        assertClose(night.window, (0.078, 0.066, 0.051))
        assertClose(night.content, (0.141, 0.122, 0.094))
        assertClose(night.text, (0.953, 0.918, 0.851))
        assertClose(night.accent, (0.851, 0.643, 0.255))
        assertClose(day.window, (0.965, 0.945, 0.918))
        assertClose(day.text, (0.141, 0.114, 0.082))
        assertClose(day.accent, (0.604, 0.420, 0.122))
    }

    func testDefaultIsInkAndGold() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: ColorTheme.storageKey)
        defer { defaults.set(saved, forKey: ColorTheme.storageKey) }
        defaults.removeObject(forKey: ColorTheme.storageKey)
        XCTAssertEqual(ColorTheme.current, .or)
        defaults.set("inconnu", forKey: ColorTheme.storageKey)
        XCTAssertEqual(ColorTheme.current, .or)
    }

    /// Texte lisible (WCAG ≥ 7) et accent visible (≥ 3) sur le fond des notes, jour et nuit.
    func testEveryThemeIsReadable() {
        for theme in ColorTheme.allCases {
            for (name, swatch) in [("nuit", theme.night), ("jour", theme.day)] {
                XCTAssertGreaterThanOrEqual(contrast(swatch.text, swatch.content), 7, "\(theme.label) \(name) : texte")
                XCTAssertGreaterThanOrEqual(contrast(swatch.secondary, swatch.content), 4.5, "\(theme.label) \(name) : texte secondaire")
                XCTAssertGreaterThanOrEqual(contrast(swatch.accent, swatch.content), 3, "\(theme.label) \(name) : accent")
            }
        }
    }

    func testDockIconUsesThemeAccent() throws {
        let hex = ColorTheme.lavande.night.accent
        let icon = try pixel(of: AppIconRenderer.image(accent: hex), x: 556, y: 700) // première barre du motif
        // Référence : un aplat de l'accent rendu par le même chemin (même gestion de couleur).
        let accent = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                             blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        let flat = NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { rect in
            accent.setFill(); rect.fill(); return true
        }
        let reference = try pixel(of: flat, x: 556, y: 700)
        XCTAssertEqual(icon.redComponent, reference.redComponent, accuracy: 0.02)
        XCTAssertEqual(icon.greenComponent, reference.greenComponent, accuracy: 0.02)
        XCTAssertEqual(icon.blueComponent, reference.blueComponent, accuracy: 0.02)
        let tile = try pixel(of: AppIconRenderer.image(accent: hex), x: 512, y: 900) // fond de la tuile
        XCTAssertGreaterThan(abs(tile.blueComponent - reference.blueComponent), 0.3)
    }

    private func pixel(of image: NSImage, x: Int, y: Int) throws -> NSColor {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.colorAt(x: x, y: y))
    }

    // MARK: - Aides

    private func components(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private func assertClose(_ hex: UInt32, _ expected: (Double, Double, Double), file: StaticString = #filePath, line: UInt = #line) {
        let c = components(hex)
        XCTAssertEqual(c.0, expected.0, accuracy: 0.003, file: file, line: line)
        XCTAssertEqual(c.1, expected.1, accuracy: 0.003, file: file, line: line)
        XCTAssertEqual(c.2, expected.2, accuracy: 0.003, file: file, line: line)
    }

    private func luminance(_ hex: UInt32) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let c = components(hex)
        return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
