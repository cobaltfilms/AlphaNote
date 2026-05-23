import Foundation

struct AIModelLocalStatus: Sendable {
    let modelID: String
    let isDownloaded: Bool
    let cachePath: String
    let cachedSizeBytes: Int64
    let updatedAt: Date?
}

struct AICompanionLLMStatus: Sendable {
    let isDetected: Bool
    let detectedSources: [String]
    let estimatedResidentGB: Double
}

/// iOS-adapted model diagnostics — no NSWorkspace, no sysctl.
/// Simplified for iOS sandbox constraints.
enum AIModelDiagnostics {
    static func physicalMemoryGB() -> Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    /// iOS: no swap — always returns 0.
    static func swapUsedGB() -> Double {
        0
    }

    /// iOS: no NSWorkspace — always returns false.
    static func isCotypistRunning() -> Bool {
        false
    }

    /// iOS: no companion LLM detection (no ps access on iOS).
    static func companionLLMStatus() -> AICompanionLLMStatus {
        AICompanionLLMStatus(
            isDetected: false,
            detectedSources: [],
            estimatedResidentGB: 0
        )
    }

    /// Check local Core ML model status.
    static func localStatus(for modelID: String) -> AIModelLocalStatus {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        // Core ML models are stored in the app's container
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDir = documents.appendingPathComponent("AlphaNote/CoreMLModels", isDirectory: true)
        let modelPath = modelsDir.appendingPathComponent("\(trimmed).mlmodelc").path

        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: modelPath, isDirectory: &isDir) && isDir.boolValue

        let size: Int64 = exists ? directorySize(at: URL(fileURLWithPath: modelPath)) : 0
        let updatedAt: Date? = exists ? latestModificationDate(at: URL(fileURLWithPath: modelPath)) : nil

        return AIModelLocalStatus(
            modelID: trimmed,
            isDownloaded: exists,
            cachePath: modelPath,
            cachedSizeBytes: size,
            updatedAt: updatedAt
        )
    }

    static func formatSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func parseProgressPercent(from line: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,3})%"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let value = Double(line[range]) else {
            return nil
        }
        return min(max(value / 100.0, 0.0), 1.0)
    }

    static func summarizedError(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("model not found") {
            return "Modèle Core ML introuvable. Télécharge un modèle dans Réglages > AI."
        }
        if lower.contains("coreml") && (lower.contains("error") || lower.contains("fail")) {
            return "Erreur d'inférence Core ML. Essaye le fallback heuristique dans les réglages."
        }
        return message
    }

    static func userFriendlyProgressLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        if lower.contains("fetching ") || lower.contains("downloading") || lower.contains("loading") {
            return trimmed
        }
        if lower.contains("files:") && lower.contains("%") {
            return trimmed
        }
        if lower.contains("traceback") || lower.hasPrefix("file \"") || lower.contains("disable") {
            return nil
        }
        return nil
    }

    private static func directorySize(at root: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else {
                continue
            }
            total += Int64(size)
        }
        return total
    }

    private static func latestModificationDate(at root: URL) -> Date? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return nil
        }

        var latest: Date?
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate else {
                continue
            }
            if let currentLatest = latest {
                if date > currentLatest {
                    latest = date
                }
            } else {
                latest = date
            }
        }
        return latest
    }
}
