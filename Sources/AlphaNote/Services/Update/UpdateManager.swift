import SwiftUI
import AppKit

// MARK: - Appcast

/// Une entrée de l'appcast décrivant la dernière version disponible.
/// Même forme que le feed d'AlphaSUB/AlphaDCP, pour rester cohérent.
struct UpdateInfo: Decodable, Equatable {
    let version: String
    let build: String?
    let notes: String?
    let url: String
    let minimumSystemVersion: String?
}

// MARK: - Progress downloader

/// Téléchargement en une fois, écrit sur disque (pas tout en RAM) et rapporte
/// une fraction 0...1 au fur et à mesure des octets reçus.
private final class ProgressDownloader: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var session: URLSession!

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func download(_ request: URLRequest) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let response = downloadTask.response ?? URLResponse()
        let stable = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlphaNoteUpdate-\(UUID().uuidString).zip")
        do {
            try? FileManager.default.removeItem(at: stable)
            try FileManager.default.moveItem(at: location, to: stable)
            continuation?.resume(returning: (stable, response))
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
        session.finishTasksAndInvalidate()
    }
}

// MARK: - Update manager

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var showingSheet = false
    @Published var feedConfigurationError: String?

    private var didAutoCheck = false

    private init() {
        refreshFeedConfiguration()
    }

    var currentVersion: String { AppVersion.current }

    private var appcastURLString: String {
        (UserDefaults.standard.string(forKey: AISettingsKeys.updateAppcastURL) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func refreshFeedConfiguration() {
        if appcastURLString.isEmpty {
            feedConfigurationError = "Aucun canal de mise à jour configuré. Renseignez une Appcast URL."
        } else {
            feedConfigurationError = nil
        }
    }

    // MARK: Check

    /// Vérification silencieuse au lancement : ne fait rien si aucun canal n'est
    /// configuré, et ne montre l'interface que si une mise à jour existe.
    func checkOnLaunch() {
        guard !didAutoCheck else { return }
        didAutoCheck = true
        guard !appcastURLString.isEmpty else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        refreshFeedConfiguration()
        guard !appcastURLString.isEmpty, let url = URL(string: appcastURLString) else {
            if userInitiated {
                phase = .failed(feedConfigurationError ?? "Appcast URL invalide.")
                showingSheet = true
            }
            return
        }

        phase = .checking
        if userInitiated { showingSheet = true }

        Task {
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, _) = try await URLSession.shared.data(for: request)
                let info = try JSONDecoder().decode(UpdateInfo.self, from: data)

                let candidate = (info.build?.isEmpty == false ? info.build! : info.version)
                if VersionComparator.isNewer(candidate, than: currentVersion) {
                    phase = .available(info)
                    showingSheet = true
                } else {
                    phase = .upToDate
                }
            } catch {
                phase = .failed("Vérification impossible : \(error.localizedDescription)")
            }
        }
    }

    // MARK: Download + install

    func downloadAndInstall(_ info: UpdateInfo) {
        guard let url = URL(string: info.url) else {
            phase = .failed("L'URL de la mise à jour est invalide.")
            return
        }
        phase = .downloading(0)

        Task {
            do {
                let zipURL = try await download(from: url)
                phase = .installing
                let appURL = try unzipApp(at: zipURL)
                try relaunch(replacingWith: appURL)
            } catch {
                phase = .failed("Échec de la mise à jour : \(error.localizedDescription)")
            }
        }
    }

    private func download(from url: URL) async throws -> URL {
        let downloader = ProgressDownloader { [weak self] fraction in
            Task { @MainActor in
                guard let self else { return }
                if case .downloading = self.phase {
                    self.phase = .downloading(fraction)
                }
            }
        }
        let (dest, response) = try await downloader.download(URLRequest(url: url))

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: dest)
            throw UpdateError.message("Le serveur a répondu HTTP \(http.statusCode). La version a peut-être été retirée.")
        }

        var head = Data()
        if let handle = try? FileHandle(forReadingFrom: dest) {
            head = (try? handle.read(upToCount: 200)) ?? Data()
            try? handle.close()
        }
        guard head.prefix(2) == Data([0x50, 0x4B]) else {
            try? FileManager.default.removeItem(at: dest)
            throw UpdateError.message("Le téléchargement n'est pas un paquet valide (pas de zip).")
        }
        return dest
    }

    private func unzipApp(at zipURL: URL) throws -> URL {
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlphaNoteUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", zipURL.path, outDir.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw UpdateError.message("Impossible de décompresser la mise à jour.")
        }

        let fm = FileManager.default
        var urls = (try? fm.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "app" } ?? []
        for sub in (try? fm.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil)) ?? []
        where (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            urls += (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "app" } ?? []
        }

        let candidates = urls.map {
            UpdateBundleSelector.Candidate(
                name: $0.lastPathComponent,
                bundleIdentifier: Bundle(url: $0)?.bundleIdentifier
            )
        }
        let expectedName = Bundle.main.bundleURL.lastPathComponent

        switch UpdateBundleSelector.select(from: candidates,
                                           expectedName: expectedName,
                                           runningIdentifier: Bundle.main.bundleIdentifier) {
        case .success(let index):
            return urls[index]
        case .failure(.noBundleFound):
            throw UpdateError.message("La mise à jour ne contenait pas \(expectedName).")
        case .failure(.identityMismatch), .failure(.unknownRunningIdentity):
            throw UpdateError.message("La mise à jour téléchargée concerne une autre application ; elle n'a pas été installée.")
        }
    }

    /// Remplace le bundle en cours par le nouveau et relance, via un script
    /// détaché qui attend la fin de ce processus avant d'agir.
    private func relaunch(replacingWith newApp: URL) throws {
        let dest = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let log = "/tmp/alphanote-update-\(pid).log"

        let script = """
        #!/bin/bash
        exec >> "\(log)" 2>&1
        echo "$(date): update helper started, waiting for PID \(pid)"
        waited=0
        while kill -0 \(pid) 2>/dev/null; do
            sleep 0.5
            waited=$((waited + 1))
            if [ $waited -ge 60 ]; then kill -9 \(pid) 2>/dev/null; sleep 1; break; fi
        done
        sleep 1
        mv "\(dest.path)" "\(dest.path).old" || { echo "could not move old bundle aside"; exit 1; }
        /usr/bin/ditto "\(newApp.path)" "\(dest.path)" || { mv "\(dest.path).old" "\(dest.path)"; exit 1; }
        /usr/bin/xattr -dr com.apple.quarantine "\(dest.path)" 2>/dev/null
        /usr/bin/open "\(dest.path)"
        rm -rf "\(dest.path).old"
        rm -f "$0"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alphanote-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = ["-c", "(\(scriptURL.path) &)"]
        try launcher.run()

        Thread.sleep(forTimeInterval: 0.5)
        exit(0)
    }

    enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }
}
