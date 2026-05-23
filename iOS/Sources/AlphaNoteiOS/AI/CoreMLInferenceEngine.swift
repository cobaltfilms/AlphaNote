import Foundation

/// Core ML inference engine for iOS.
/// Currently a placeholder — will be implemented when Core ML-compatible models
/// (e.g., Gemma 4 converted via coremltools) become available.
final class CoreMLInferenceEngine: AIInferenceEngineProtocol, @unchecked Sendable {

    func generate(
        prompt: String,
        system: String?,
        modelID: String,
        options: AIRequestOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            // Placeholder: Core ML inference not yet available.
            // Falls through to heuristic fallback in AIService.
            continuation.yield("Inference Core ML — modèle non disponible. Active le fallback heuristique dans Réglages > AI.")
            continuation.finish()
        }
    }
}

/// Heuristic fallback for iOS — no model required, works offline.
struct HeuristicFallbackInferenceEngine: AIInferenceEngineProtocol {
    func generate(
        prompt: String,
        system: String?,
        modelID: String,
        options: AIRequestOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("Moteur IA local indisponible (mode dégradé). Télécharge un modèle Core ML dans Réglages > AI.")
            continuation.finish()
        }
    }
}
