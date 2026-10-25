import AppKit

/// Dessine l'icône de l'app (design/AlphaNoteIcon.svg) avec l'accent du thème :
/// le Dock suit le thème choisi pendant que l'app tourne. Le Finder garde
/// l'icône du bundle, qu'on ne peut pas réécrire sans casser la signature.
enum AppIconRenderer {
    static func image(accent hex: UInt32) -> NSImage {
        let accent = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                             green: CGFloat((hex >> 8) & 0xFF) / 255,
                             blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        // Coordonnées du SVG (1024 × 1024, origine en haut à gauche).
        return NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { _ in
            NSColor(srgbRed: 0x22 / 255, green: 0x27 / 255, blue: 0x2E / 255, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 220, yRadius: 220).fill()

            let border = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 936, height: 936), xRadius: 192, yRadius: 192)
            border.lineWidth = 8
            NSColor(srgbRed: 0x2D / 255, green: 0x33 / 255, blue: 0x3B / 255, alpha: 1).setStroke()
            border.stroke()

            let font = NSFont(name: "Didot-Bold", size: 560) ?? NSFont(name: "Times-Bold", size: 560) ?? .boldSystemFont(ofSize: 560)
            let glyph = NSAttributedString(string: "A", attributes: [.font: font, .foregroundColor: NSColor.white])
            // Ligne de base à y = 600, centré sur x = 512, comme le SVG.
            let width = glyph.size().width
            glyph.draw(at: NSPoint(x: 512 - width / 2, y: 600 - font.ascender))

            // Motif : deux lignes de liste à cocher.
            accent.setFill()
            NSBezierPath(roundedRect: NSRect(x: 232, y: 672, width: 56, height: 56), xRadius: 14, yRadius: 14).fill()
            NSBezierPath(roundedRect: NSRect(x: 320, y: 679, width: 472, height: 42), xRadius: 21, yRadius: 21).fill()

            let faded = accent.withAlphaComponent(0.65)
            let box = NSBezierPath(roundedRect: NSRect(x: 237, y: 757, width: 46, height: 46), xRadius: 11, yRadius: 11)
            box.lineWidth = 10
            faded.setStroke()
            box.stroke()
            faded.setFill()
            NSBezierPath(roundedRect: NSRect(x: 320, y: 759, width: 312, height: 42), xRadius: 21, yRadius: 21).fill()
            return true
        }
    }
}
