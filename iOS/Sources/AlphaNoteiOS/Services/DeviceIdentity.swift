import Foundation

enum DeviceIdentity {
    private static let storageKey = "alphaNoteDeviceID"

    static var currentDeviceID: String {
        if let existing = UserDefaults.standard.string(forKey: storageKey), !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: storageKey)
        return created
    }
}
