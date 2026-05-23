import Foundation

enum AIModelStabilityTier: String, Codable, Sendable {
    case `default`
    case quality
    case experimental

    var label: String {
        switch self {
        case .default: return "Par défaut"
        case .quality: return "Qualité+"
        case .experimental: return "Avancé (expérimental)"
        }
    }
}

struct AIModelProfile: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let displayFormat: String
    let recommendedMaxTokens: Int
    let qualityTier: AIQualityTier
    let memoryHint: String
    let estimatedDownloadGB: Double
    let recommendedMinMemoryGB: Int
    let stabilityTier: AIModelStabilityTier

    var isHeavyForNotes: Bool {
        estimatedDownloadGB >= 8 || stabilityTier == .experimental
    }

    // iOS Core ML models — placeholder profiles for when Core ML models become available
    static let heuristicFallback = AIModelProfile(
        id: "heuristic",
        displayName: "Fallback heuristique (iOS)",
        displayFormat: "Sans modèle",
        recommendedMaxTokens: 0,
        qualityTier: .fast,
        memoryHint: "Aucun",
        estimatedDownloadGB: 0,
        recommendedMinMemoryGB: 0,
        stabilityTier: .default
    )

    // Placeholder Core ML profiles for future model availability
    static let gemma4E2BCoreML = AIModelProfile(
        id: "coreml-gemma-4-e2b-it",
        displayName: "Gemma 4 E2B IT (Core ML)",
        displayFormat: "Core ML",
        recommendedMaxTokens: 640,
        qualityTier: .fast,
        memoryHint: "Petit (multimodal)",
        estimatedDownloadGB: 2.7,
        recommendedMinMemoryGB: 4,
        stabilityTier: .default
    )

    static let gemma4E4BCoreML = AIModelProfile(
        id: "coreml-gemma-4-e4b-it",
        displayName: "Gemma 4 E4B IT (Core ML)",
        displayFormat: "Core ML",
        recommendedMaxTokens: 700,
        qualityTier: .balanced,
        memoryHint: "Petit (multimodal)",
        estimatedDownloadGB: 5.2,
        recommendedMinMemoryGB: 6,
        stabilityTier: .default
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
    static let conservativePolicyEnabled = "aiConservativePolicyEnabled"
    static let companionAwarenessEnabled = "aiCompanionAwarenessEnabled"
    static let cotypistAwarenessEnabledLegacy = "aiCotypistAwarenessEnabled"
}

enum AIModelRegistry {
    static let allProfiles: [AIModelProfile] = [
        .heuristicFallback,
        .gemma4E2BCoreML,
        .gemma4E4BCoreML
    ]

    static func profile(for id: String) -> AIModelProfile {
        allProfiles.first(where: { $0.id == id }) ?? .heuristicFallback
    }

    static func defaultProfile(for tier: AIQualityTier) -> AIModelProfile {
        switch tier {
        case .fast:
            return .heuristicFallback
        case .balanced, .quality:
            return .heuristicFallback
        }
    }

    static func effectiveProfile(userModelID: String?, qualityTier: AIQualityTier) -> AIModelProfile {
        let requested = userModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !requested.isEmpty, let exact = allProfiles.first(where: { $0.id == requested }) {
            return exact
        }
        return defaultProfile(for: qualityTier)
    }

    /// iOS memory recommendation — simplified vs macOS (no swap on iOS).
    static func machineRecommendation(physicalMemoryGB: Int) -> String {
        if physicalMemoryGB < 4 {
            return "Appareil: \(physicalMemoryGB) GB. Recommandation: fallback heuristique uniquement."
        }
        if physicalMemoryGB < 6 {
            return "Appareil: \(physicalMemoryGB) GB. Recommandation: Gemma 4 E2B Core ML (quand disponible)."
        }
        return "Appareil: \(physicalMemoryGB) GB. Recommandation: Gemma 4 E4B Core ML (quand disponible)."
    }

    /// iOS memory-safe token limit — no swap on iOS, simpler than macOS.
    static func memorySafeMaxTokens(
        requested: Int,
        profile: AIModelProfile,
        swapUsedGB: Double,
        conservativeMode: Bool,
        companionLLMRunning: Bool
    ) -> Int {
        // iOS has no swap — swapUsedGB is always 0
        guard conservativeMode else {
            return max(64, min(requested, profile.recommendedMaxTokens))
        }

        var cap = profile.recommendedMaxTokens
        if profile.isHeavyForNotes {
            cap = min(cap, 192)
            if companionLLMRunning {
                cap = min(cap, 128)
            }
        }

        return max(64, min(requested, cap))
    }
}
