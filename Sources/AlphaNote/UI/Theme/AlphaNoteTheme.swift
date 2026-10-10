import SwiftUI

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
                                 _ night: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let isNight = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isNight ? night : day
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }

    // Surfaces en camaïeu (du plus sombre au plus clair, ou l'inverse la nuit).
    static let window    = adaptive((0.965, 0.945, 0.918), (0.078, 0.066, 0.051))
    static let sidebar   = adaptive((0.937, 0.902, 0.847), (0.114, 0.094, 0.071))
    static let content   = adaptive((1.000, 0.980, 0.953), (0.141, 0.122, 0.094))
    static let field     = adaptive((1.000, 0.980, 0.953), (0.102, 0.086, 0.067))
    static let selection = adaptive((0.925, 0.878, 0.804), (0.165, 0.137, 0.094))
    static let line      = adaptive((0.886, 0.839, 0.769), (0.204, 0.173, 0.129))

    // Texte.
    static let text      = adaptive((0.141, 0.114, 0.082), (0.953, 0.918, 0.851))
    static let secondary = adaptive((0.435, 0.380, 0.322), (0.663, 0.604, 0.502))

    // Accents opposés : or (primaire) et paon/sage (secondaire).
    static let accent    = adaptive((0.604, 0.420, 0.122), (0.851, 0.643, 0.255))
    static let accent2   = adaptive((0.184, 0.435, 0.400), (0.498, 0.655, 0.627))

    // Couleur sémantique par mode.
    static let math  = adaptive((0.604, 0.420, 0.122), (0.851, 0.643, 0.255)) // or
    static let list  = adaptive((0.184, 0.435, 0.400), (0.498, 0.655, 0.627)) // paon/sage
    static let timer = adaptive((0.706, 0.314, 0.180), (0.812, 0.420, 0.341)) // terre cuite
    static let code  = adaptive((0.227, 0.373, 0.659), (0.616, 0.706, 0.839)) // bleu
    static let plain = adaptive((0.435, 0.380, 0.322), (0.663, 0.604, 0.502)) // neutre

    static func mode(_ mode: NoteMode) -> NSColor {
        switch mode {
        case .math:  return math
        case .list:  return list
        case .timer: return timer
        case .code:  return code
        case .plain: return plain
        }
    }

    // Accès SwiftUI.
    static var windowColor: Color { Color(nsColor: window) }
    static var sidebarColor: Color { Color(nsColor: sidebar) }
    static var contentColor: Color { Color(nsColor: content) }
    static var fieldColor: Color { Color(nsColor: field) }
    static var selectionColor: Color { Color(nsColor: selection) }
    static var lineColor: Color { Color(nsColor: line) }
    static var textColor: Color { Color(nsColor: text) }
    static var secondaryColor: Color { Color(nsColor: secondary) }
    static var accentColor: Color { Color(nsColor: accent) }
    static var accent2Color: Color { Color(nsColor: accent2) }
    static func modeColor(_ mode: NoteMode) -> Color { Color(nsColor: Palette.mode(mode)) }
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
