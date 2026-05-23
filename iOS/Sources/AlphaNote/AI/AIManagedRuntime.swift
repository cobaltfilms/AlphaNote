import Foundation

struct AIManagedRuntimeInfo: Sendable {
    let mode: String
    let pythonPath: String?
    let torchVersion: String?
    let isTorchCompatible: Bool
    let hasMLXLMModule: Bool
    let summary: String
}

enum AIManagedRuntimeError: Error, LocalizedError, Sendable {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(text):
            return text
        }
    }
}

enum AIManagedRuntime {
    private static let minTorchMajor = 2
    private static let minTorchMinor = 4

    static func preferredGenerateCommand() -> (executable: String, argumentsPrefix: [String]) {
        let managedInfo = diagnoseManagedRuntime()
        if let managedScript = managedGenerateScriptPath(),
           managedInfo.isTorchCompatible,
           managedInfo.hasMLXLMModule {
            return (managedScript, [])
        }

        if let managedPython = managedInfo.pythonPath,
           managedInfo.isTorchCompatible,
           managedInfo.hasMLXLMModule {
            return (managedPython, ["-m", "mlx_lm.generate"])
        }

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

    static func diagnose() -> AIManagedRuntimeInfo {
        let managedInfo = diagnoseManagedRuntime()
        if managedInfo.mode == "runtime-isole" && managedInfo.isTorchCompatible && managedInfo.hasMLXLMModule {
            return managedInfo
        }

        if managedInfo.mode == "runtime-isole" && (!managedInfo.isTorchCompatible || !managedInfo.hasMLXLMModule) {
            return AIManagedRuntimeInfo(
                mode: managedInfo.mode,
                pythonPath: managedInfo.pythonPath,
                torchVersion: managedInfo.torchVersion,
                isTorchCompatible: managedInfo.isTorchCompatible,
                hasMLXLMModule: managedInfo.hasMLXLMModule,
                summary: "Runtime IA isolé incomplet (torch ou mlx-lm). Fallback auto vers runtime système."
            )
        }

        if let script = resolveMLXGenerateScriptPath(),
           let python = runtimePythonFromScript(script),
           !python.isEmpty {
            let torch = readTorchVersion(pythonPath: python)
            let compatible = isTorchCompatible(version: torch)
            let hasModule = hasMLXLMModule(pythonPath: python)
            let torchLabel = torch ?? "inconnue"
            return AIManagedRuntimeInfo(
                mode: "systeme",
                pythonPath: python,
                torchVersion: torch,
                isTorchCompatible: compatible,
                hasMLXLMModule: hasModule,
                summary: "Runtime IA système: \(python) (torch \(torchLabel))."
            )
        }

        return AIManagedRuntimeInfo(
            mode: "indisponible",
            pythonPath: nil,
            torchVersion: nil,
            isTorchCompatible: false,
            hasMLXLMModule: false,
            summary: "Runtime IA non détecté."
        )
    }

    static func repairWithUV(
        onProgress: @escaping @Sendable (String) -> Void
    ) -> Result<AIManagedRuntimeInfo, AIManagedRuntimeError> {
        let uvPath: String
        if let existing = resolveCommandPath("uv") {
            uvPath = existing
        } else {
            onProgress("`uv` absent, installation automatique en cours...")
            switch installUVIfNeeded() {
            case let .success(path):
                uvPath = path
            case let .failure(error):
                return .failure(error)
            }
        }

        let runtimeDir = managedRuntimeDirectory()
        do {
            try FileManager.default.createDirectory(
                atPath: runtimeDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            return .failure(.message("Impossible de créer le dossier runtime IA: \(error.localizedDescription)"))
        }

        onProgress("Création du runtime IA isolé...")
        let venvResult = runCommand(
            executable: uvPath,
            arguments: ["venv", runtimeDir, "--python", "3.11"]
        )
        guard venvResult.status == 0 else {
            return .failure(.message("Échec création runtime IA: \(venvResult.output)"))
        }

        guard let managedPython = managedPythonPath() else {
            return .failure(.message("Runtime IA créé mais Python introuvable."))
        }

        onProgress("Installation des dépendances IA (peut prendre quelques minutes)...")
        let installResult = runCommand(
            executable: uvPath,
            arguments: [
                "pip", "install",
                "--python", managedPython,
                "--upgrade",
                "pip", "setuptools", "wheel",
                "torch>=2.4,<3",
                "mlx", "mlx-metal", "mlx-lm"
            ]
        )
        guard installResult.status == 0 else {
            return .failure(.message("Échec installation dépendances IA: \(installResult.output)"))
        }

        let info = diagnose()
        if info.mode != "runtime-isole" || !info.isTorchCompatible || !info.hasMLXLMModule {
            return .failure(.message("Runtime IA créé mais incomplet (torch/mlx-lm). \(info.summary)"))
        }
        return .success(info)
    }

    static func managedPythonPath() -> String? {
        let candidates = [
            managedRuntimeDirectory() + "/bin/python3",
            managedRuntimeDirectory() + "/bin/python"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    static func managedGenerateScriptPath() -> String? {
        let candidate = managedRuntimeDirectory() + "/bin/mlx_lm.generate"
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    private static func managedRuntimeDirectory() -> String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return home + "/.alphanote/runtime/mlx"
    }

    private static func runtimePythonFromScript(_ scriptPath: String) -> String? {
        guard let shebang = readShebang(from: scriptPath) else { return nil }
        if shebang.hasPrefix("/usr/bin/env ") {
            let command = shebang.replacingOccurrences(of: "/usr/bin/env ", with: "")
            return resolveCommandPath(command)
        }
        return shebang
    }

    private static func isTorchCompatible(version: String?) -> Bool {
        guard let version else { return false }
        let normalized = version.split(separator: "+").first.map(String.init) ?? version
        let parts = normalized.split(separator: ".")
        guard let major = parts.first.flatMap({ Int($0) }) else { return false }
        let minor = parts.dropFirst().first.flatMap { Int($0) } ?? 0
        if major > minTorchMajor { return true }
        if major < minTorchMajor { return false }
        return minor >= minTorchMinor
    }

    private static func resolveMLXGenerateScriptPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/mlx_lm.generate",
            "/usr/local/bin/mlx_lm.generate"
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        return resolveCommandPath("mlx_lm.generate")
    }

    private static func readShebang(from scriptPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: scriptPath),
              let text = String(data: data, encoding: .utf8),
              let first = text.components(separatedBy: .newlines).first,
              first.hasPrefix("#!") else {
            return nil
        }
        return String(first.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveCommandPath(_ command: String) -> String? {
        let result = runCommand(executable: "/usr/bin/which", arguments: [command])
        guard result.status == 0 else { return nil }
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func installUVIfNeeded() -> Result<String, AIManagedRuntimeError> {
        if let current = resolveCommandPath("uv") {
            return .success(current)
        }

        let install = runCommand(
            executable: "/bin/sh",
            arguments: ["-c", "curl -LsSf https://astral.sh/uv/install.sh | sh"]
        )
        guard install.status == 0 else {
            return .failure(.message("Installation automatique de `uv` échouée: \(install.output)"))
        }

        if let installed = resolveCommandPath("uv") {
            return .success(installed)
        }

        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let localUV = home + "/.local/bin/uv"
        guard FileManager.default.isExecutableFile(atPath: localUV) else {
            return .failure(.message("`uv` semble installé, mais introuvable dans le PATH."))
        }
        return .success(localUV)
    }

    private static func readTorchVersion(pythonPath: String) -> String? {
        let result = runCommand(
            executable: pythonPath,
            arguments: ["-c", "import torch; print(torch.__version__)"]
        )
        guard result.status == 0 else { return nil }
        let version = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    private static func hasMLXLMModule(pythonPath: String) -> Bool {
        let result = runCommand(
            executable: pythonPath,
            arguments: [
                "-c",
                "import importlib.util; print('1' if importlib.util.find_spec('mlx_lm') else '0')"
            ]
        )
        guard result.status == 0 else { return false }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private static func diagnoseManagedRuntime() -> AIManagedRuntimeInfo {
        guard let managedPython = managedPythonPath() else {
            return AIManagedRuntimeInfo(
                mode: "indisponible",
                pythonPath: nil,
                torchVersion: nil,
                isTorchCompatible: false,
                hasMLXLMModule: false,
                summary: "Runtime IA non détecté."
            )
        }
        let torch = readTorchVersion(pythonPath: managedPython)
        let compatible = isTorchCompatible(version: torch)
        let hasModule = hasMLXLMModule(pythonPath: managedPython)
        let torchLabel = torch ?? "inconnue"
        return AIManagedRuntimeInfo(
            mode: "runtime-isole",
            pythonPath: managedPython,
            torchVersion: torch,
            isTorchCompatible: compatible,
            hasMLXLMModule: hasModule,
            summary: "Runtime IA isolé: \(managedPython) (torch \(torchLabel))."
        )
    }

    @discardableResult
    private static func runCommand(executable: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
            let stdout = String(
                data: out.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let stderr = String(
                data: err.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let merged = [stdout, stderr]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus, merged)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
