import Foundation

final class MLXSwiftInferenceEngine: AIInferenceEngineProtocol, @unchecked Sendable {
    private let runner = MLXCommandRunner()

    func generate(
        prompt: String,
        system: String?,
        modelID: String,
        options: AIRequestOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let output = try await runner.generate(
                        prompt: prompt,
                        system: system,
                        modelID: modelID,
                        options: options
                    )
                    continuation.yield(output)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

actor MLXCommandRunner {
    func generate(prompt: String, system: String?, modelID: String, options: AIRequestOptions) async throws -> String {
        let mergedPrompt: String
        if let system, !system.isEmpty {
            mergedPrompt = "[SYSTEM]\n\(system)\n\n[USER]\n\(prompt)"
        } else {
            mergedPrompt = prompt
        }

        let process = Process()
        let command = resolveMLXGenerateCommand()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.argumentsPrefix + [
            "--model", modelID,
            "--prompt", mergedPrompt,
            "--max-tokens", String(options.maxTokens),
            "--temp", String(options.temperature),
            "--top-p", String(options.topP)
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw AIError.modelUnavailable
        }

        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                throw AIError.cancelled
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if Task.isCancelled {
            throw AIError.cancelled
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            if errorOutput.localizedCaseInsensitiveContains("no module named mlx_lm") ||
                errorOutput.localizedCaseInsensitiveContains("mlx_lm.generate: command not found") ||
                errorOutput.localizedCaseInsensitiveContains("not found") {
                throw AIError.modelUnavailable
            }
            if errorOutput.localizedCaseInsensitiveContains("model not found") {
                throw AIError.internalFailure(
                    "Modèle MLX introuvable ou non téléchargé. Vérifie l'ID du modèle dans les réglages IA."
                )
            }
            throw AIError.internalFailure(errorOutput.isEmpty ? "Échec d'exécution MLX local." : errorOutput)
        }

        let sanitized = sanitizeMLXOutput(output)
        guard !sanitized.isEmpty else {
            throw AIError.invalidOutput
        }
        return sanitized
    }

    private func resolveMLXGenerateCommand() -> (executable: String, argumentsPrefix: [String]) {
        let fm = FileManager.default

        let directCandidates = [
            "/opt/homebrew/bin/mlx_lm.generate",
            "/usr/local/bin/mlx_lm.generate"
        ]
        if let direct = directCandidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return (direct, [])
        }

        return ("/usr/bin/env", ["mlx_lm.generate"])
    }

    private func sanitizeMLXOutput(_ output: String) -> String {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                guard !$0.isEmpty else { return false }
                let lower = $0.lowercased()
                if lower.hasPrefix("loading") || lower.hasPrefix("prompt") || lower.hasPrefix("generating") {
                    return false
                }
                if lower.hasPrefix("generation:") || lower.contains("tokens-per-sec") || lower.hasPrefix("peak memory:") {
                    return false
                }
                if lower.hasPrefix("prompt eval") || lower.hasPrefix("eval:") || $0 == "==========" || $0 == "=========" {
                    return false
                }
                if $0.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil {
                    return false
                }
                return true
            }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct HeuristicFallbackInferenceEngine: AIInferenceEngineProtocol {
    func generate(
        prompt: String,
        system: String?,
        modelID: String,
        options: AIRequestOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("Moteur IA local indisponible (mode dégradé). Active un modèle MLX valide dans Réglages > AI.")
            continuation.finish()
        }
    }
}
