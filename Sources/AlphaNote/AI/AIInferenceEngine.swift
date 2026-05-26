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

    func prepareModel(
        modelID: String,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await runner.prepareModel(modelID: modelID, onProgress: onProgress)
    }

    func unloadActiveModel() async {
        await runner.unloadActiveModel()
    }
}

actor MLXCommandRunner {
    private var activeProcess: Process?
    private var activeModelID: String?

    func generate(prompt: String, system: String?, modelID: String, options: AIRequestOptions) async throws -> String {
        try await stopProcessIfSwitchingModel(to: modelID)
        let (output, errorOutput, status) = try await runGenerate(
            prompt: prompt,
            system: system,
            modelID: modelID,
            options: options,
            onStderrLine: nil
        )
        return try finalizeOutput(output: output, errorOutput: errorOutput, status: status)
    }

    func prepareModel(modelID: String, onProgress: @escaping @Sendable (String) -> Void) async throws -> String {
        try await stopProcessIfSwitchingModel(to: modelID)
        let (output, errorOutput, status) = try await runGenerate(
            prompt: "Réponds uniquement OK",
            system: "Préparation du modèle local.",
            modelID: modelID,
            options: AIRequestOptions(temperature: 0, maxTokens: 12, topP: 1, stop: []),
            onStderrLine: onProgress
        )
        return try finalizeOutput(output: output, errorOutput: errorOutput, status: status)
    }

    func unloadActiveModel() async {
        guard let process = activeProcess, process.isRunning else {
            activeModelID = nil
            return
        }
        process.terminate()
        for _ in 0..<20 where process.isRunning {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if process.isRunning {
            process.interrupt()
        }
        activeModelID = nil
    }

    private func runGenerate(
        prompt: String,
        system: String?,
        modelID: String,
        options: AIRequestOptions,
        onStderrLine: (@Sendable (String) -> Void)?
    ) async throws -> (output: String, errorOutput: String, status: Int32) {
        let mergedPrompt: String
        if let system, !system.isEmpty {
            mergedPrompt = "[SYSTEM]\n\(system)\n\n[USER]\n\(prompt)"
        } else {
            mergedPrompt = prompt
        }

        let process = Process()
        let command = resolveMLXGenerateCommand(for: modelID)
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

        let state = StreamCaptureState(onStderrLine: onStderrLine)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            state.appendStdout(data)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            state.appendStderr(data)
        }

        do {
            try process.run()
        } catch {
            throw AIError.modelUnavailable
        }
        activeProcess = process
        activeModelID = modelID

        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                activeProcess = nil
                activeModelID = nil
                throw AIError.cancelled
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        state.appendStdout(stdout.fileHandleForReading.availableData)
        state.appendStderr(stderr.fileHandleForReading.availableData)

        activeProcess = nil
        activeModelID = modelID

        if Task.isCancelled {
            throw AIError.cancelled
        }

        let output = state.finalStdout
        let errorOutput = state.finalStderr
        return (output, errorOutput, process.terminationStatus)
    }

    private func finalizeOutput(output: String, errorOutput: String, status: Int32) throws -> String {
        guard status == 0 else {
            if errorOutput.localizedCaseInsensitiveContains("no module named mlx_lm") ||
                errorOutput.localizedCaseInsensitiveContains("no module named mlx_vlm") ||
                errorOutput.localizedCaseInsensitiveContains("mlx_lm.generate: command not found") ||
                errorOutput.localizedCaseInsensitiveContains("mlx_vlm.generate: command not found") ||
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

    private func stopProcessIfSwitchingModel(to nextModelID: String) async throws {
        guard let process = activeProcess,
              process.isRunning,
              let activeModelID,
              activeModelID != nextModelID else {
            return
        }
        process.terminate()
        for _ in 0..<20 where process.isRunning {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if process.isRunning {
            process.interrupt()
        }
        self.activeProcess = nil
    }

    private func resolveMLXGenerateCommand(for modelID: String) -> (executable: String, argumentsPrefix: [String]) {
        AIManagedRuntime.preferredGenerateCommand(for: modelID)
    }

    private func sanitizeMLXOutput(_ output: String) -> String {
        let withoutThinking = output
            .replacingOccurrences(
                of: #"<think>[\s\S]*?</think>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"</?think>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

        let lines = withoutThinking
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

private final class StreamCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private let onStderrLine: (@Sendable (String) -> Void)?
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stderrPending = ""

    init(onStderrLine: (@Sendable (String) -> Void)?) {
        self.onStderrLine = onStderrLine
    }

    var finalStdout: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var finalStderr: String {
        lock.lock()
        defer { lock.unlock() }
        if !stderrPending.isEmpty {
            onStderrLine?(stderrPending)
            stderrPending = ""
        }
        return String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func appendStdout(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        stdoutData.append(data)
        lock.unlock()
    }

    func appendStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        stderrData.append(data)
        let chunk = String(data: data, encoding: .utf8) ?? ""
        stderrPending += chunk
        let lines = splitCompletedLines(&stderrPending)
        lock.unlock()

        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onStderrLine?(line)
        }
    }

    private func splitCompletedLines(_ buffer: inout String) -> [String] {
        let separators = CharacterSet(charactersIn: "\n\r")
        let parts = buffer.components(separatedBy: separators)
        guard parts.count > 1 else { return [] }
        buffer = parts.last ?? ""
        return Array(parts.dropLast())
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
