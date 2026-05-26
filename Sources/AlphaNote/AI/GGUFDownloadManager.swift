import Foundation

actor GGUFDownloadManager {
    static let shared = GGUFDownloadManager()

    static func modelsDirectory() -> String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return home + "/.alphanote/models"
    }

    static func localPath(for profile: AIModelProfile) -> String {
        modelsDirectory() + "/" + profile.id + "/" + profile.ggufFilename
    }

    static func isModelDownloaded(_ modelID: String) -> Bool {
        let profile = AIModelRegistry.profile(for: modelID)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: localPath(for: profile), isDirectory: &isDir) && !isDir.boolValue
    }

    nonisolated func downloadURL(for profile: AIModelProfile) -> URL {
        URL(string: "https://huggingface.co/\(profile.hfRepo)/resolve/main/\(profile.ggufFilename)")!
    }

    func fetchFileSize(for profile: AIModelProfile) async -> Int64 {
        let apiURL = URL(string: "https://huggingface.co/api/models/\(profile.hfRepo)?expand[]=siblings")!
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 10
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let siblings = json["siblings"] as? [[String: Any]] else { return 0 }
            for sib in siblings {
                if let name = sib["rfilename"] as? String,
                   name == profile.ggufFilename,
                   let lfs = sib["lfs"] as? [String: Any],
                   let size = lfs["size"] as? Int64 {
                    return size
                }
                if let name = sib["rfilename"] as? String,
                   name == profile.ggufFilename,
                   let size = sib["size"] as? Int64,
                   size > 0 {
                    return size
                }
            }
        } catch {}
        return 0
    }

    func download(
        modelID: String,
        onProgress: @escaping @Sendable (String, Double?) -> Void
    ) async throws {
        let profile = AIModelRegistry.profile(for: modelID)
        let modelsDir = Self.modelsDirectory()
        let modelDir = modelsDir + "/" + profile.id
        let destPath = modelDir + "/" + profile.ggufFilename

        let fm = FileManager.default
        try fm.createDirectory(atPath: modelDir, withIntermediateDirectories: true, attributes: nil)

        let totalSize = await fetchFileSize(for: profile)
        onProgress("Téléchargement de \(profile.displayName) depuis HuggingFace...", nil)

        let url = downloadURL(for: profile)

        let delegate = DownloadDelegate(
            totalSize: totalSize,
            onProgress: onProgress,
            displayName: profile.displayName
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, response) = try await session.download(from: url)
        let httpResponse = response as? HTTPURLResponse

        guard httpResponse?.statusCode == 200 else {
            throw AIError.internalFailure("Échec du téléchargement: HTTP \(httpResponse?.statusCode ?? 0)")
        }

        if fm.fileExists(atPath: destPath) {
            try fm.removeItem(atPath: destPath)
        }
        try fm.moveItem(atPath: tempURL.path, toPath: destPath)

        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize > 0 ? totalSize : (fm.fileExists(atPath: destPath) ? (try? fm.attributesOfItem(atPath: destPath)[.size] as? Int64) ?? 0 : 0), countStyle: .file)
        onProgress("Téléchargement terminé: \(profile.displayName) (\(sizeStr))", 1.0)
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let totalSize: Int64
    let onProgress: @Sendable (String, Double?) -> Void
    let displayName: String
    let startTime = Date()

    init(totalSize: Int64, onProgress: @escaping @Sendable (String, Double?) -> Void, displayName: String) {
        self.totalSize = totalSize
        self.onProgress = onProgress
        self.displayName = displayName
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let effectiveTotal = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : totalSize
        guard effectiveTotal > 0 else { return }

        let fraction = Double(totalBytesWritten) / Double(effectiveTotal)
        let elapsed = max(Date().timeIntervalSince(startTime), 1)
        let speed = Double(totalBytesWritten) / elapsed
        let speedStr = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
        let writtenStr = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
        let totalStr = ByteCountFormatter.string(fromByteCount: effectiveTotal, countStyle: .file)

        onProgress("\(writtenStr) / \(totalStr) — \(speedStr)/s — \(Int(fraction * 100))%", fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {}
}
