import Foundation

extension Notification.Name {
    /// Postée sur le thread principal quand de nouveaux taux de change sont
    /// disponibles : les éditeurs math réévaluent leurs lignes.
    static let alphaNoteCurrencyRatesDidUpdate = Notification.Name("alphaNoteCurrencyRatesDidUpdate")
}

/// Taux de change : cache synchrone (mémoire + UserDefaults, 1 h) et
/// rafraîchissement asynchrone. Jamais d'attente réseau sur le thread appelant :
/// une conversion dont le taux manque retourne nil et déclenche un
/// téléchargement en arrière-plan, puis la notification ci-dessus.
///
/// Sources (sans clé d'API) : Frankfurter (BCE) puis open.er-api.com en repli.
final class CurrencyRateService: @unchecked Sendable {
    static let shared = CurrencyRateService()

    struct Snapshot: Codable {
        let base: String
        let fetchedAt: Date
        let rates: [String: Double]
    }

    private let lock = NSLock()
    private var snapshots: [String: Snapshot] = [:]
    private var inFlight: Set<String> = []
    private let defaultsKey = "currencyRatesCacheV2"
    private let maxAge: TimeInterval = 3600
    private let session: URLSession

    /// Transport injectable pour les tests.
    var fetcher: (URL) async throws -> Data

    private let persists: Bool

    init(session: URLSession = .shared, persists: Bool = true) {
        self.session = session
        self.persists = persists
        self.fetcher = { url in
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }
        if persists { loadFromDefaults() }
    }

    // MARK: - Lecture synchrone

    /// Taux `from → to` s'il est en cache et frais. Sinon nil, et un
    /// rafraîchissement est lancé en arrière-plan.
    func rate(from: String, to: String) -> Double? {
        let base = from.uppercased()
        let quote = to.uppercased()
        if base == quote { return 1 }

        lock.lock()
        let snapshot = snapshots[base]
        lock.unlock()

        if let snapshot, Date().timeIntervalSince(snapshot.fetchedAt) < maxAge {
            return snapshot.rates[quote]
        }

        requestRefresh(base: base)
        // Un taux périmé vaut mieux que rien pendant le rafraîchissement.
        return snapshot?.rates[quote]
    }

    /// Vrai si une devise est connue d'un instantané (même périmé).
    func knowsCurrency(_ code: String) -> Bool {
        let upper = code.uppercased()
        lock.lock(); defer { lock.unlock() }
        if snapshots[upper] != nil { return true }
        return snapshots.values.contains { $0.rates[upper] != nil }
    }

    // MARK: - Rafraîchissement

    func requestRefresh(base: String) {
        let upper = base.uppercased()
        lock.lock()
        let alreadyRunning = inFlight.contains(upper)
        if !alreadyRunning { inFlight.insert(upper) }
        lock.unlock()
        guard !alreadyRunning else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.refresh(base: upper)
        }
    }

    @discardableResult
    func refresh(base: String) async -> Snapshot? {
        defer { markFinished(base) }

        for provider in Self.providers {
            guard let url = provider.url(base) else { continue }
            do {
                let data = try await fetcher(url)
                if let rates = provider.parse(data), !rates.isEmpty {
                    let snapshot = Snapshot(base: base, fetchedAt: Date(), rates: rates)
                    store(snapshot)
                    await MainActor.run {
                        NotificationCenter.default.post(name: .alphaNoteCurrencyRatesDidUpdate, object: nil)
                    }
                    return snapshot
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func markFinished(_ base: String) {
        lock.lock()
        inFlight.remove(base)
        lock.unlock()
    }

    // MARK: - Fournisseurs

    struct Provider {
        let url: (String) -> URL?
        let parse: (Data) -> [String: Double]?
    }

    static let providers: [Provider] = [
        Provider(
            url: { URL(string: "https://api.frankfurter.app/latest?from=\($0)") },
            parse: { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return json["rates"] as? [String: Double]
            }
        ),
        Provider(
            url: { URL(string: "https://open.er-api.com/v6/latest/\($0)") },
            parse: { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (json["result"] as? String) == "success" else { return nil }
                return json["rates"] as? [String: Double]
            }
        )
    ]

    // MARK: - Persistance

    private func store(_ snapshot: Snapshot) {
        lock.lock()
        snapshots[snapshot.base] = snapshot
        let all = snapshots
        lock.unlock()
        if persists, let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: Snapshot].self, from: data) else {
            return
        }
        lock.lock()
        snapshots = decoded
        lock.unlock()
    }

    /// Pour les tests : injecte un instantané sans réseau.
    func seed(base: String, rates: [String: Double], fetchedAt: Date = Date()) {
        store(Snapshot(base: base.uppercased(), fetchedAt: fetchedAt, rates: rates))
    }
}
