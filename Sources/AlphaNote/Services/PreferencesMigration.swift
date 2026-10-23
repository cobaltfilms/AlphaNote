import Foundation

enum PreferencesMigration {
    private static let migrationFlagKey = "preferencesMigratedFromLegacyDomainsV1"

    private static let trackedKeys: Set<String> = [
        "hotkeyEnabled",
        "hotkeyKeyCode",
        "hotkeyModifiers",
        "alwaysOnTop",
        "showInDock",
        "showInMenuBar",
        "autoCleanup",
        "theme",
        "fontSize",
        "keywordMath",
        "keywordList",
        "keywordCode",
        "keywordTimer",
        "listCheckTrigger",
        "listModeShortcutKey",
        "listModeShortcutModifiers",
        "archivedNoteIDs",
        "archivedIDsMigratedToDatabase",
        DatabaseManager.databaseLocationUserDefaultsKey,
        "syncEnabled",
        "syncIntervalMinutes",
        "nextcloudServerURL",
        "nextcloudUsername",
        AISettingsKeys.enabled,
        AISettingsKeys.jevURL,
        AISettingsKeys.jevDelaiMs
    ]

    private static let legacyDomainCandidates = [
        "AlphaNote",
        "com.cobaltfilms.alphanote",
        "be.cobaltfilms.alphanote"
    ]

    static func migrateLegacyDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationFlagKey) {
            return
        }
        defer {
            defaults.set(true, forKey: migrationFlagKey)
        }

        guard let source = bestLegacyDomain(defaults) else {
            return
        }
        let currentScore = currentPreferencesScore(defaults)
        guard source.score > currentScore else { return }

        for (key, value) in source.values {
            if defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
    }

    private static func currentPreferencesScore(_ defaults: UserDefaults) -> Int {
        trackedKeys.reduce(into: 0) { partial, key in
            if defaults.object(forKey: key) != nil {
                partial += 1
            }
        }
    }

    private static func bestLegacyDomain(_ defaults: UserDefaults) -> (name: String, values: [String: Any], score: Int)? {
        let currentDomain = Bundle.main.bundleIdentifier ?? ""
        var best: (name: String, values: [String: Any], score: Int)?

        for domain in legacyDomainCandidates where domain != currentDomain {
            guard let values = defaults.persistentDomain(forName: domain), !values.isEmpty else {
                continue
            }

            let matchedKeys = trackedKeys.intersection(values.keys)
            let score = matchedKeys.count + (values[DatabaseManager.databaseLocationUserDefaultsKey] != nil ? 2 : 0)
            guard score > 0 else { continue }

            if let currentBest = best {
                if score > currentBest.score {
                    best = (domain, values, score)
                }
            } else {
                best = (domain, values, score)
            }
        }

        return best
    }
}
