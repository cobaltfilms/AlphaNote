import Foundation
#if canImport(AppKit)
import AppKit
#endif

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

enum AIModelDiagnostics {
    static func physicalMemoryGB() -> Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    static func swapUsedGB() -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        process.arguments = ["vm.swapusage"]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return 0 }
            let output = String(
                data: out.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            return parseSwapUsedGB(from: output)
        } catch {
            return 0
        }
    }

    static func isCotypistRunning() -> Bool {
        #if canImport(AppKit)
        let apps = NSWorkspace.shared.runningApplications
        return apps.contains { app in
            if let bundleID = app.bundleIdentifier?.lowercased(), bundleID.contains("cotypist") {
                return true
            }
            if let name = app.localizedName?.lowercased(), name.contains("cotypist") {
                return true
            }
            return false
        }
        #else
        return false
        #endif
    }

    static func companionLLMStatus() -> AICompanionLLMStatus {
        var labels = Set<String>()
        var residentKB: Double = 0

        let knownMarkers: [(needle: String, label: String)] = [
            ("cotypist", "Cotypist"),
            ("ollama", "Ollama"),
            ("llama-server", "llama.cpp server"),
            ("llama.cpp", "llama.cpp"),
            ("lm studio", "LM Studio"),
            ("jan", "Jan"),
            ("msty", "Msty"),
            ("gpt4all", "GPT4All"),
            ("koboldcpp", "KoboldCpp"),
            ("mlx_lm.generate", "MLX-LM"),
            ("mlx_lm.server", "MLX-LM server"),
            ("vllm", "vLLM"),
            ("text-generation-webui", "text-generation-webui"),
            ("localai", "LocalAI")
        ]

        #if canImport(AppKit)
        for app in NSWorkspace.shared.runningApplications {
            let name = app.localizedName?.lowercased() ?? ""
            let bundle = app.bundleIdentifier?.lowercased() ?? ""
            for marker in knownMarkers {
                if name.contains(marker.needle) || bundle.contains(marker.needle) {
                    labels.insert(marker.label)
                }
            }
        }
        #endif

        for line in runningProcessSnapshotLines() {
            let lower = line.lowercased()
            for marker in knownMarkers where lower.contains(marker.needle) {
                labels.insert(marker.label)
                residentKB += parseLeadingRSSKB(from: line)
            }
        }

        let sources = labels.sorted()
        return AICompanionLLMStatus(
            isDetected: !sources.isEmpty,
            detectedSources: sources,
            estimatedResidentGB: max(0, residentKB / 1_048_576.0)
        )
    }

    static func localStatus(for modelID: String) -> AIModelLocalStatus {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cachePath = huggingFaceModelCachePath(for: trimmed)
        let rootURL = URL(fileURLWithPath: cachePath)
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: cachePath, isDirectory: &isDir), isDir.boolValue else {
            return AIModelLocalStatus(
                modelID: trimmed,
                isDownloaded: false,
                cachePath: cachePath,
                cachedSizeBytes: 0,
                updatedAt: nil
            )
        }

        let snapshotsURL = rootURL.appendingPathComponent("snapshots", isDirectory: true)
        let refsURL = rootURL.appendingPathComponent("refs", isDirectory: true)
        let snapshotExists = fm.fileExists(atPath: snapshotsURL.path)
        let refsExist = fm.fileExists(atPath: refsURL.path)
        let downloaded = snapshotExists || refsExist

        let size = directorySize(at: rootURL)
        let updatedAt = latestModificationDate(at: rootURL)

        return AIModelLocalStatus(
            modelID: trimmed,
            isDownloaded: downloaded,
            cachePath: cachePath,
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
        if lower.contains("pytorch >= 2.4") || lower.contains("found 2.0.0") {
            let hint = AIManagedRuntime.diagnose().summary
            return "Environnement MLX incomplet: PyTorch est trop ancien pour ce modèle. \(hint)"
        }
        if lower.contains("model not found") {
            return "Modèle introuvable. Vérifie l'ID du modèle dans les réglages."
        }
        if lower.contains("module specification for 'mlx_lm") || lower.contains("no module named 'mlx_lm") {
            return "Runtime IA incomplet: le module mlx-lm est absent. Clique sur « Réparer runtime IA »."
        }
        if lower.contains("module specification for 'mlx_vlm") || lower.contains("no module named 'mlx_vlm") {
            return "Runtime IA incomplet: le module mlx-vlm est absent pour ce modèle Gemma 4. Clique sur « Réparer runtime IA »."
        }
        if lower.contains("no module named mlx_lm") || lower.contains("mlx_lm.generate: command not found") {
            return "MLX-LM n'est pas disponible sur ce Mac. Vérifie l'installation locale."
        }
        if lower.contains("no module named mlx_vlm") || lower.contains("mlx_vlm.generate: command not found") {
            return "MLX-VLM n'est pas disponible sur ce Mac. Clique sur « Réparer runtime IA »."
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

    private static func huggingFaceModelCachePath(for modelID: String) -> String {
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let hfHome = env["HF_HOME"] ?? (home + "/.cache/huggingface")
        let repoPath = modelID.replacingOccurrences(of: "/", with: "--")
        return hfHome + "/hub/models--" + repoPath
    }

    private static func parseSwapUsedGB(from raw: String) -> Double {
        let pattern = #"used\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*([KMGTP])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let valueRange = Range(match.range(at: 1), in: raw),
              let unitRange = Range(match.range(at: 2), in: raw),
              let value = Double(raw[valueRange]) else {
            return 0
        }

        let unit = raw[unitRange].uppercased()
        let gb: Double
        switch unit {
        case "K":
            gb = value / 1_048_576.0
        case "M":
            gb = value / 1_024.0
        case "G":
            gb = value
        case "T":
            gb = value * 1_024.0
        default:
            gb = 0
        }
        return max(0, gb)
    }

    private static func runningProcessSnapshotLines() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "rss=,comm=,args="]
        let out = Pipe()
        process.standardOutput = out
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let text = String(
                data: out.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            return text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    private static func parseLeadingRSSKB(from line: String) -> Double {
        let parts = line.split(whereSeparator: { $0.isWhitespace })
        guard let first = parts.first, let rss = Double(first) else { return 0 }
        return max(0, rss)
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
