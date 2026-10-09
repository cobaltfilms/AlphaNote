import Foundation

/// Version affichée partout (réglages, sheet de mise à jour).
///
/// Lue depuis le bundle quand AlphaNote tourne en `.app` ; repli sur une
/// constante quand il tourne en `swift run` (binaire SPM nu, sans Info.plist).
enum AppVersion {
    static let fallback = "0.1.0"

    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? fallback
    }
}
