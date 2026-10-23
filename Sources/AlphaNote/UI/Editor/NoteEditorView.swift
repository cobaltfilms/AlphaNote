import SwiftUI
import AppKit

/// L'éditeur unique d'AlphaNote. Un seul `NSTextView` pour tous les modes
/// texte : le mode (`plain`, `math`, `list`, `code`) ne fait que *décorer* le
/// texte — police, couleurs, résultats inline, cases à cocher en marge. Changer
/// de mode en tapant la première ligne ne détruit donc jamais l'éditeur, le
/// focus ni le curseur.
struct NoteEditorView: NSViewRepresentable {
    @Binding var text: String
    let mode: NoteMode
    let fontSize: Double
    let checkTrigger: String
    var onEscape: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Pile TextKit 1 explicite : la marge à cases (mode liste) lit les
        // rectangles de ligne via NSLayoutManager, absent d'une vue TextKit 2.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        let textView = NoteTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        // Fond opaque (couleur adaptative) : un NSTextView sans fond ne nettoie
        // pas sa zone sale et laisse des fragments de glyphes.
        textView.backgroundColor = Palette.content
        textView.drawsBackground = true
        textView.insertionPointColor = Palette.accent
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.selectedTextAttributes = [.backgroundColor: Palette.selection]
        textView.onEscape = { context.coordinator.parent.onEscape() }
        textView.onToggleItem = { [weak coordinator = context.coordinator] lineRange in
            coordinator?.toggleListItem(in: lineRange)
        }

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.applyMode(animated: false)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.content
        scrollView.documentView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }

        if !coordinator.isProgrammaticChange, textView.string != text {
            coordinator.isProgrammaticChange = true
            let selection = textView.selectedRange()
            textView.string = text
            let clamped = min(selection.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
            coordinator.isProgrammaticChange = false
            coordinator.applyMode(animated: false)
            return
        }

        if coordinator.appliedMode != mode || coordinator.appliedFontSize != fontSize || coordinator.appliedTrigger != checkTrigger {
            coordinator.applyMode(animated: true)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditorView
        weak var textView: NoteTextView?
        var isProgrammaticChange = false
        var appliedMode: NoteMode?
        var appliedFontSize: Double?
        var appliedTrigger: String?

        private let documentEvaluator = MathDocumentEvaluator()
        private var ratesObserver: NSObjectProtocol?

        init(parent: NoteEditorView) {
            self.parent = parent
            super.init()
            ratesObserver = NotificationCenter.default.addObserver(
                forName: .alphaNoteCurrencyRatesDidUpdate, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.parent.mode == .math else { return }
                self.applyMathResults(respectCaret: false)
                self.decorate()
            }
        }

        deinit {
            if let ratesObserver { NotificationCenter.default.removeObserver(ratesObserver) }
        }

        // MARK: Délégué

        func textDidChange(_ notification: Notification) {
            guard let textView, !isProgrammaticChange else { return }
            if parent.mode == .math || Self.detectMode(in: textView.string) == .math {
                applyMathResults(respectCaret: true)
            }
            publish()
            decorate()
        }

        private func publish() {
            guard let textView else { return }
            let newText = textView.string
            guard newText != parent.text else { return }
            parent.text = newText
        }

        // MARK: Mode

        func applyMode(animated: Bool) {
            guard let textView else { return }
            appliedMode = parent.mode
            appliedFontSize = parent.fontSize
            appliedTrigger = parent.checkTrigger

            let isMono = parent.mode == .math || parent.mode == .code
            textView.font = isMono
                ? .monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
                : .systemFont(ofSize: parent.fontSize)
            textView.listGutterEnabled = parent.mode == .list
            textView.textContainerInset = NSSize(width: parent.mode == .list ? 40 : 18, height: 14)

            if parent.mode == .math {
                applyMathResults(respectCaret: false) // chargement : on rafraîchit tout
            }
            decorate()
            textView.needsDisplay = true
        }

        static func detectMode(in content: String) -> NoteMode {
            var probe = Note(content: content)
            probe.detectKeyword()
            return NoteMode(rawValue: probe.keyword) ?? .plain
        }

        // MARK: Décoration

        func decorate() {
            guard let textView, let storage = textView.textStorage else { return }
            let text = textView.string
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let mode = Self.detectMode(in: text)
            let size = parent.fontSize
            let baseFont: NSFont = (mode == .math || mode == .code)
                ? .monospacedSystemFont(ofSize: size, weight: .regular)
                : .systemFont(ofSize: size)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = mode == .code ? 1 : 3

            storage.beginEditing()
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: Palette.text,
                .paragraphStyle: paragraph
            ], range: fullRange)

            var itemLines: [NoteTextView.ItemLine] = []
            let variableNames = mode == .math ? documentEvaluator.variableNames(in: text) : []
            let trigger = parent.checkTrigger.isEmpty ? "/x" : parent.checkTrigger

            var location = 0
            let lines = text.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let nsLine = line as NSString
                let lineRange = NSRange(location: location, length: nsLine.length)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                defer {
                    location += nsLine.length
                    if index < lines.count - 1 { location += 1 }
                }

                // En-tête de mode : discret.
                if index == 0, Self.isModeHeader(trimmed) {
                    storage.addAttributes([
                        .foregroundColor: Palette.secondary,
                        .font: NSFont.systemFont(ofSize: max(10, size - 2), weight: .semibold)
                    ], range: lineRange)
                    continue
                }

                switch mode {
                case .plain:
                    break
                case .code:
                    break
                case .timer:
                    break
                case .list:
                    if trimmed.isEmpty { continue }
                    if ListModeFormatter.isHeading(trimmed) {
                        storage.addAttributes([
                            .font: NSFont.systemFont(ofSize: size + 2, weight: .bold)
                        ], range: lineRange)
                    } else if ListModeFormatter.isComment(trimmed) {
                        storage.addAttributes([.foregroundColor: Palette.secondary], range: lineRange)
                    } else {
                        let checked = Self.isChecked(trimmed, trigger: trigger)
                        if checked {
                            storage.addAttributes([
                                .foregroundColor: Palette.secondary,
                                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                .strikethroughColor: Palette.secondary
                            ], range: lineRange)
                        }
                        // Marqueur « - » ou « * » discret.
                        if let markerRange = line.range(of: #"^\s*[-*•]\s"#, options: .regularExpression) {
                            let ns = NSRange(markerRange, in: line)
                            storage.addAttributes([.foregroundColor: Palette.line],
                                                  range: NSRange(location: lineRange.location + ns.location, length: ns.length))
                        }
                        // Le déclencheur « /x » en fin de ligne presque invisible.
                        if checked, let triggerRange = line.range(of: trigger, options: [.caseInsensitive, .backwards]) {
                            let ns = NSRange(triggerRange, in: line)
                            storage.addAttributes([.foregroundColor: Palette.line],
                                                  range: NSRange(location: lineRange.location + ns.location, length: ns.length))
                        }
                        itemLines.append(NoteTextView.ItemLine(range: lineRange, checked: checked))
                    }
                case .math:
                    decorateMathLine(line, lineRange: lineRange, in: storage, variableNames: variableNames, size: size)
                }
            }

            if mode == .plain {
                for url in URLDetector.extractURLs(from: text) {
                    var searchRange = fullRange
                    while let found = Self.range(of: url, in: nsText, searchRange: searchRange) {
                        storage.addAttributes([
                            .link: url,
                            .foregroundColor: Palette.accent2,
                            .underlineStyle: NSUnderlineStyle.single.rawValue
                        ], range: found)
                        let next = found.location + found.length
                        searchRange = NSRange(location: next, length: max(0, nsText.length - next))
                        if searchRange.length == 0 { break }
                    }
                }
            }

            storage.endEditing()
            textView.itemLines = itemLines
            textView.setNeedsDisplay(textView.bounds)
        }

        private static func range(of url: URL, in text: NSString, searchRange: NSRange) -> NSRange? {
            let candidates = [url.absoluteString, url.absoluteString.replacingOccurrences(of: "https://", with: "")]
            for candidate in candidates {
                let range = text.range(of: candidate, options: [.caseInsensitive], range: searchRange)
                if range.location != NSNotFound { return range }
            }
            return nil
        }

        private func decorateMathLine(_ line: String, lineRange: NSRange, in storage: NSTextStorage, variableNames: Set<String>, size: CGFloat) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                storage.addAttributes([.foregroundColor: Palette.secondary], range: lineRange)
                return
            }

            if let assignment = MathDocumentEvaluator.parseVariableAssignment(from: line),
               let colon = line.firstIndex(of: ":") {
                _ = assignment
                let length = line.distance(from: line.startIndex, to: colon)
                storage.addAttributes([
                    .foregroundColor: Palette.math,
                    .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
                ], range: NSRange(location: lineRange.location, length: length))
            }

            if let equal = line.firstIndex(of: "=") {
                let offset = line.distance(from: line.startIndex, to: equal)
                storage.addAttributes([.foregroundColor: Palette.secondary],
                                      range: NSRange(location: lineRange.location + offset, length: 1))
                let resultOffset = offset + 1
                let resultLength = lineRange.length - resultOffset
                if resultLength > 0 {
                    storage.addAttributes([
                        .foregroundColor: Palette.accent2,
                        .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
                    ], range: NSRange(location: lineRange.location + resultOffset, length: resultLength))
                }
            }

            Self.highlight(Self.numberRegex, color: Palette.code, in: lineRange, storage: storage)
            Self.highlight(Self.unitRegex, color: Palette.list, in: lineRange, storage: storage)
            for name in variableNames {
                let escaped = NSRegularExpression.escapedPattern(for: name)
                guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])", options: [.caseInsensitive]) else { continue }
                Self.highlight(regex, color: Palette.math, in: lineRange, storage: storage)
            }
        }

        private static func highlight(_ regex: NSRegularExpression, color: NSColor, in range: NSRange, storage: NSTextStorage) {
            for match in regex.matches(in: storage.string, options: [], range: range) {
                storage.addAttributes([.foregroundColor: color], range: match.range)
            }
        }

        private static let numberRegex = try! NSRegularExpression(pattern: "(?<![\\p{L}_])[-+]?\\d+(?:[.,]\\d+)?")
        private static let unitRegex = try! NSRegularExpression(pattern: "(?i)\\b(usd|eur|gbp|jpy|chf|cad|kg|g|mg|lb|oz|km|m|cm|mm|mi|yd|ft|in|sqm|sqft|ha|acre|l|ml|gal|qt|pt|cup|°c|°f|k|min|h|s)\\b")

        static func isModeHeader(_ trimmed: String) -> Bool {
            let lower = trimmed.lowercased()
            return Note.knownKeywords.contains(lower)
                || Note.knownKeywords.contains(where: { lower.hasPrefix("\($0):") })
        }

        static func isChecked(_ trimmed: String, trigger: String) -> Bool {
            trimmed.range(of: trigger, options: [.caseInsensitive, .anchored, .backwards]) != nil
        }

        // MARK: Résultats math (remplacement ciblé, jamais du texte entier)

        func applyMathResults(respectCaret: Bool = true) {
            guard let textView, let storage = textView.textStorage, !textView.hasMarkedText() else { return }
            let content = textView.string
            let outcomes = documentEvaluator.evaluate(content: content).filter(\.changed)
            guard !outcomes.isEmpty else { return }

            let nsContent = content as NSString
            var lineStarts: [Int] = [0]
            nsContent.enumerateSubstrings(in: NSRange(location: 0, length: nsContent.length), options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
                lineStarts.append(enclosing.location + enclosing.length)
            }

            let selection = textView.selectedRange()
            var newSelection = selection
            var edits: [(range: NSRange, replacement: String)] = []

            for outcome in outcomes.reversed() {
                guard outcome.index < lineStarts.count - 1 || outcome.index == lineStarts.count - 1 else { continue }
                let lineStart = lineStarts[outcome.index]
                let original = outcome.original as NSString
                let lineRange = NSRange(location: lineStart, length: original.length)
                guard NSMaxRange(lineRange) <= nsContent.length else { continue }

                // On ne touche qu'à la queue après le premier « = ».
                let equalIndex = original.range(of: "=").location
                guard equalIndex != NSNotFound else { continue }
                let tailRange = NSRange(location: lineStart + equalIndex + 1, length: original.length - equalIndex - 1)

                let transformed = outcome.transformed as NSString
                let transformedEqual = transformed.range(of: "=").location
                guard transformedEqual != NSNotFound else { continue }
                let newTail = transformed.substring(from: transformedEqual + 1)

                // Le curseur est à l'intérieur d'un résultat existant (l'utilisateur
                // y écrit) : on attend qu'il en sorte. Juste après « = », on remplace.
                if respectCaret, tailRange.length > 0,
                   selection.location > tailRange.location, selection.location <= NSMaxRange(tailRange) {
                    continue
                }

                edits.append((tailRange, newTail))
            }
            guard !edits.isEmpty else { return }

            // Enregistrement undo avant toute modification (plages encore valides).
            let allowed = edits.filter { textView.shouldChangeText(in: $0.range, replacementString: $0.replacement) }
            guard !allowed.isEmpty else { return }

            isProgrammaticChange = true
            storage.beginEditing()
            for edit in allowed { // déjà dans l'ordre inverse
                storage.replaceCharacters(in: edit.range, with: edit.replacement)
                if edit.range.location < newSelection.location {
                    newSelection.location += (edit.replacement as NSString).length - edit.range.length
                }
            }
            storage.endEditing()
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: max(0, min(newSelection.location, (textView.string as NSString).length)), length: 0))
            isProgrammaticChange = false
            publish()
        }

        // MARK: Liste

        func toggleListItem(in lineRange: NSRange) {
            guard let textView, let storage = textView.textStorage else { return }
            let nsText = textView.string as NSString
            guard NSMaxRange(lineRange) <= nsText.length else { return }
            let line = nsText.substring(with: lineRange)
            let trigger = parent.checkTrigger.isEmpty ? "/x" : parent.checkTrigger
            let trimmedTrailing = line.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)

            let replacement: String
            if Self.isChecked(trimmedTrailing.trimmingCharacters(in: .whitespaces), trigger: trigger),
               let range = trimmedTrailing.range(of: trigger, options: [.caseInsensitive, .backwards]) {
                replacement = String(trimmedTrailing[..<range.lowerBound]).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            } else {
                replacement = trimmedTrailing.isEmpty ? trigger : "\(trimmedTrailing) \(trigger)"
            }

            isProgrammaticChange = true
            if textView.shouldChangeText(in: lineRange, replacementString: replacement) {
                storage.replaceCharacters(in: lineRange, with: replacement)
                textView.didChangeText()
            }
            isProgrammaticChange = false
            publish()
            decorate()
        }
    }
}

// MARK: - NSTextView

final class NoteTextView: NSTextView {
    struct ItemLine {
        let range: NSRange
        let checked: Bool
    }

    var listGutterEnabled = false {
        didSet { updateGutter() }
    }
    var itemLines: [ItemLine] = [] {
        didSet { gutter?.needsDisplay = true }
    }
    private var gutter: ListGutterView?
    var onEscape: () -> Void = {}
    var onToggleItem: (NSRange) -> Void = { _ in }

    private let gutterWidth: CGFloat = 40
    private let boxSize: CGFloat = 15

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }

    // MARK: Marge à cases
    //
    // Le dessin se fait dans une sous-vue dédiée : sur macOS 14, ce qu'un
    // NSTextView dessine dans `draw(_:)` en dehors du texte n'atteint pas
    // l'écran (le rendu passe par sa propre couche). Une NSView ordinaire,
    // enfant du text view, défile avec lui et se redessine normalement.

    private func updateGutter() {
        if listGutterEnabled {
            if gutter == nil {
                let view = ListGutterView(frame: NSRect(x: 0, y: 0, width: textContainerInset.width, height: bounds.height))
                view.autoresizingMask = [.height]
                view.textView = self
                addSubview(view)
                gutter = view
            }
            gutter?.frame.size.width = textContainerInset.width
            gutter?.isHidden = false
            gutter?.needsDisplay = true
        } else {
            gutter?.isHidden = true
        }
    }

    override var textContainerInset: NSSize {
        didSet { gutter?.frame.size.width = textContainerInset.width }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        gutter?.frame.size.height = newSize.height
        gutter?.needsDisplay = true
    }

    /// Rectangle de la case pour une ligne d'élément, en coordonnées du text view.
    fileprivate func checkboxRect(for item: ItemLine) -> NSRect? {
        guard let layoutManager, let textContainer,
              let frame = lineFragmentFrame(for: item.range, layoutManager: layoutManager, container: textContainer) else { return nil }
        return NSRect(
            x: textContainerInset.width - boxSize - 10,
            y: frame.minY + (frame.height - boxSize) / 2 + textContainerInset.height,
            width: boxSize, height: boxSize
        )
    }

    /// Élément dont la ligne contient le point (coordonnées du text view).
    fileprivate func itemLine(at point: NSPoint) -> ItemLine? {
        guard let layoutManager, let textContainer else { return nil }
        let containerPoint = NSPoint(x: max(0, point.x - textContainerInset.width), y: point.y - textContainerInset.height)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return itemLines.first { charIndex >= $0.range.location && charIndex <= NSMaxRange($0.range) }
    }

    override func mouseDown(with event: NSEvent) {
        guard listGutterEnabled else { return super.mouseDown(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        guard point.x < textContainerInset.width - 4, let item = itemLine(at: point) else {
            return super.mouseDown(with: event)
        }
        onToggleItem(item.range)
    }

    /// Entrée en mode liste : continue la puce « - » si la ligne en a une.
    override func insertNewline(_ sender: Any?) {
        guard listGutterEnabled else { return super.insertNewline(sender) }
        let nsText = string as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
        if let marker = line.range(of: #"^\s*[-*•]\s"#, options: .regularExpression) {
            let rest = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                // Puce vide : on la retire au lieu d'en ajouter une.
                let markerNS = NSRange(location: lineRange.location, length: (String(line[marker]) as NSString).length)
                if shouldChangeText(in: markerNS, replacementString: "") {
                    textStorage?.replaceCharacters(in: markerNS, with: "")
                    didChangeText()
                }
                return
            }
            super.insertNewline(sender)
            insertText(String(line[marker]), replacementRange: selectedRange())
            return
        }
        super.insertNewline(sender)
    }

    private func lineFragmentFrame(for range: NSRange, layoutManager: NSLayoutManager, container: NSTextContainer) -> NSRect? {
        let length = (string as NSString).length
        guard range.location <= length else { return nil }
        let charIndex = min(range.location, max(0, length - 1))
        if length == 0 { return nil }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
        guard glyphIndex < layoutManager.numberOfGlyphs || range.length == 0 else {
            return layoutManager.extraLineFragmentRect
        }
        return layoutManager.lineFragmentRect(forGlyphAt: min(glyphIndex, max(0, layoutManager.numberOfGlyphs - 1)), effectiveRange: nil)
    }
}

/// Marge gauche du mode liste : une case par élément, cliquable.
final class ListGutterView: NSView {
    weak var textView: NoteTextView?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView, textView.listGutterEnabled else { return }
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        for item in textView.itemLines {
            guard let box = textView.checkboxRect(for: item) else { continue }
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            if item.checked {
                Palette.list.setFill()
                path.fill()
                let check = NSBezierPath()
                check.lineWidth = 2
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.move(to: NSPoint(x: box.minX + 3.5, y: box.midY))
                check.line(to: NSPoint(x: box.minX + 6.5, y: box.maxY - 3.5))
                check.line(to: NSPoint(x: box.maxX - 3.5, y: box.minY + 3.5))
                Palette.content.setStroke()
                check.stroke()
            } else {
                path.lineWidth = 1.5
                Palette.secondary.setStroke()
                path.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let textView else { return }
        let point = textView.convert(event.locationInWindow, from: nil)
        if let item = textView.itemLine(at: point) {
            textView.onToggleItem(item.range)
        } else {
            textView.window?.makeFirstResponder(textView)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
