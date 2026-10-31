import SwiftUI
#if os(macOS)
import AppKit

/// Couleur native : PlatformColor sur macOS, UIColor sur iOS. La palette est la même.
typealias PlatformColor = NSColor

extension Color {
    init(platform color: NSColor) { self.init(nsColor: color) }
}
#else
import UIKit

typealias PlatformColor = UIColor

extension Color {
    init(platform color: UIColor) { self.init(uiColor: color) }
}
#endif

// Design language shared with AlphaSUB / AlphaDCP, mirrored locally so AlphaNote
// stays a dependency-free SPM build. The look those apps use is: forms built
// from `LabeledContent` whose label carries a hover explanation, secondary
// `.callout` help text, rounded surfaces, and a semantic colour per concept.

// MARK: - Field labels

/// A form field's name, with an explanation shown on hover.
struct FieldLabel: View {
    private let title: String
    private let help: String?

    init(_ title: String, help: String? = nil) {
        self.title = title
        self.help = help
    }

    var body: some View {
        if let help {
            Text(title).help(help)
        } else {
            Text(title)
        }
    }
}

/// A labelled text field whose NAME carries the explanation, value trailing.
struct HelpTextField: View {
    private let title: String
    private let help: String?
    private let prompt: String?
    @Binding private var text: String

    init(_ title: String, text: Binding<String>, prompt: String? = nil, help: String? = nil) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.help = help
    }

    var body: some View {
        LabeledContent {
            TextField(title, text: $text, prompt: prompt.map { Text($0) })
                .labelsHidden()
                .multilineTextAlignment(.trailing)
        } label: {
            FieldLabel(title, help: help)
        }
    }
}

/// A labelled toggle whose NAME carries the explanation.
struct HelpToggle: View {
    private let title: String
    private let help: String?
    @Binding private var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>, help: String? = nil) {
        self.title = title
        self._isOn = isOn
        self.help = help
    }

    var body: some View {
        LabeledContent {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        } label: {
            FieldLabel(title, help: help)
        }
    }
}

/// Secondary explanatory line under a control.
struct HelpNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Palette (thème méta « Encre & or »)
//
// Mêmes teintes, inversées jour/nuit comme un mode day & night :
//   · Nuit  = encre chaude (neutres bruns très sombres) + or + sauge.
//   · Jour  = crème chaude (camaïeu clair) + or profond + bleu paon.
// Les couleurs sont adaptatives : elles se résolvent selon l'apparence effective
// de la fenêtre (réglée par le réglage « theme »), donc tout — surfaces, texte,
// badges, éditeurs — bascule ensemble.

enum Palette {
    private static func adaptive(_ day: (CGFloat, CGFloat, CGFloat),
                                 _ night: (CGFloat, CGFloat, CGFloat)) -> PlatformColor {
        #if os(macOS)
        NSColor(name: nil) { appearance in
            let isNight = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isNight ? night : day
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        }
        #else
        UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? night : day
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        }
        #endif
    }

    /// Couleur du thème choisi (Réglages › Apparence › Couleurs). Calculée à
    /// chaque lecture : un changement de thème vaut pour les vues recréées.
    private static func themed(_ role: KeyPath<ColorTheme.Swatch, UInt32>) -> PlatformColor {
        let theme = ColorTheme.current
        return adaptive(rgb(theme.day[keyPath: role]), rgb(theme.night[keyPath: role]))
    }

    private static func rgb(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
        (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }

    // Surfaces en camaïeu (du plus sombre au plus clair, ou l'inverse la nuit).
    static var window: PlatformColor    { themed(\.window) }
    static var sidebar: PlatformColor   { themed(\.sidebar) }
    static var content: PlatformColor   { themed(\.content) }
    static var field: PlatformColor     { themed(\.field) }
    static var selection: PlatformColor { themed(\.selection) }
    static var line: PlatformColor      { themed(\.line) }

    // Texte.
    static var text: PlatformColor      { themed(\.text) }
    static var secondary: PlatformColor { themed(\.secondary) }

    // Accent du thème ; le secondaire (paon/sage) ne change pas.
    static var accent: PlatformColor    { themed(\.accent) }
    static let accent2   = adaptive((0.184, 0.435, 0.400), (0.498, 0.655, 0.627))

    // Couleur sémantique par mode.
    static let math  = adaptive((0.604, 0.420, 0.122), (0.851, 0.643, 0.255)) // or
    static let list  = adaptive((0.184, 0.435, 0.400), (0.498, 0.655, 0.627)) // paon/sage
    static let timer = adaptive((0.706, 0.314, 0.180), (0.812, 0.420, 0.341)) // terre cuite
    static let code  = adaptive((0.227, 0.373, 0.659), (0.616, 0.706, 0.839)) // bleu
    static var plain: PlatformColor { secondary }                                    // neutre

    static func mode(_ mode: NoteMode) -> PlatformColor {
        switch mode {
        case .math:  return math
        case .list:  return list
        case .timer: return timer
        case .code:  return code
        case .plain: return plain
        }
    }

    // Accès SwiftUI.
    static var windowColor: Color { Color(platform: window) }
    static var sidebarColor: Color { Color(platform: sidebar) }
    static var contentColor: Color { Color(platform: content) }
    static var fieldColor: Color { Color(platform: field) }
    static var selectionColor: Color { Color(platform: selection) }
    static var lineColor: Color { Color(platform: line) }
    static var textColor: Color { Color(platform: text) }
    static var secondaryColor: Color { Color(platform: secondary) }
    static var accentColor: Color { Color(platform: accent) }
    static var accent2Color: Color { Color(platform: accent2) }
    static func modeColor(_ mode: NoteMode) -> Color { Color(platform: Palette.mode(mode)) }
}

// MARK: - Thèmes de couleur

/// Thèmes coordonnés : chacun fixe l'accent (contours, cases, curseur) et une
/// teinte des fonds assortie, de nuit et de jour. Mêmes valeurs sur Android
/// (ui/theme/Color.kt) ; l'icône du Dock reprend l'accent de nuit.
enum ColorTheme: String, CaseIterable, Identifiable {
    case or, corail, sauge, lavande, framboise, bleu

    struct Swatch {
        let window, sidebar, content, field, selection, line, text, secondary, accent: UInt32
    }

    static let storageKey = "colorTheme"

    static var current: ColorTheme {
        ColorTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .or
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .or: return "Encre & or"
        case .corail: return "Corail"
        case .sauge: return "Sauge"
        case .lavande: return "Lavande"
        case .framboise: return "Framboise"
        case .bleu: return "Bleu nuit"
        }
    }

    var night: Swatch {
        switch self {
        case .or:        return Swatch(window: 0x14110D, sidebar: 0x1D1812, content: 0x241F18, field: 0x1A1611, selection: 0x2A2318, line: 0x342C21, text: 0xF3EAD9, secondary: 0xA99A80, accent: 0xD9A441)
        case .corail:    return Swatch(window: 0x1B1F25, sidebar: 0x1F242B, content: 0x22272E, field: 0x1D2127, selection: 0x2D333B, line: 0x343B45, text: 0xEEF0F2, secondary: 0x9AA3AD, accent: 0xEF7B5F)
        case .sauge:     return Swatch(window: 0x141A18, sidebar: 0x18201D, content: 0x1B2320, field: 0x161D1A, selection: 0x24302B, line: 0x2B3832, text: 0xE8EFEC, secondary: 0x93A59E, accent: 0x7FBFA8)
        case .lavande:   return Swatch(window: 0x17151F, sidebar: 0x1B1924, content: 0x1F1C29, field: 0x191722, selection: 0x2A2638, line: 0x312C40, text: 0xEEEBF5, secondary: 0xA29CB5, accent: 0xA78BFA)
        case .framboise: return Swatch(window: 0x1C1418, sidebar: 0x21181D, content: 0x251B20, field: 0x1E161A, selection: 0x33242C, line: 0x3A2A32, text: 0xF5EBEF, secondary: 0xB39AA4, accent: 0xE86A8E)
        case .bleu:      return Swatch(window: 0x121821, sidebar: 0x161D28, content: 0x19212D, field: 0x141B25, selection: 0x223047, line: 0x283548, text: 0xE9EEF5, secondary: 0x97A4B6, accent: 0x5B9CF0)
        }
    }

    var day: Swatch {
        switch self {
        case .or:        return Swatch(window: 0xF6F1EA, sidebar: 0xEFE6D8, content: 0xFFFAF3, field: 0xFFFAF3, selection: 0xECE0CD, line: 0xE2D6C4, text: 0x241D15, secondary: 0x6F6152, accent: 0x9A6B1F)
        case .corail:    return Swatch(window: 0xF5F3F1, sidebar: 0xECE8E4, content: 0xFFFDFB, field: 0xFFFDFB, selection: 0xF2DFD8, line: 0xE2DCD6, text: 0x22272E, secondary: 0x626B75, accent: 0xC4553A)
        case .sauge:     return Swatch(window: 0xF1F5F2, sidebar: 0xE4EBE6, content: 0xFBFDFB, field: 0xFBFDFB, selection: 0xD8E8E1, line: 0xD3DDD7, text: 0x1B2320, secondary: 0x5A6B64, accent: 0x2F6F66)
        case .lavande:   return Swatch(window: 0xF4F2F8, sidebar: 0xE9E5F1, content: 0xFDFCFF, field: 0xFDFCFF, selection: 0xE3DBF7, line: 0xDDD8E8, text: 0x1F1C29, secondary: 0x665F7A, accent: 0x6D4FD1)
        case .framboise: return Swatch(window: 0xF8F1F3, sidebar: 0xF0E4E8, content: 0xFFFBFC, field: 0xFFFBFC, selection: 0xF3D9E1, line: 0xE8D8DD, text: 0x251B20, secondary: 0x76606A, accent: 0xB83E63)
        case .bleu:      return Swatch(window: 0xF1F4F8, sidebar: 0xE4EAF2, content: 0xFBFCFF, field: 0xFBFCFF, selection: 0xD9E5F6, line: 0xD6DEE9, text: 0x19212D, secondary: 0x5C6A7D, accent: 0x2F62B8)
        }
    }
}

// MARK: - Mode palette

/// Une couleur par mode, issue de la Palette : badges de la barre de question et
/// schéma IA lisent la même teinte.
enum ModePalette {
    static func foreground(_ mode: NoteMode) -> Color { Palette.modeColor(mode) }

    static func background(_ mode: NoteMode) -> Color {
        Palette.modeColor(mode).opacity(mode == .plain ? 0.14 : 0.20)
    }
}
