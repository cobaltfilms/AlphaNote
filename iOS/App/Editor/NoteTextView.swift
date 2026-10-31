import SwiftUI
import UIKit

/// Éditeur unique iOS : un seul UITextView (TextKit 1) pour tous les modes,
/// comme l'éditeur macOS (NoteEditorView) et Android (NoteEditor.kt). Le mode
/// ne change que la décoration : résultats math écrits en ligne, cases du mode
/// liste dans la marge, en-tête discret, liens soulignés.
struct NoteTextView: UIViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var checkTrigger: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ChecklistTextView {
        let textView = ChecklistTextView.makeTextKit1()
        textView.delegate = context.coordinator
        textView.accessibilityIdentifier = "noteEditor"
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .default
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.dataDetectorTypes = []
        textView.linkTextAttributes = [:] // couleur posée par la décoration
        textView.textContainer.lineFragmentPadding = 0
        textView.text = text
        textView.onToggleItem = { [weak coordinator = context.coordinator] range in
            coordinator?.toggleListItem(in: range)
        }
        context.coordinator.textView = textView
        context.coordinator.refresh(recomputeMath: true)
        return textView
    }

    func updateUIView(_ textView: ChecklistTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        var needsRefresh = coordinator.appliedFontSize != fontSize || coordinator.appliedTrigger != checkTrigger
        if textView.text != text, !textView.isEditingProgrammatically {
            // Changement venu de l'extérieur (synchro, IA, mode, image) : on garde
            // le curseur au même endroit si possible.
            let selection = textView.selectedRange
            textView.text = text
            let length = (text as NSString).length
            textView.selectedRange = NSRange(location: min(selection.location, length), length: 0)
            needsRefresh = true
        }
        if needsRefresh { coordinator.refresh(recomputeMath: true) }
        if isFocused, !textView.isFirstResponder {
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteTextView
        weak var textView: ChecklistTextView?
        var appliedFontSize: Double?
        var appliedTrigger: String?

        private let documentEvaluator = MathDocumentEvaluator()
        private var ratesObserver: NSObjectProtocol?

        init(parent: NoteTextView) {
            self.parent = parent
            super.init()
            ratesObserver = NotificationCenter.default.addObserver(
                forName: .alphaNoteCurrencyRatesDidUpdate, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, let textView = self.textView,
                      EditorTextRules.detectMode(in: textView.text) == .math else { return }
                self.refresh(recomputeMath: true)
            }
        }

        deinit {
            if let ratesObserver { NotificationCenter.default.removeObserver(ratesObserver) }
        }

        // MARK: Délégué

        func textViewDidChange(_ textView: UITextView) {
            if EditorTextRules.detectMode(in: textView.text) == .math {
                applyMathResults(respectCaret: true)
            }
            publish()
            decorate()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        /// Entrée en mode liste : continue la puce, ou retire une puce vide.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement == "\n", range.length == 0,
                  EditorTextRules.detectMode(in: textView.text) == .list else { return true }
            let nsText = textView.text as NSString
            let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
            let line = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard let marker = EditorTextRules.bulletMarker(in: line) else { return true }

            if EditorTextRules.isEmptyBullet(line) {
                replace(NSRange(location: lineRange.location, length: (marker as NSString).length), with: "",
                        caret: lineRange.location)
            } else {
                let insertion = "\n" + marker
                replace(range, with: insertion, caret: range.location + (insertion as NSString).length)
            }
            return false
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            // Liens : ouverture au toucher, même en édition.
            defaultAction
        }

        private func publish() {
            guard let textView, textView.text != parent.text else { return }
            parent.text = textView.text
        }

        // MARK: Rafraîchissement

        func refresh(recomputeMath: Bool) {
            guard let textView else { return }
            appliedFontSize = parent.fontSize
            appliedTrigger = parent.checkTrigger
            if recomputeMath, EditorTextRules.detectMode(in: textView.text) == .math {
                applyMathResults(respectCaret: false)
            }
            decorate()
        }

        private func replace(_ range: NSRange, with string: String, caret: Int) {
            guard let textView, let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }
            textView.replace(textRange, withText: string) // passe par l'undo manager
            textView.selectedRange = NSRange(location: min(caret, (textView.text as NSString).length), length: 0)
            publish()
            decorate()
        }

        // MARK: Décoration

        func decorate() {
            guard let textView else { return }
            let storage = textView.textStorage
            let text = textView.text ?? ""
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let mode = EditorTextRules.detectMode(in: text)
            let size = CGFloat(parent.fontSize)
            let isMono = mode == .math || mode == .code || mode == .vault
            let baseFont: UIFont = isMono
                ? .monospacedSystemFont(ofSize: size, weight: .regular)
                : .systemFont(ofSize: size)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = mode == .code ? size * 0.35 : size * 0.55

            let selection = textView.selectedRange
            textView.isEditingProgrammatically = true
            storage.beginEditing()
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: Palette.text,
                .paragraphStyle: paragraph
            ], range: fullRange)

            var itemLines: [ChecklistTextView.ItemLine] = []
            let variableNames = mode == .math ? documentEvaluator.variableNames(in: text) : []
            let trigger = parent.checkTrigger.isEmpty ? "/x" : parent.checkTrigger

            var location = 0
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let nsLine = line as NSString
                let lineRange = NSRange(location: location, length: nsLine.length)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                location += nsLine.length + 1

                if index == 0, EditorTextRules.isModeHeader(trimmed) {
                    storage.addAttributes([
                        .foregroundColor: Palette.secondary,
                        .font: UIFont.systemFont(ofSize: max(11, size - 2), weight: .semibold)
                    ], range: lineRange)
                    continue
                }
                if NoteAttachments.isImageLine(line) {
                    storage.addAttributes([.foregroundColor: Palette.secondary,
                                           .font: UIFont.systemFont(ofSize: max(11, size - 3))], range: lineRange)
                    continue
                }

                switch mode {
                case .plain, .code, .timer, .vault:
                    break
                case .list:
                    if trimmed.isEmpty { continue }
                    if ListModeFormatter.isHeading(trimmed) {
                        storage.addAttributes([.font: UIFont.systemFont(ofSize: size + 2, weight: .bold)], range: lineRange)
                    } else if ListModeFormatter.isComment(trimmed) {
                        storage.addAttributes([.foregroundColor: Palette.secondary], range: lineRange)
                    } else {
                        let checked = EditorTextRules.isChecked(trimmed, trigger: trigger)
                        if checked {
                            storage.addAttributes([
                                .foregroundColor: Palette.secondary,
                                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                .strikethroughColor: Palette.secondary
                            ], range: lineRange)
                            if let triggerRange = line.range(of: trigger, options: [.caseInsensitive, .backwards]) {
                                let ns = NSRange(triggerRange, in: line)
                                storage.addAttributes([.foregroundColor: Palette.line],
                                                      range: NSRange(location: lineRange.location + ns.location, length: ns.length))
                            }
                        }
                        if let marker = EditorTextRules.bulletMarker(in: line) {
                            storage.addAttributes([.foregroundColor: Palette.line],
                                                  range: NSRange(location: lineRange.location, length: (marker as NSString).length))
                        }
                        itemLines.append(.init(range: lineRange, checked: checked))
                    }
                case .math:
                    decorateMathLine(line, lineRange: lineRange, in: storage, variableNames: variableNames, size: size)
                }
            }

            if mode == .plain {
                for url in URLDetector.extractURLs(from: text) {
                    var searchRange = fullRange
                    while searchRange.length > 0 {
                        let found = nsText.range(of: url.absoluteString, options: [.caseInsensitive], range: searchRange)
                        guard found.location != NSNotFound else { break }
                        storage.addAttributes([
                            .link: url,
                            .foregroundColor: Palette.accent2,
                            .underlineStyle: NSUnderlineStyle.single.rawValue
                        ], range: found)
                        let next = NSMaxRange(found)
                        searchRange = NSRange(location: next, length: nsText.length - next)
                    }
                }
            }
            storage.endEditing()
            textView.selectedRange = selection
            textView.isEditingProgrammatically = false

            textView.typingAttributes = [.font: baseFont, .foregroundColor: Palette.text, .paragraphStyle: paragraph]
            textView.listMode = mode == .list
            textView.itemLines = itemLines
        }

        private func decorateMathLine(_ line: String, lineRange: NSRange, in storage: NSTextStorage, variableNames: Set<String>, size: CGFloat) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                storage.addAttributes([.foregroundColor: Palette.secondary], range: lineRange)
                return
            }
            if MathDocumentEvaluator.parseVariableAssignment(from: line) != nil, let colon = line.firstIndex(of: ":") {
                let length = NSRange(line.startIndex..<colon, in: line).length
                storage.addAttributes([
                    .foregroundColor: Palette.math,
                    .font: UIFont.monospacedSystemFont(ofSize: size, weight: .semibold)
                ], range: NSRange(location: lineRange.location, length: length))
            }
            if let equal = line.firstIndex(of: "=") {
                let offset = NSRange(line.startIndex..<equal, in: line).length
                storage.addAttributes([.foregroundColor: Palette.secondary],
                                      range: NSRange(location: lineRange.location + offset, length: 1))
                let resultLength = lineRange.length - offset - 1
                if resultLength > 0 {
                    storage.addAttributes([
                        .foregroundColor: Palette.accent2,
                        .font: UIFont.monospacedSystemFont(ofSize: size, weight: .semibold)
                    ], range: NSRange(location: lineRange.location + offset + 1, length: resultLength))
                }
            }
            highlight(EditorTextRules.numberRegex, color: Palette.code, in: lineRange, storage: storage)
            highlight(EditorTextRules.unitRegex, color: Palette.list, in: lineRange, storage: storage)
            for name in variableNames {
                guard let regex = EditorTextRules.variableRegex(name) else { continue }
                highlight(regex, color: Palette.math, in: lineRange, storage: storage)
            }
        }

        private func highlight(_ regex: NSRegularExpression, color: UIColor, in range: NSRange, storage: NSTextStorage) {
            for match in regex.matches(in: storage.string, range: range) {
                storage.addAttributes([.foregroundColor: color], range: match.range)
            }
        }

        // MARK: Résultats math

        func applyMathResults(respectCaret: Bool) {
            guard let textView, textView.markedTextRange == nil else { return }
            let selection = textView.selectedRange
            let edits = MathInlineApplier.edits(for: textView.text, caret: respectCaret ? selection.location : nil,
                                                evaluator: documentEvaluator)
            guard !edits.isEmpty else { return }
            let caret = MathInlineApplier.adjustedCaret(selection.location, after: edits)
            textView.isEditingProgrammatically = true
            let storage = textView.textStorage
            storage.beginEditing()
            for edit in edits { storage.replaceCharacters(in: edit.range, with: edit.replacement) }
            storage.endEditing()
            textView.selectedRange = NSRange(location: min(caret, (textView.text as NSString).length), length: 0)
            textView.isEditingProgrammatically = false
            publish()
        }

        // MARK: Liste

        func toggleListItem(in lineRange: NSRange) {
            guard let textView else { return }
            let nsText = textView.text as NSString
            guard NSMaxRange(lineRange) <= nsText.length else { return }
            let line = nsText.substring(with: lineRange)
            let replacement = EditorTextRules.toggledListLine(line, trigger: parent.checkTrigger)
            let caret = textView.selectedRange.location
            let delta = (replacement as NSString).length - lineRange.length
            replace(lineRange, with: replacement, caret: caret > lineRange.location ? max(lineRange.location, caret + delta) : caret)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

// MARK: - UITextView avec marge de cases

final class ChecklistTextView: UITextView {
    struct ItemLine {
        let range: NSRange
        let checked: Bool
    }

    static let gutterWidth: CGFloat = 40
    private let boxSize: CGFloat = 18

    var isEditingProgrammatically = false
    var onToggleItem: (NSRange) -> Void = { _ in }

    var listMode = false {
        didSet {
            guard listMode != oldValue else { return }
            textContainerInset = UIEdgeInsets(top: 12, left: listMode ? Self.gutterWidth : 16, bottom: 120, right: 16)
            gutter.isHidden = !listMode
            setNeedsLayout()
        }
    }

    var itemLines: [ItemLine] = [] {
        didSet { gutter.setNeedsDisplay() }
    }

    private lazy var gutter: GutterView = {
        let view = GutterView()
        view.owner = self
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.contentMode = .redraw
        return view
    }()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        commonInit()
    }

    /// TextKit 1 : NSLayoutManager donne la géométrie des lignes pour la marge.
    static func makeTextKit1() -> ChecklistTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = ChecklistTextView(frame: .zero, textContainer: container)
        textView.ownedStorage = storage // la pile TextKit ne retient pas son stockage
        return textView
    }

    private var ownedStorage: NSTextStorage?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 120, right: 16)
        addSubview(gutter)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleGutterTap(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gutter.frame = CGRect(x: 0, y: 0, width: Self.gutterWidth, height: max(contentSize.height, bounds.height))
        gutter.setNeedsDisplay()
    }

    fileprivate func checkboxRect(for item: ItemLine) -> CGRect? {
        let length = (text as NSString).length
        guard length > 0, item.range.location < length else { return nil }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: item.range.location)
        let fragment = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let lineHeight = (font ?? .systemFont(ofSize: 17)).lineHeight
        return CGRect(x: Self.gutterWidth - boxSize - 10,
                      y: textContainerInset.top + fragment.minY + (min(fragment.height, lineHeight) - boxSize) / 2 + 1,
                      width: boxSize, height: boxSize)
    }

    @objc private func handleGutterTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        guard let item = itemLines.first(where: { item in
            guard let rect = checkboxRect(for: item) else { return false }
            return point.y >= rect.minY - 10 && point.y <= rect.maxY + 10
        }) else { return }
        onToggleItem(item.range)
    }
}

extension ChecklistTextView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer.view === self, recognizer is UITapGestureRecognizer,
              recognizer.delegate === self else { return super.gestureRecognizerShouldBegin(recognizer) }
        // Seuls les touchers dans la marge du mode liste basculent une case.
        return listMode && recognizer.location(in: self).x < Self.gutterWidth - 2
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        false
    }
}

private final class GutterView: UIView {
    weak var owner: ChecklistTextView?

    override func draw(_ rect: CGRect) {
        guard let owner else { return }
        for item in owner.itemLines {
            guard let box = owner.checkboxRect(for: item), box.intersects(rect) else { continue }
            let path = UIBezierPath(roundedRect: box, cornerRadius: 4)
            if item.checked {
                Palette.accent.setFill()
                path.fill()
                let check = UIBezierPath()
                check.move(to: CGPoint(x: box.minX + 4.5, y: box.midY))
                check.addLine(to: CGPoint(x: box.minX + 7.5, y: box.maxY - 5))
                check.addLine(to: CGPoint(x: box.maxX - 4, y: box.minY + 5))
                check.lineWidth = 2
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                Palette.content.setStroke()
                check.stroke()
            } else {
                path.lineWidth = 1.5
                Palette.secondary.setStroke()
                path.stroke()
            }
        }
    }
}
