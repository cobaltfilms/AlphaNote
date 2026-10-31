import Foundation

enum DeviceIdentity {
    private static let storageKey = "alphaNoteDeviceID"

    static var currentDeviceID: String {
        if let existing = UserDefaults.standard.string(forKey: storageKey), !existing.isEmpty {
            return existing
        }

        #if os(iOS)
        // Préfixé comme sur Android (« android-… ») : l'identifiant départage
        // les conflits de synchro et dit d'où vient la dernière modification.
        let created = "ios-" + UUID().uuidString.lowercased()
        #else
        let created = UUID().uuidString.lowercased()
        #endif
        UserDefaults.standard.set(created, forKey: storageKey)
        return created
    }
}
