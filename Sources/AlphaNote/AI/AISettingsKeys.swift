import Foundation

enum AISettingsKeys {
    static let enabled = "aiEnabled"
    static let jevURL = "jevURL"
    static let jevDelaiMs = "jevDelaiMs"
    /// Exception au contrat JEV : l'IA peut rédiger une formule en mode math.
    static let formulaDraftEnabled = "aiFormulaDraftEnabled"
    static let updateAppcastURL = "updateAppcastURL"

    static let jevURLDefault = "http://192.168.3.169:8096"
    static let jevDelaiMsDefault = 20_000
}
