import Foundation

struct AIModelProfile: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let recommendedMaxTokens: Int
    let qualityTier: AIQualityTier

    static let qwen31_7B = AIModelProfile(
        id: "mlx-community/Qwen3-1.7B-4bit",
        displayName: "Qwen 3 1.7B (MLX)",
        recommendedMaxTokens: 500,
        qualityTier: .fast
    )

    static let gemma34B = AIModelProfile(
        id: "mlx-community/gemma-3-4b-it-4bit",
        displayName: "Gemma 3 4B IT (MLX)",
        recommendedMaxTokens: 700,
        qualityTier: .balanced
    )

    static let gemma3Text4B = AIModelProfile(
        id: "mlx-community/gemma-3-text-4b-it-4bit",
        displayName: "Gemma 3 Text 4B IT (MLX)",
        recommendedMaxTokens: 900,
        qualityTier: .quality
    )
}

enum AIQualityTier: String, CaseIterable, Codable, Sendable {
    case fast
    case balanced
    case quality

    var label: String {
        switch self {
        case .fast: return "Rapide"
        case .balanced: return "Équilibré"
        case .quality: return "Haute qualité"
        }
    }
}

enum AISettingsKeys {
    static let enabled = "aiEnabled"
    static let selectedModelID = "aiSelectedModelID"
    static let customModelID = "aiCustomModelID"
    static let qualityMode = "aiQualityMode"
    static let maxTokens = "aiMaxTokens"
    static let allowFallbackHeuristics = "aiAllowFallbackHeuristics"
}

enum AIModelRegistry {
    static let allProfiles: [AIModelProfile] = [.qwen31_7B, .gemma34B, .gemma3Text4B]

    static func profile(for id: String) -> AIModelProfile {
        allProfiles.first(where: { $0.id == id }) ?? .gemma34B
    }

    static func defaultProfile(for tier: AIQualityTier) -> AIModelProfile {
        switch tier {
        case .fast:
            return .qwen31_7B
        case .balanced:
            return .gemma34B
        case .quality:
            return .gemma3Text4B
        }
    }

    static func effectiveProfile(userModelID: String?, qualityTier: AIQualityTier) -> AIModelProfile {
        let requested = userModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !requested.isEmpty, let exact = allProfiles.first(where: { $0.id == requested }) {
            return exact
        }
        return defaultProfile(for: qualityTier)
    }
}
