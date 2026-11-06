import AppKit
import Foundation
import UserNotifications

/// Rappels de notes sur le Mac (0.6.0). Chaque rappel du texte devient une
/// notification système programmée à l'heure dite (UNCalendarNotificationTrigger),
/// qui s'affiche même si AlphaNote est fermée. Les rappels d'une note sont
/// remplacés à chaque sauvegarde, à chaque synchro et au lancement.
///
/// Sonnerie : si AlphaNote tourne, la sonnerie choisie (comme pour les minuteurs)
/// est jouée ; sinon le son système de la notification prend le relais.
/// Vibration : le Mac n'a pas de moteur de vibration. Le retour haptique du
/// trackpad n'existe que si AlphaNote est au premier plan.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    // UNUserNotificationCenter exige une vraie application (.app) : absente sous `swift test` ou `swift run`.
    private var center: UNUserNotificationCenter? { Bundle.main.bundlePath.hasSuffix(".app") ? UNUserNotificationCenter.current() : nil }
    private let alarm = AlarmPlayer()
    private static let kindsKey = "kinds"
    private static let separator = "|"

    /// À appeler une fois au lancement : prend la délégation et reprogramme tout.
    func start() {
        center?.delegate = self
        rescheduleAll()
        NotificationCenter.default.addObserver(forName: .alphaNoteDidSync, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rescheduleAll() }
        }
    }

    /// Remplace les rappels de la note par ceux de son texte.
    /// Une note sécurisée n'a jamais de rappel : son texte est chiffré.
    func sync(note: Note) {
        sync(noteUUID: note.uuid, title: note.title, content: note.content, isVault: note.isVault)
    }

    func sync(noteUUID: String, title: String, content: String, isVault: Bool) {
        let reminders = isVault ? [] : Reminders.parse(content)
        let now = Date()
        let prefix = noteUUID + Self.separator
        guard let center else { return }
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        guard !reminders.isEmpty else { return }

        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        for reminder in reminders where reminder.at > now {
            let body = UNMutableNotificationContent()
            body.title = title.isEmpty ? "Rappel" : title
            body.body = "Rappel de \(Self.clock(reminder.at))"
            body.interruptionLevel = .timeSensitive
            body.userInfo = [Self.kindsKey: reminder.kinds.map(\.rawValue)]
            body.sound = reminder.kinds.contains(.sonnerie) ? .default : nil
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.at)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let identifier = prefix + Reminders.formatter().string(from: reminder.at)
            center.add(UNNotificationRequest(identifier: identifier, content: body, trigger: trigger))
        }
    }

    /// Reprogramme les rappels de toutes les notes, par exemple après une synchro
    /// (les notes reçues ne passent pas par la sauvegarde locale).
    func rescheduleAll() {
        for note in Note.fetchAll() where note.content.localizedCaseInsensitiveContains("rappel") {
            sync(note: note)
        }
    }

    // MARK: - Présentation quand AlphaNote tourne

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let kinds = (notification.request.content.userInfo[Self.kindsKey] as? [String] ?? [])
            .compactMap { ReminderKind(rawValue: $0) }
        Task { @MainActor in
            if kinds.contains(.sonnerie) {
                // La sonnerie choisie joue une fois ; le son système est alors coupé.
                self.alarm.play(AlarmSound.current, loop: false)
            }
            if kinds.contains(.vibration) {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
        var options: UNNotificationPresentationOptions = [.banner, .list]
        completionHandler(options)
    }

    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
