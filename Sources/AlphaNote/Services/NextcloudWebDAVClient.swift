import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct RemoteNotePayload {
    let dto: CloudNoteDTO
    let etag: String?
}

struct RemoteFileEntry {
    let href: String
    let etag: String?
}

struct RemoteTextFile {
    let path: String
    let content: String
}

enum NextcloudClientError: LocalizedError {
    case invalidServerURL
    case unauthorized
    case forbidden
    case httpStatus(Int)
    case invalidResponse
    case importFolderNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Invalid server URL."
        case .unauthorized:
            return "Invalid Nextcloud credentials (401)."
        case .forbidden:
            return "Access denied by Nextcloud (403)."
        case let .httpStatus(code):
            return "Unexpected server response (\(code))."
        case .invalidResponse:
            return "Unexpected server response format."
        case let .importFolderNotFound(path):
            return "Nextcloud folder not found: \(path)"
        }
    }
}

final class NextcloudWebDAVClient {
    private let username: String
    private let password: String
    private let session: URLSession
    private let serverBaseURL: URL
    private let webDAVRootURL: URL
    private let alphaFolderURL: URL
    private let notesFolderURL: URL
    private let manifestURL: URL
    private let attachmentsFolderURL: URL
    /// Envois et téléchargements de pièces jointes : même silence maximal, mais
    /// une durée totale bien plus longue (une note vocale peut peser lourd).
    private let transferSession: URLSession

    init(serverURL: String, username: String, password: String) throws {
        guard let baseURL = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              baseURL.scheme?.hasPrefix("http") == true else {
            throw NextcloudClientError.invalidServerURL
        }

        self.username = username
        self.password = password

        let config = URLSessionConfiguration.default
        // Silence maximal entre deux paquets, puis durée totale d'une requête :
        // lister ~450 notes peut prendre plus de 15 s quand le serveur est
        // chargé, et l'ancienne limite totale de 15 s faisait échouer la synchro.
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: config)
        let transferConfig = URLSessionConfiguration.default
        transferConfig.timeoutIntervalForRequest = 60
        transferConfig.timeoutIntervalForResource = 3600
        self.transferSession = URLSession(configuration: transferConfig)

        let normalizedServer = NextcloudWebDAVClient.removeTrailingSlash(from: baseURL)
        self.serverBaseURL = normalizedServer
        let webDAVRoot = normalizedServer
            .appendingPathComponent("remote.php", isDirectory: true)
            .appendingPathComponent("dav", isDirectory: true)
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(username, isDirectory: true)
        self.webDAVRootURL = webDAVRoot

        self.alphaFolderURL = webDAVRoot.appendingPathComponent("AlphaNote", isDirectory: true)
        self.notesFolderURL = alphaFolderURL.appendingPathComponent("notes", isDirectory: true)
        self.manifestURL = alphaFolderURL.appendingPathComponent("manifest.json")
        self.attachmentsFolderURL = alphaFolderURL.appendingPathComponent(AttachmentSyncPlanner.folderName, isDirectory: true)
    }

    func testConnection() async throws {
        try await ensureDirectories()
        _ = try await fetchManifest()
    }

    func ensureDirectories() async throws {
        try await ensureDirectory(alphaFolderURL)
        try await ensureDirectory(notesFolderURL)
    }

    func listNotes() async throws -> [RemoteFileEntry] {
        let entries = try await propfind(url: notesFolderURL, depth: 1)
        return entries.filter { entry in
            entry.href.hasSuffix(".json")
        }
    }

    func fetchManifest() async throws -> ManifestDTO? {
        let result = try await sendRequest(url: manifestURL, method: "GET", expectedStatusCodes: [200, 404])
        if result.statusCode == 404 {
            return nil
        }

        let decoder = CloudJSONCoder.makeDecoder()
        return try decoder.decode(ManifestDTO.self, from: result.data)
    }

    func uploadManifest(_ manifest: ManifestDTO) async throws {
        let encoder = CloudJSONCoder.makeEncoder()
        let payload = try encoder.encode(manifest)
        _ = try await sendRequest(url: manifestURL, method: "PUT", body: payload, expectedStatusCodes: [200, 201, 204])
    }

    func fetchNote(uuid: String) async throws -> RemoteNotePayload? {
        let url = notesFolderURL.appendingPathComponent("\(uuid).json")
        let result = try await sendRequest(url: url, method: "GET", expectedStatusCodes: [200, 404])
        if result.statusCode == 404 {
            return nil
        }

        let decoder = CloudJSONCoder.makeDecoder()
        let dto = try decoder.decode(CloudNoteDTO.self, from: result.data)
        return RemoteNotePayload(dto: dto, etag: result.headers["Etag"] ?? result.headers["ETag"])
    }

    /// Envoie la note ; retourne l'ETag renvoyé par le serveur (nil s'il n'en
    /// donne pas), pour éviter de la re-télécharger à la sync suivante.
    @discardableResult
    func uploadNote(_ dto: CloudNoteDTO, etag: String?) async throws -> String? {
        let url = notesFolderURL.appendingPathComponent("\(dto.uuid).json")
        let encoder = CloudJSONCoder.makeEncoder()
        let payload = try encoder.encode(dto)

        var headers: [String: String] = [:]
        if let etag, !etag.isEmpty {
            headers["If-Match"] = etag
        }

        let statusCodes: Set<Int> = [200, 201, 204, 412]
        let result = try await sendRequest(url: url, method: "PUT", headers: headers, body: payload, expectedStatusCodes: statusCodes)
        if result.statusCode == 412 {
            throw NextcloudClientError.httpStatus(412)
        }
        return result.headers["Etag"] ?? result.headers["ETag"] ?? result.headers["etag"]
    }

    func deleteNote(uuid: String) async throws {
        let url = notesFolderURL.appendingPathComponent("\(uuid).json")
        _ = try await sendRequest(url: url, method: "DELETE", expectedStatusCodes: [200, 204, 404])
    }

    // MARK: Pièces jointes (`AlphaNote/attachments/<uuid de la note>/<nom>`)

    /// Dossiers de notes sous `attachments` (avec leur ETag) ; nil si le dossier
    /// `attachments` n'existe pas encore sur le serveur.
    func listAttachmentFolders() async throws -> [RemoteFileEntry]? {
        do {
            return try await propfind(url: attachmentsFolderURL, depth: 1)
        } catch let NextcloudClientError.httpStatus(code) where code == 404 {
            return nil
        }
    }

    /// Fichiers joints d'une note présents sur le serveur.
    func listAttachments(noteUUID: String) async throws -> [RemoteFileEntry] {
        do {
            return try await propfind(url: try attachmentFolderURL(noteUUID: noteUUID), depth: 1)
        } catch let NextcloudClientError.httpStatus(code) where code == 404 {
            return []
        }
    }

    /// Crée `attachments` (noteUUID nil) ou le dossier d'une note.
    func ensureAttachmentsFolder(noteUUID: String?) async throws {
        if let noteUUID {
            try await ensureDirectory(try attachmentFolderURL(noteUUID: noteUUID))
        } else {
            try await ensureDirectory(attachmentsFolderURL)
        }
    }

    /// Envoie le fichier tel quel, lu depuis le disque (jamais chargé en mémoire).
    func uploadAttachment(noteUUID: String, name: String, from fileURL: URL) async throws {
        var request = URLRequest(url: try attachmentURL(noteUUID: noteUUID, name: name))
        request.httpMethod = "PUT"
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await transferSession.upload(for: request, fromFile: fileURL)
        try Self.check(response, expected: [200, 201, 204])
    }

    /// Télécharge le fichier sur disque puis le met en place d'un seul geste
    /// (jamais de fichier à moitié écrit sous son nom final). Retourne false
    /// s'il n'est pas (ou plus) sur le serveur.
    func downloadAttachment(noteUUID: String, name: String, to target: URL) async throws -> Bool {
        var request = URLRequest(url: try attachmentURL(noteUUID: noteUUID, name: name))
        request.httpMethod = "GET"
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        let (downloaded, response) = try await transferSession.download(for: request)
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: downloaded) }
        if (response as? HTTPURLResponse)?.statusCode == 404 { return false }
        try Self.check(response, expected: [200])
        let size = (try fileManager.attributesOfItem(atPath: downloaded.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw NextcloudClientError.invalidResponse }

        let folder = target.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        // Même dossier (donc même volume) que la cible : le renommage final est atomique.
        let staging = folder.appendingPathComponent(".\(name).part")
        try? fileManager.removeItem(at: staging)
        try fileManager.moveItem(at: downloaded, to: staging)
        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: target)
        }
        return true
    }

    /// Supprime le dossier distant des pièces jointes d'une note (purge d'une
    /// note supprimée depuis plus de 30 jours).
    func deleteAttachments(noteUUID: String) async throws {
        _ = try await sendRequest(url: try attachmentFolderURL(noteUUID: noteUUID), method: "DELETE", expectedStatusCodes: [200, 204, 404])
    }

    private func attachmentFolderURL(noteUUID: String) throws -> URL {
        // Un UUID vide ou farfelu viserait un autre dossier (voire `attachments` entier).
        guard AttachmentSyncPlanner.isSafeNoteUUID(noteUUID) else { throw NextcloudClientError.invalidResponse }
        return attachmentsFolderURL.appendingPathComponent(noteUUID, isDirectory: true)
    }

    private func attachmentURL(noteUUID: String, name: String) throws -> URL {
        guard AttachmentSyncPlanner.isSafeName(name) else { throw NextcloudClientError.invalidResponse }
        return try attachmentFolderURL(noteUUID: noteUUID).appendingPathComponent(name)
    }

    private static func check(_ response: URLResponse, expected: Set<Int>) throws {
        guard let http = response as? HTTPURLResponse else { throw NextcloudClientError.invalidResponse }
        if http.statusCode == 401 { throw NextcloudClientError.unauthorized }
        if http.statusCode == 403 { throw NextcloudClientError.forbidden }
        guard expected.contains(http.statusCode) else { throw NextcloudClientError.httpStatus(http.statusCode) }
    }

    func listTextFiles(relativeFolderPath: String, recursive: Bool = true) async throws -> [RemoteTextFile] {
        let trimmedPath = relativeFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw NextcloudClientError.importFolderNotFound(relativeFolderPath)
        }

        let folderURL = urlForRelativeFolderPath(trimmedPath)
        var queue: [URL] = [folderURL]
        var visitedDirectories = Set<String>()
        var files: [RemoteTextFile] = []
        let allowedExtensions: Set<String> = ["md", "txt"]

        while !queue.isEmpty {
            let currentDirectory = queue.removeFirst()
            let directoryKey = Self.removeTrailingSlash(from: currentDirectory).absoluteString
            if visitedDirectories.contains(directoryKey) {
                continue
            }
            visitedDirectories.insert(directoryKey)

            let entries: [RemoteFileEntry]
            do {
                entries = try await propfind(url: currentDirectory, depth: 1)
            } catch let NextcloudClientError.httpStatus(code) where code == 404 {
                throw NextcloudClientError.importFolderNotFound(trimmedPath)
            }

            for entry in entries {
                guard let entryURL = resolvedURL(fromHref: entry.href) else { continue }
                let normalizedEntryURL = Self.removeTrailingSlash(from: entryURL)
                let normalizedDirectory = Self.removeTrailingSlash(from: currentDirectory)
                guard normalizedEntryURL != normalizedDirectory else { continue }

                let isDirectory = entry.href.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/")
                if isDirectory {
                    if recursive {
                        queue.append(entryURL)
                    }
                    continue
                }

                let fileExtension = entryURL.pathExtension.lowercased()
                guard allowedExtensions.contains(fileExtension) else { continue }

                let content = try await fetchTextFile(at: entryURL)
                let path = displayPath(for: entryURL, under: folderURL)
                files.append(RemoteTextFile(path: path, content: content))
            }
        }

        return files
    }

    private func ensureDirectory(_ url: URL) async throws {
        let result = try await sendRequest(url: url, method: "MKCOL", expectedStatusCodes: [201, 405, 301])
        if result.statusCode == 301 {
            throw NextcloudClientError.httpStatus(301)
        }
    }

    private func fetchTextFile(at url: URL) async throws -> String {
        let result = try await sendRequest(url: url, method: "GET", expectedStatusCodes: [200])
        if let text = String(data: result.data, encoding: .utf8) {
            return text
        }
        return String(decoding: result.data, as: UTF8.self)
    }

    private func propfind(url: URL, depth: Int) async throws -> [RemoteFileEntry] {
        let body = """
        <?xml version="1.0"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:getetag/>
          </d:prop>
        </d:propfind>
        """.data(using: .utf8)

        let result = try await sendRequest(
            url: url,
            method: "PROPFIND",
            headers: ["Depth": "\(depth)", "Content-Type": "application/xml"],
            body: body,
            expectedStatusCodes: [207]
        )

        return try WebDAVPropfindParser.parse(data: result.data)
    }

    private func sendRequest(
        url: URL,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        expectedStatusCodes: Set<Int>
    ) async throws -> (data: Data, statusCode: Int, headers: [String: String]) {
        var attempt = 0
        let maxAttempts = 3

        while true {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.httpBody = body
                request.setValue(authHeader(), forHTTPHeaderField: "Authorization")

                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw NextcloudClientError.invalidResponse
                }

                if http.statusCode == 401 { throw NextcloudClientError.unauthorized }
                if http.statusCode == 403 { throw NextcloudClientError.forbidden }

                if expectedStatusCodes.contains(http.statusCode) {
                    var normalizedHeaders: [String: String] = [:]
                    for (key, value) in http.allHeaderFields {
                        normalizedHeaders["\(key)"] = "\(value)"
                    }
                    return (data, http.statusCode, normalizedHeaders)
                }

                if shouldRetry(statusCode: http.statusCode, attempt: attempt, maxAttempts: maxAttempts) {
                    attempt += 1
                    try await Task.sleep(nanoseconds: backoffNanoseconds(forAttempt: attempt))
                    continue
                }

                throw NextcloudClientError.httpStatus(http.statusCode)
            } catch {
                if shouldRetry(error: error, attempt: attempt, maxAttempts: maxAttempts) {
                    attempt += 1
                    try await Task.sleep(nanoseconds: backoffNanoseconds(forAttempt: attempt))
                    continue
                }
                throw error
            }
        }
    }

    private func shouldRetry(statusCode: Int, attempt: Int, maxAttempts: Int) -> Bool {
        attempt + 1 < maxAttempts && (500...599).contains(statusCode)
    }

    private func shouldRetry(error: Error, attempt: Int, maxAttempts: Int) -> Bool {
        guard attempt + 1 < maxAttempts else { return false }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        let retryableCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorDNSLookupFailed
        ]

        return retryableCodes.contains(nsError.code)
    }

    private func backoffNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let delay = pow(2.0, Double(attempt - 1))
        return UInt64(delay * 400_000_000)
    }

    private func authHeader() -> String {
        let token = "\(username):\(password)"
        let encoded = Data(token.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private func urlForRelativeFolderPath(_ folderPath: String) -> URL {
        var sanitized = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        while sanitized.hasPrefix("/") {
            sanitized.removeFirst()
        }
        return webDAVRootURL.appendingPathComponent(sanitized, isDirectory: true)
    }

    private func resolvedURL(fromHref href: String) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let absolute = URL(string: trimmed), absolute.scheme?.hasPrefix("http") == true {
            return absolute
        }

        if trimmed.hasPrefix("/") {
            return URL(string: trimmed, relativeTo: serverBaseURL)?.absoluteURL
        }

        return URL(string: trimmed, relativeTo: serverBaseURL)?.absoluteURL
    }

    private func displayPath(for fileURL: URL, under folderURL: URL) -> String {
        let relativeToWebDAVRoot = fileURL.path.replacingOccurrences(of: webDAVRootURL.path, with: "")
        let relativeToFolder = fileURL.path.replacingOccurrences(of: folderURL.path, with: "")
        let candidate = relativeToFolder.count < relativeToWebDAVRoot.count ? relativeToFolder : relativeToWebDAVRoot
        return candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func removeTrailingSlash(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        let trimmedPath = components.path.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        components.path = trimmedPath
        return components.url ?? url
    }
}

private final class WebDAVPropfindParser: NSObject, XMLParserDelegate {
    private var entries: [RemoteFileEntry] = []
    private var currentElement = ""
    private var currentHref = ""
    private var currentEtag = ""
    private var inResponse = false

    static func parse(data: Data) throws -> [RemoteFileEntry] {
        let parser = XMLParser(data: data)
        let delegate = WebDAVPropfindParser()
        parser.delegate = delegate
        guard parser.parse() else {
            throw NextcloudClientError.invalidResponse
        }

        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let normalized = Self.localName(for: elementName)
        currentElement = normalized

        if normalized == "response" {
            inResponse = true
            currentHref = ""
            currentEtag = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inResponse else { return }

        switch currentElement {
        case "href":
            currentHref += string
        case "getetag":
            currentEtag += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let normalized = Self.localName(for: elementName)

        if normalized == "response" {
            inResponse = false
            let href = currentHref.trimmingCharacters(in: .whitespacesAndNewlines)
            if !href.isEmpty {
                entries.append(
                    RemoteFileEntry(
                        href: href,
                        etag: currentEtag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? nil
                            : currentEtag.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            }
        }

        currentElement = ""
    }

    private static func localName(for elementName: String) -> String {
        let lower = elementName.lowercased()
        if let colonIndex = lower.firstIndex(of: ":") {
            return String(lower[lower.index(after: colonIndex)...])
        }
        return lower
    }
}
