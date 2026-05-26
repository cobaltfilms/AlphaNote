import Foundation

final class LlamaCppInferenceEngine: AIInferenceEngineProtocol, @unchecked Sendable {
    private let runner = LlamaCppServerRunner()

    static var isAvailable: Bool {
        let candidates = [
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server"
        ]
        return candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var serverPath: String? {
        let candidates = [
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

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

actor LlamaCppServerRunner {
    private var serverProcess: Process?
    private var serverPort: Int = 8080
    private var currentModelID: String?
    private var baseURL: String { "http://127.0.0.1:\(serverPort)" }
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 1
        self.session = URLSession(configuration: config)
    }

    private func resolveModelPath(for profile: AIModelProfile, modelID: String) -> String {
        let customPath = UserDefaults.standard
            .string(forKey: AISettingsKeys.ggufCustomPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !customPath.isEmpty, FileManager.default.fileExists(atPath: customPath) {
            return customPath
        }

        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let cotypistPath = home + "/Library/Application Support/app.cotypist.Cotypist/Models/gemma-4-E2B-i1-Q4_K_M.gguf"
        if profile.id == "gemma-4-e2b", FileManager.default.fileExists(atPath: cotypistPath) {
            return cotypistPath
        }

        return GGUFDownloadManager.localPath(for: profile)
    }

    func generate(prompt: String, system: String?, modelID: String, options: AIRequestOptions) async throws -> String {
        let profile = AIModelRegistry.profile(for: modelID)
        let modelPath = resolveModelPath(for: profile, modelID: modelID)

        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw AIError.modelUnavailable
        }

        guard let serverBin = LlamaCppInferenceEngine.serverPath else {
            throw AIError.modelUnavailable
        }

        if serverProcess == nil || currentModelID != modelID {
            try await restartServer(modelPath: modelPath, modelID: modelID, serverBin: serverBin)
        }

        let formattedPrompt = formatSinglePrompt(prompt: prompt, system: system)

        let requestBody: [String: Any] = [
            "prompt": formattedPrompt,
            "n_predict": options.maxTokens,
            "temperature": options.temperature,
            "top_p": options.topP,
            "stream": false
        ]

        guard let url = URL(string: "\(baseURL)/completion") else {
            throw AIError.internalFailure("Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.internalFailure("Invalid response from server")
        }

        if httpResponse.statusCode != 200 {
            let errorStr = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.internalFailure("Server error: \(httpResponse.statusCode) - \(errorStr)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? String else {
            throw AIError.invalidOutput
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restartServer(modelPath: String, modelID: String, serverBin: String) async throws {
        if let proc = serverProcess, proc.isRunning {
            proc.terminate()
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        serverPort = Int.random(in: 8080...8999)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverBin)
        process.arguments = [
            "-m", modelPath,
            "-c", "1024",
            "-ngl", "999",
            "--host", "127.0.0.1",
            "--port", String(serverPort),
            "-t", "4"
        ]

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        serverProcess = process
        currentModelID = modelID

        try await waitForServerReady(timeout: 30)
    }

    private func waitForServerReady(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if serverProcess == nil || !(serverProcess?.isRunning ?? false) {
                throw AIError.internalFailure("Server process died")
            }

            do {
                let url = URL(string: "\(baseURL)/health")!
                let (_, response) = try await session.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    return
                }
            } catch {
                // Not ready yet
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw AIError.internalFailure("Server timed out starting")
    }

    private func formatSinglePrompt(prompt: String, system: String?) -> String {
        if let sys = system, !sys.isEmpty {
            return "\(sys)\n\n\(prompt)"
        }
        return prompt
    }

    func stop() {
        serverProcess?.terminate()
        serverProcess = nil
        currentModelID = nil
    }
}
