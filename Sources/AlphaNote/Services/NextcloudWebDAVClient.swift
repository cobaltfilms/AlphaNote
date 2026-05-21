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

enum NextcloudClientError: LocalizedError {
    case invalidServerURL
    case unauthorized
    case forbidden
    case httpStatus(Int)
    case invalidResponse

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
        }
    }
}

final class NextcloudWebDAVClient {
    private let username: String
    private let password: String
    private let session: URLSession
    private let alphaFolderURL: URL
    private let notesFolderURL: URL
    private let manifestURL: URL

    init(serverURL: String, username: String, password: String) throws {
        guard let baseURL = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              baseURL.scheme?.hasPrefix("http") == true else {
            throw NextcloudClientError.invalidServerURL
        }

        self.username = username
        self.password = password

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)

        let normalizedServer = NextcloudWebDAVClient.removeTrailingSlash(from: baseURL)
        let webDAVRoot = normalizedServer
            .appendingPathComponent("remote.php", isDirectory: true)
            .appendingPathComponent("dav", isDirectory: true)
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(username, isDirectory: true)

        self.alphaFolderURL = webDAVRoot.appendingPathComponent("AlphaNote", isDirectory: true)
        self.notesFolderURL = alphaFolderURL.appendingPathComponent("notes", isDirectory: true)
        self.manifestURL = alphaFolderURL.appendingPathComponent("manifest.json")
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

    func uploadNote(_ dto: CloudNoteDTO, etag: String?) async throws {
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
    }

    func deleteNote(uuid: String) async throws {
        let url = notesFolderURL.appendingPathComponent("\(uuid).json")
        _ = try await sendRequest(url: url, method: "DELETE", expectedStatusCodes: [200, 204, 404])
    }

    private func ensureDirectory(_ url: URL) async throws {
        let result = try await sendRequest(url: url, method: "MKCOL", expectedStatusCodes: [201, 405, 301])
        if result.statusCode == 301 {
            throw NextcloudClientError.httpStatus(301)
        }
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
