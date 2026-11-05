import Foundation
import UIKit
import UserNotifications

/// Fin de minuteur quand l'app n'est plus au premier plan : iOS suspend l'app,
/// la sonnerie en boucle de TimerSession ne peut plus jouer. On programme donc
/// une notification locale à l'heure de fin, avec la sonnerie choisie (version
/// .caf d'environ 28 s générée par scripts/ios.sh). Au premier plan, la
/// notification est masquée : la session sonne elle-même.
@MainActor
final class TimerNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TimerNotifier()
    private var askedPermission = false

    func install() {
        UNUserNotificationCenter.current().delegate = self
        TimerSession.onStateChange = { [weak self] session in
            self?.update(for: session)
        }
    }

    private func identifier(_ session: TimerSession) -> String { "timer-\(session.id)" }

    private func update(for session: TimerSession) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(session)])

        let request: UNNotificationRequest
        if session.state == .finished, UIApplication.shared.applicationState != .active {
            // L'app tournait encore en arrière-plan (session audio) : elle sonne
            // elle-même, la bannière sert seulement à y revenir.
            request = UNNotificationRequest(identifier: identifier(session), content: content(for: session, sound: nil), trigger: nil)
        } else if session.state == .running, session.mode != .stopwatch, session.remaining > 0 {
            // Si iOS suspend l'app, c'est cette notification qui sonnera.
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, session.remaining), repeats: false)
            request = UNNotificationRequest(identifier: identifier(session), content: content(for: session, sound: Self.sound()), trigger: trigger)
        } else {
            if session.state != .finished {
                center.removeDeliveredNotifications(withIdentifiers: [identifier(session)])
            }
            return
        }

        Task {
            if !askedPermission {
                askedPermission = true
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)
        }
    }

    private func content(for session: TimerSession, sound: UNNotificationSound?) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = session.mode == .alarm ? "Alarme \(TimerSession.clock(session.alarmTime))" : "Minuteur terminé"
        content.body = noteTitle(for: session.id) ?? "AlphaNote"
        content.sound = sound
        content.interruptionLevel = .timeSensitive
        return content
    }

    private func noteTitle(for uuid: String) -> String? {
        Note.fetchAll().first(where: { $0.uuid == uuid }).map(NoteFormatting.displayTitle)
    }

    private static func sound() -> UNNotificationSound {
        let name = "alarm-\(AlarmSound.current == .systeme ? AlarmSound.minuterie.rawValue : AlarmSound.current.rawValue).caf"
        guard Bundle.main.url(forResource: name, withExtension: nil) != nil else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(name))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // App au premier plan : TimerSession sonne déjà en boucle.
        notification.request.identifier.hasPrefix("timer-") ? [] : [.banner, .sound]
    }
}
