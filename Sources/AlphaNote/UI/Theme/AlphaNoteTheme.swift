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

// MARK: - Mode palette

/// One colour per note mode, used by the question-bar badges and the AI schema
/// so a mode reads the same everywhere in the app.
enum ModePalette {
    static func foreground(_ mode: NoteMode) -> Color {
        switch mode {
        case .math: return .orange
        case .list: return .green
        case .timer: return .red
        case .code: return .blue
        case .plain: return .secondary
        }
    }

    static func background(_ mode: NoteMode) -> Color {
        switch mode {
        case .plain: return Color.secondary.opacity(0.15)
        default: return foreground(mode).opacity(0.18)
        }
    }
}
