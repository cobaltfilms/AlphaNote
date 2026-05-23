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

    static let qwen31_7B = AIModelProfile(
        id: "mlx-community/Qwen3-1.7B-4bit",
        displayName: "Qwen 3 1.7B (MLX)",
        displayFormat: "MLX 4-bit",
        recommendedMaxTokens: 500,
        qualityTier: .fast,
        memoryHint: "Petit",
        estimatedDownloadGB: 1.6,
        recommendedMinMemoryGB: 8,
        stabilityTier: .default
    )

    static let gemma34B = AIModelProfile(
        id: "mlx-community/gemma-3-4b-it-4bit",
        displayName: "Gemma 3 4B IT (MLX)",
        displayFormat: "MLX 4-bit",
        recommendedMaxTokens: 640,
        qualityTier: .balanced,
        memoryHint: "Petit",
        estimatedDownloadGB: 3.2,
        recommendedMinMemoryGB: 8,
        stabilityTier: .default
    )

    static let gemma3Text4B = AIModelProfile(
        id: "mlx-community/gemma-3-text-4b-it-4bit",
        displayName: "Gemma 3 Text 4B IT (MLX)",
        displayFormat: "MLX 4-bit",
        recommendedMaxTokens: 700,
        qualityTier: .balanced,
        memoryHint: "Petit",
        estimatedDownloadGB: 3.2,
        recommendedMinMemoryGB: 8,
        stabilityTier: .default
    )

    static let qwen3_14B4bitDWQ = AIModelProfile(
        id: "mlx-community/Qwen3-14B-4bit-DWQ-053125",
        displayName: "Qwen 3 14B (MLX)",
        displayFormat: "MLX 4-bit (DWQ)",
        recommendedMaxTokens: 160,
        qualityTier: .quality,
        memoryHint: "Qualité+ macOS (contexte court)",
        estimatedDownloadGB: 9.5,
        recommendedMinMemoryGB: 24,
        stabilityTier: .quality
    )

    static let qwen36_27BMoE = AIModelProfile(
        id: "mlx-community/Qwen3.6-27B-4bit",
        displayName: "Qwen 3.6 27B MoE (MLX)",
        displayFormat: "MLX 4-bit",
        recommendedMaxTokens: 384,
        qualityTier: .quality,
        memoryHint: "16 GB+ (contexte court)",
        estimatedDownloadGB: 16.8,
        recommendedMinMemoryGB: 24,
        stabilityTier: .experimental
    )

    static let qwen36_35BA3BMoE = AIModelProfile(
        id: "mlx-community/Qwen3.6-35B-A3B-4bit",
        displayName: "Qwen 3.6 35B A3B MoE (MLX)",
        displayFormat: "MLX 4-bit",
        recommendedMaxTokens: 256,
        qualityTier: .quality,
        memoryHint: "24 GB+",
        estimatedDownloadGB: 24.0,
        recommendedMinMemoryGB: 32,
        stabilityTier: .experimental
    )

    static let gemma4_26BA4BMoE = AIModelProfile(
        id: "mlx-community/gemma-4-26b-a4b-4bit",
        displayName: "Gemma 4 26B A4B MoE (MLX)",
        displayFormat: "MLX 4-bit",
        recommendedMaxTokens: 320,
        qualityTier: .quality,
        memoryHint: "24 GB+",
        estimatedDownloadGB: 18.0,
        recommendedMinMemoryGB: 32,
        stabilityTier: .experimental
    )

    static let gemma4E2B = AIModelProfile(
        id: "mlx-community/gemma-4-e2b-it-4bit",
        displayName: "Gemma 4 E2B IT (MLX)",
        displayFormat: "MLX 4-bit",
        recommendedMaxTokens: 640,
        qualityTier: .fast,
        memoryHint: "Petit (multimodal)",
        estimatedDownloadGB: 2.7,
        recommendedMinMemoryGB: 8,
        stabilityTier: .default
    )

    static let gemma4E4B = AIModelProfile(
        id: "mlx-community/gemma-4-e4b-it-4bit",
        displayName: "Gemma 4 E4B IT (MLX)",
        displayFormat: "MLX 4-bit",
        recommendedMaxTokens: 700,
        qualityTier: .balanced,
        memoryHint: "Petit (multimodal)",
        estimatedDownloadGB: 5.2,
        recommendedMinMemoryGB: 8,
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
        .gemma4E2B,
        .gemma4E4B,
        .qwen31_7B,
        .gemma34B,
        .gemma3Text4B,
        .qwen3_14B4bitDWQ,
        .qwen36_27BMoE,
        .qwen36_35BA3BMoE,
        .gemma4_26BA4BMoE
    ]

    static func profile(for id: String) -> AIModelProfile {
        allProfiles.first(where: { $0.id == id }) ?? .gemma4E2B
    }

    static func defaultProfile(for tier: AIQualityTier) -> AIModelProfile {
        switch tier {
        case .fast:
            return .gemma4E2B
        case .balanced:
            return .gemma4E4B
        case .quality:
            return .qwen3_14B4bitDWQ
        }
    }

    static func effectiveProfile(userModelID: String?, qualityTier: AIQualityTier) -> AIModelProfile {
        let requested = userModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !requested.isEmpty, let exact = allProfiles.first(where: { $0.id == requested }) {
            return exact
        }
        return defaultProfile(for: qualityTier)
    }

    static func machineRecommendation(physicalMemoryGB: Int) -> String {
        if physicalMemoryGB < 16 {
            return "Machine détectée: \(physicalMemoryGB) GB. Recommandation: petits modèles MLX par défaut."
        }
        if physicalMemoryGB < 24 {
            return "Machine détectée: \(physicalMemoryGB) GB. Qwen 14B possible en contexte court, MoE déconseillés."
        }
        return "Machine détectée: \(physicalMemoryGB) GB. Recommandation: petits modèles par défaut; MoE uniquement en mode avancé."
    }

    static func memorySafeMaxTokens(
        requested: Int,
        profile: AIModelProfile,
        swapUsedGB: Double,
        conservativeMode: Bool,
        companionLLMRunning: Bool
    ) -> Int {
        guard conservativeMode else {
            return max(64, min(requested, profile.recommendedMaxTokens))
        }

        var cap = profile.recommendedMaxTokens

        if profile.isHeavyForNotes {
            cap = min(cap, 192)

            if companionLLMRunning {
                cap = min(cap, 128)
            }

            if swapUsedGB >= 2 {
                cap = min(cap, 160)
            }
            if swapUsedGB >= 8 {
                cap = min(cap, 128)
            }
            if swapUsedGB >= 16 {
                cap = min(cap, 96)
            }
        } else if swapUsedGB >= 16 {
            cap = min(cap, 256)
        }

        return max(64, min(requested, cap))
    }
}
