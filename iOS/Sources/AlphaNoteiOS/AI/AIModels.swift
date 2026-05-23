import Foundation

enum RewriteStyle: String, CaseIterable, Codable, Sendable {
    case clear
    case concise
    case professional

    var label: String {
        switch self {
        case .clear: return "Clair"
        case .concise: return "Concis"
        case .professional: return "Professionnel"
        }
    }
}

enum AITask: Sendable, Equatable {
    case summarize
    case rewrite(style: RewriteStyle)
    case extractActions
    case modeRouting
    case semanticAnswer

    var telemetryName: String {
        switch self {
        case .summarize: return "summarize"
        case .rewrite: return "rewrite"
        case .extractActions: return "extract_actions"
        case .modeRouting: return "mode_routing"
        case .semanticAnswer: return "semantic_answer"
        }
    }
}

struct AIRequestOptions: Sendable {
    let temperature: Double
    let maxTokens: Int
    let topP: Double
    let stop: [String]

    static let `default` = AIRequestOptions(
        temperature: 0.2,
        maxTokens: 500,
        topP: 0.9,
        stop: []
    )
}

struct AIContext: Sendable {
    let noteTitle: String
    let languageCode: String
    let relatedNotes: [NoteContext]

    static let empty = AIContext(noteTitle: "", languageCode: "fr", relatedNotes: [])
}

struct NoteContext: Sendable {
    let uuid: String
    let title: String
    let content: String
}

struct AIResult: Sendable, Equatable {
    let text: String
    let metadata: [String: String]
}

enum AIError: Error, LocalizedError, Equatable {
    case disabled
    case modelUnavailable
    case timeout
    case cancelled
    case invalidOutput
    case internalFailure(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "L'IA locale est désactivée dans les réglages."
        case .modelUnavailable:
            return "Modèle local indisponible. Vérifie l'installation dans Réglages > AI."
        case .timeout:
            return "L'opération IA a dépassé le délai."
        case .cancelled:
            return "L'opération IA a été annulée."
        case .invalidOutput:
            return "Réponse IA invalide."
        case let .internalFailure(message):
            return message
        }
    }
}

enum AIApplyMode: String, CaseIterable, Sendable {
    case replace
    case insertBelow
}

struct AIResultEnvelope: Identifiable, Equatable, Sendable {
    let id = UUID()
    let noteID: Int64
    let task: AITask
    let result: AIResult
}

protocol AIInferenceEngineProtocol {
    func generate(
        prompt: String,
        system: String?,
        modelID: String,
        options: AIRequestOptions
    ) -> AsyncThrowingStream<String, Error>
}

protocol AIServiceProtocol {
    func run(task: AITask, note: Note, context: AIContext) async throws -> AIResult
}
