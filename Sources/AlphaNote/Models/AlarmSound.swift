#if os(macOS)
import AppKit
#endif
import AVFoundation

/// Sonnerie de fin de minuteur (Réglages › Général › Minuteur). Les dix
/// sonneries sont synthétisées par scripts/make-sounds.py, mêmes fichiers sur
/// Android ; « Verre » est le son système de macOS.
enum AlarmSound: String, CaseIterable, Identifiable {
    case minuterie, cloche, telephone, reveil, alerte, montre, sonar, cristal, bois, pulsation, systeme

    static let storageKey = "alarmSound"

    static var current: AlarmSound {
        AlarmSound(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .minuterie
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minuterie: return "Minuterie"
        case .cloche: return "Cloche"
        case .telephone: return "Téléphone"
        case .reveil: return "Réveil"
        case .alerte: return "Alerte"
        case .montre: return "Montre"
        case .sonar: return "Sonar"
        case .cristal: return "Cristal"
        case .bois: return "Bois"
        case .pulsation: return "Pulsation"
        #if os(macOS)
        case .systeme: return "Verre (macOS)"
        #else
        case .systeme: return "Son système"
        #endif
        }
    }

    /// Fichier embarqué ; nil pour le son système.
    var url: URL? {
        guard self != .systeme else { return nil }
        return Self.bundle.url(forResource: rawValue, withExtension: "m4a", subdirectory: "Sounds")
            ?? Self.bundle.url(forResource: rawValue, withExtension: "m4a")
    }

    /// Paquet SwiftPM sur macOS, app Xcode sur iOS.
    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}

/// Joue une sonnerie en boucle (minuteur) ou une fois (essai dans Réglages).
@MainActor
final class AlarmPlayer {
    private var player: AVAudioPlayer?
    #if os(macOS)
    private var systemSound: NSSound?

    var isPlaying: Bool { player?.isPlaying == true || systemSound?.isPlaying == true }
    #else
    var isPlaying: Bool { player?.isPlaying == true }
    #endif

    func play(_ sound: AlarmSound, loop: Bool) {
        stop()
        #if os(iOS)
        // Catégorie lecture : la sonnerie passe même avec le bouton silence.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        // Pas de son système en boucle sur iOS : on retombe sur « Minuterie ».
        let sound = sound.url == nil ? .minuterie : sound
        #endif
        if let url = sound.url, let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = loop ? -1 : 0
            player.prepareToPlay()
            player.play()
            self.player = player
            return
        }
        #if os(macOS)
        // Son système (ou fichier manquant) : « Glass » de macOS.
        if let system = NSSound(named: "Glass") {
            system.loops = loop
            system.play()
            systemSound = system
        }
        #endif
    }

    func stop() {
        player?.stop()
        player = nil
        #if os(macOS)
        systemSound?.stop()
        systemSound = nil
        #endif
    }
}
