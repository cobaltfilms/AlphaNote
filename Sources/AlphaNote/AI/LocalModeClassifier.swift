import CoreML
import Foundation
import NaturalLanguage

/// Classe une demande dans un mode, sur l'appareil, sans serveur : modèle
/// Create ML (entropie maximale, ~20 Ko) entraîné sur ml/data/train.csv, le
/// même jeu que le modèle TFLite d'Android. Rend JEV facultatif.
final class LocalModeClassifier: @unchecked Sendable {
    static let shared = LocalModeClassifier()

    /// En dessous, la décision est trop incertaine : les mots-clés tranchent.
    static let minimumConfidence = 0.45

    private let lock = NSLock()
    private var model: NLModel?
    private var loadFailed = false

    struct Decision: Equatable {
        let mode: NoteMode
        let confidence: Double
    }

    func classify(_ text: String) -> Decision? {
        guard let model = loadedModel() else { return nil }
        let hypotheses = model.predictedLabelHypotheses(for: text, maximumCount: 1)
        guard let (label, confidence) = hypotheses.max(by: { $0.value < $1.value }),
              let mode = NoteMode(rawValue: label), mode != .vault else { return nil }
        return Decision(mode: mode, confidence: confidence)
    }

    var isAvailable: Bool { loadedModel() != nil }

    // MARK: - Chargement

    private func loadedModel() -> NLModel? {
        lock.lock()
        defer { lock.unlock() }
        if let model { return model }
        guard !loadFailed else { return nil }
        do {
            model = try NLModel(contentsOf: try Self.compiledModelURL())
        } catch {
            loadFailed = true
            print("[LocalModeClassifier] modèle indisponible : \(error)")
        }
        return model
    }

    /// Le modèle voyage en `.coreml` (le .mlmodel de Create ML renommé : SwiftPM
    /// essaierait sinon d'en générer du code) ; compilé au premier usage, puis
    /// mis en cache.
    private static func compiledModelURL() throws -> URL {
        let name = "AlphaNoteModeClassifier"
        if let compiled = bundle.url(forResource: name, withExtension: "mlmodelc") {
            return compiled
        }
        guard let packaged = bundle.url(forResource: name, withExtension: "coreml") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AlphaNote/\(name)-\(modelStamp(packaged)).mlmodelc")
        if FileManager.default.fileExists(atPath: cache.path) { return cache }
        // compileModel veut l'extension .mlmodel.
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).mlmodel")
        try FileManager.default.copyItem(at: packaged, to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let compiled = try MLModel.compileModel(at: source)
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: cache)
        try FileManager.default.moveItem(at: compiled, to: cache)
        return cache
    }

    /// Un nouveau modèle (mise à jour de l'app) ne réutilise pas l'ancien cache.
    private static func modelStamp(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return String(size)
    }

    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}
