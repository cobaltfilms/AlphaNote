import Foundation

enum AIRuntimeFamily: String, Codable, Sendable {
    case gguf
    case vlm
}

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
    let runtimeFamily: AIRuntimeFamily

    let hfRepo: String
    let ggufFilename: String

    var isHeavyForNotes: Bool {
        estimatedDownloadGB >= 8 || stabilityTier == .experimental
    }

    static let gemma4E4B = AIModelProfile(
        id: "gemma-4-e4b",
        displayName: "Gemma 4 E4B",
        displayFormat: "GGUF Q4_K_M",
        recommendedMaxTokens: 700,
        qualityTier: .balanced,
        memoryHint: "6.2 GB",
        estimatedDownloadGB: 6.2,
        recommendedMinMemoryGB: 8,
        stabilityTier: .default,
        runtimeFamily: .gguf,
        hfRepo: "unsloth/gemma-4-E4B-it-GGUF",
        ggufFilename: "gemma-4-E4B-it-Q4_K_M.gguf"
    )

    static let gemma4E2B = AIModelProfile(
        id: "gemma-4-e2b",
        displayName: "Gemma 4 E2B",
        displayFormat: "GGUF Q4_K_M",
        recommendedMaxTokens: 640,
        qualityTier: .fast,
        memoryHint: "3.2 GB",
        estimatedDownloadGB: 3.2,
        recommendedMinMemoryGB: 8,
        stabilityTier: .default,
        runtimeFamily: .gguf,
        hfRepo: "unsloth/gemma-4-E2B-it-GGUF",
        ggufFilename: "gemma-4-E2B-it-Q4_K_M.gguf"
    )

    static let gemma34B = AIModelProfile(
        id: "gemma-3-4b",
        displayName: "Gemma 3 4B",
        displayFormat: "GGUF Q4_K_M",
        recommendedMaxTokens: 640,
        qualityTier: .balanced,
        memoryHint: "2.3 GB",
        estimatedDownloadGB: 2.3,
        recommendedMinMemoryGB: 8,
        stabilityTier: .default,
        runtimeFamily: .gguf,
        hfRepo: "unsloth/gemma-3-4b-it-GGUF",
        ggufFilename: "gemma-3-4b-it-Q4_K_M.gguf"
    )

    static let qwen31_7B = AIModelProfile(
        id: "qwen3-1.7b",
        displayName: "Qwen 3 1.7B",
        displayFormat: "GGUF Q4_K_M",
        recommendedMaxTokens: 500,
        qualityTier: .fast,
        memoryHint: "1.2 GB",
        estimatedDownloadGB: 1.2,
        recommendedMinMemoryGB: 8,
        stabilityTier: .default,
        runtimeFamily: .gguf,
        hfRepo: "unsloth/Qwen3-1.7B-GGUF",
        ggufFilename: "Qwen3-1.7B-Q4_K_M.gguf"
    )

    static let gemma31B = AIModelProfile(
        id: "gemma-3-1b",
        displayName: "Gemma 3 1B",
        displayFormat: "GGUF Q4_K_M",
        recommendedMaxTokens: 400,
        qualityTier: .fast,
        memoryHint: "0.8 GB",
        estimatedDownloadGB: 0.8,
        recommendedMinMemoryGB: 4,
        stabilityTier: .default,
        runtimeFamily: .gguf,
        hfRepo: "unsloth/gemma-3-1b-it-GGUF",
        ggufFilename: "gemma-3-1b-it-Q4_K_M.gguf"
    )

    static let gemma4_26BA4BMoE = AIModelProfile(
        id: "gemma-4-26b-a4b",
        displayName: "Gemma 4 26B A4B",
        displayFormat: "GGUF Q4_K_M (UD)",
        recommendedMaxTokens: 320,
        qualityTier: .quality,
        memoryHint: "15.7 GB",
        estimatedDownloadGB: 15.7,
        recommendedMinMemoryGB: 32,
        stabilityTier: .experimental,
        runtimeFamily: .gguf,
        hfRepo: "unsloth/gemma-4-26B-A4B-it-GGUF",
        ggufFilename: "gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
    )

    static let qwen34B = AIModelProfile(
        id: "qwen3-4b",
        displayName: "Qwen 3 4B",
        displayFormat: "GGUF Q4_K_M",
        recommendedMaxTokens: 550,
        qualityTier: .balanced,
        memoryHint: "2.3 GB",
        estimatedDownloadGB: 2.3,
        recommendedMinMemoryGB: 8,
        stabilityTier: .default,
        runtimeFamily: .gguf,
        hfRepo: "unsloth/Qwen3-4B-GGUF",
        ggufFilename: "Qwen3-4B-Q4_K_M.gguf"
    )

    static let qwen38B = AIModelProfile(
        id: "qwen3-8b",
        displayName: "Qwen 3 8B",
        displayFormat: "GGUF Q4_K_M",
        recommendedMaxTokens: 500,
        qualityTier: .quality,
        memoryHint: "4.7 GB",
        estimatedDownloadGB: 4.7,
        recommendedMinMemoryGB: 8,
        stabilityTier: .default,
        runtimeFamily: .gguf,
        hfRepo: "unsloth/Qwen3-8B-GGUF",
        ggufFilename: "Qwen3-8B-Q4_K_M.gguf"
    )

    static let qwen330BA3BMoE = AIModelProfile(
        id: "qwen3-30b-a3b",
        displayName: "Qwen 3 30B A3B",
        displayFormat: "GGUF Q4_K_M",
        recommendedMaxTokens: 320,
        qualityTier: .quality,
        memoryHint: "13.7 GB",
        estimatedDownloadGB: 13.7,
        recommendedMinMemoryGB: 24,
        stabilityTier: .experimental,
        runtimeFamily: .gguf,
        hfRepo: "unsloth/Qwen3-30B-A3B-GGUF",
        ggufFilename: "Qwen3-30B-A3B-Q4_K_M.gguf"
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
    static let ggufCustomPath = "aiGGUFCustomPath"
}

enum AIModelRegistry {
    static let allProfiles: [AIModelProfile] = [
        .gemma4E4B,
        .gemma4E2B,
        .gemma34B,
        .qwen31_7B,
        .gemma31B,
        .gemma4_26BA4BMoE,
        .qwen34B,
        .qwen38B,
        .qwen330BA3BMoE
    ]

    static func profile(for id: String) -> AIModelProfile {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return allProfiles.first(where: { $0.id == normalized }) ?? .gemma4E2B
    }

    static let bestAvailableModelID: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let cotypistPath = home + "/Library/Application Support/app.cotypist.Cotypist/Models/gemma-4-E2B-i1-Q4_K_M.gguf"
        if FileManager.default.fileExists(atPath: cotypistPath) {
            return AIModelProfile.gemma4E2B.id
        }
        for profile in allProfiles {
            if GGUFDownloadManager.isModelDownloaded(profile.id) {
                return profile.id
            }
        }
        return AIModelProfile.gemma4E2B.id
    }()

    static func defaultProfile(for tier: AIQualityTier) -> AIModelProfile {
        switch tier {
        case .fast:
            return .gemma4E2B
        case .balanced:
            return .gemma34B
        case .quality:
            return .qwen38B
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
            return "Machine détectée: \(physicalMemoryGB) GB. Modèles 1B–4B recommandés."
        }
        if physicalMemoryGB < 24 {
            return "Machine détectée: \(physicalMemoryGB) GB. Modèles jusqu'à 8B possibles."
        }
        return "Machine détectée: \(physicalMemoryGB) GB. Modèles MoE accessibles en mode avancé."
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
            if companionLLMRunning { cap = min(cap, 128) }
            if swapUsedGB >= 2 { cap = min(cap, 160) }
            if swapUsedGB >= 8 { cap = min(cap, 128) }
            if swapUsedGB >= 16 { cap = min(cap, 96) }
        } else if swapUsedGB >= 16 {
            cap = min(cap, 256)
        }

        return max(64, min(requested, cap))
    }

    static func requiresVLMRuntime(modelID: String) -> Bool {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if let profile = allProfiles.first(where: { $0.id == normalized }) {
            return profile.runtimeFamily == .vlm
        }
        return false
    }
}
