import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import AVFoundation
import Combine

/// État d'un minuteur, indépendant de la vue : il survit au changement de
/// note, à la fermeture de la fenêtre et au redémarrage (persisté dans
/// UserDefaults par UUID de note). La sonnerie appartient à la session, pas à
/// la vue, pour qu'un compte à rebours sonne même si la note n'est plus affichée.
@MainActor
final class TimerSession: ObservableObject, Identifiable {
    enum Mode: String, CaseIterable, Codable {
        /// `alarm` : sonne à une heure donnée (« alarm 07:30 »), pas après une durée.
        case stopwatch, countdown, alarm

        var label: String {
            switch self {
            case .stopwatch: return "Chrono"
            case .countdown: return "Minuteur"
            case .alarm: return "Alarme"
            }
        }

        init?(keyword: String) {
            let lower = keyword.lowercased()
            if lower.contains("alarm") { self = .alarm }
            else if lower.contains("stopwatch") || lower.contains("chrono") { self = .stopwatch }
            // « pomodoro » : ancien mode, relu comme un minuteur.
            else if lower.contains("countdown") || lower.contains("minuteur") || lower.contains("pomodoro") { self = .countdown }
            else { return nil }
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Mode(rawValue: raw) ?? .countdown
        }
    }

    enum State: String, Codable {
        case stopped, running, paused, finished
    }

    let id: String

    @Published private(set) var mode: Mode
    @Published private(set) var state: State = .stopped
    @Published private(set) var targetDuration: TimeInterval
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isSoundPlaying = false
    /// Heure de l'alarme, en secondes depuis minuit (mode `alarm`).
    @Published private(set) var alarmTime: Int

    private var runStartDate: Date?
    private var tick: Timer?
    private let alarm = AlarmPlayer()

    init(id: String, mode: Mode, targetDuration: TimeInterval, alarmTime: Int = 7 * 3600) {
        self.id = id
        self.mode = mode
        self.targetDuration = targetDuration
        self.alarmTime = Self.normalizedClock(alarmTime)
    }

    // MARK: - Lecture

    var remaining: TimeInterval { max(0, targetDuration - elapsed) }

    var displayTime: String {
        if mode == .alarm { return Self.clock(alarmTime) }
        let total = mode == .stopwatch ? elapsed : remaining
        return Self.format(total)
    }

    /// Valeur écrite dans la note : la durée, ou l'heure pour une alarme.
    var settingSeconds: TimeInterval {
        mode == .alarm ? TimeInterval(alarmTime) : targetDuration
    }

    var progress: Double {
        guard mode != .stopwatch, targetDuration > 0 else { return 0 }
        return min(1, elapsed / targetDuration)
    }

    // MARK: - Commandes

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        let leavingAlarm = mode == .alarm
        mode = newMode
        reset()
        // La durée servait au compte à rebours jusqu'à l'alarme.
        if leavingAlarm { targetDuration = 10 * 60 }
        persist()
    }

    /// Change l'heure de l'alarme ; armée, elle se recale sur la nouvelle heure.
    func setAlarmTime(_ secondsSinceMidnight: Int) {
        alarmTime = Self.normalizedClock(secondsSinceMidnight)
        if mode == .alarm, state == .running {
            elapsed = 0
            runStartDate = Date()
            targetDuration = Self.secondsUntil(alarmTime)
        }
        persist()
    }

    /// Passe en alarme à cette heure et l'arme (demande en langage naturel).
    func arm(alarmTime secondsSinceMidnight: Int) {
        if mode != .alarm { setMode(.alarm) }
        reset()
        alarmTime = Self.normalizedClock(secondsSinceMidnight)
        start()
    }

    func setTargetDuration(_ seconds: TimeInterval) {
        targetDuration = max(1, seconds)
        if state == .running, mode != .stopwatch, elapsed >= targetDuration {
            finish()
        }
        persist()
    }

    func toggle() {
        switch state {
        // Une alarme ne se met pas en pause : on la désarme.
        case .running: mode == .alarm ? reset() : pause()
        case .stopped, .paused: start()
        case .finished:
            reset()
            start()
        }
    }

    func start() {
        guard state != .running else { return }
        stopSound()
        if mode == .alarm {
            elapsed = 0
            targetDuration = Self.secondsUntil(alarmTime)
        }
        runStartDate = Date()
        state = .running
        scheduleTick()
        persist()
    }

    func pause() {
        guard state == .running else { return }
        syncElapsed()
        runStartDate = nil
        tick?.invalidate()
        tick = nil
        state = .paused
        persist()
    }

    func reset() {
        tick?.invalidate()
        tick = nil
        runStartDate = nil
        elapsed = 0
        state = .stopped
        stopSound()
        persist()
    }

    func stopSound() {
        alarm.stop()
        isSoundPlaying = false
    }

    // MARK: - Mécanique

    private func scheduleTick() {
        tick?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handleTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func handleTick() {
        guard state == .running else { return }
        syncElapsed()
        if mode != .stopwatch, elapsed >= targetDuration {
            finish()
        }
    }

    private func syncElapsed() {
        guard let runStartDate else { return }
        elapsed += Date().timeIntervalSince(runStartDate)
        self.runStartDate = Date()
    }

    private func finish() {
        tick?.invalidate()
        tick = nil
        runStartDate = nil
        elapsed = targetDuration
        state = .finished
        persist()
        playSound()
        #if os(macOS)
        NSApp.requestUserAttention(.criticalRequest)
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    private func playSound() {
        alarm.play(AlarmSound.current, loop: true)
        isSoundPlaying = true
    }

    static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// « 07:30 » pour 27 000 s depuis minuit.
    static func clock(_ secondsSinceMidnight: Int) -> String {
        let value = normalizedClock(secondsSinceMidnight)
        return String(format: "%02d:%02d", value / 3600, (value % 3600) / 60)
    }

    static func normalizedClock(_ seconds: Int) -> Int {
        let day = 24 * 3600
        return ((seconds / 60 * 60) % day + day) % day
    }

    /// Délai jusqu'à la prochaine occurrence de l'heure (demain si elle est passée).
    static func secondsUntil(_ secondsSinceMidnight: Int, from now: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        let value = normalizedClock(secondsSinceMidnight)
        let components = DateComponents(hour: value / 3600, minute: (value % 3600) / 60, second: 0)
        guard let next = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) else {
            return 24 * 3600
        }
        return max(1, next.timeIntervalSince(now))
    }

    // MARK: - Persistance

    struct Snapshot: Codable {
        let mode: Mode
        let state: State
        let targetDuration: TimeInterval
        let elapsed: TimeInterval
        let runStartDate: Date?
        var alarmTime: Int? = nil
    }

    func snapshot() -> Snapshot {
        Snapshot(mode: mode, state: state, targetDuration: targetDuration, elapsed: elapsed, runStartDate: runStartDate, alarmTime: alarmTime)
    }

    func restore(from snapshot: Snapshot) {
        mode = snapshot.mode
        if let saved = snapshot.alarmTime { alarmTime = Self.normalizedClock(saved) }
        targetDuration = snapshot.targetDuration
        elapsed = snapshot.elapsed
        state = snapshot.state
        if snapshot.state == .running, let start = snapshot.runStartDate {
            elapsed += Date().timeIntervalSince(start)
            if mode != .stopwatch, elapsed >= targetDuration {
                elapsed = targetDuration
                state = .finished
            } else {
                runStartDate = Date()
                scheduleTick()
            }
        }
    }

    /// Appelé à chaque changement d'état. iOS s'en sert pour programmer la
    /// notification de fin, qui sonne quand l'app n'est plus au premier plan.
    static var onStateChange: ((TimerSession) -> Void)?

    private func persist() {
        TimerRegistry.shared.persist(self)
        Self.onStateChange?(self)
    }
}

/// Une session par note (clé = UUID), créée à la demande et restaurée depuis
/// UserDefaults.
@MainActor
final class TimerRegistry {
    static let shared = TimerRegistry()
    private let defaultsKey = "timerSessionsV1"
    private var sessions: [String: TimerSession] = [:]

    func session(for noteUUID: String, defaultMode: TimerSession.Mode, defaultSeconds: Int) -> TimerSession {
        if let existing = sessions[noteUUID] {
            return existing
        }
        // Pour une alarme, defaultSeconds est l'heure (secondes depuis minuit).
        let session = defaultMode == .alarm
            ? TimerSession(id: noteUUID, mode: .alarm, targetDuration: 10 * 60, alarmTime: defaultSeconds)
            : TimerSession(id: noteUUID, mode: defaultMode, targetDuration: TimeInterval(defaultSeconds))
        if let snapshot = storedSnapshots()[noteUUID] {
            session.restore(from: snapshot)
        }
        sessions[noteUUID] = session
        return session
    }

    func discard(noteUUID: String) {
        sessions[noteUUID]?.reset()
        sessions.removeValue(forKey: noteUUID)
        var all = storedSnapshots()
        all.removeValue(forKey: noteUUID)
        save(all)
    }

    fileprivate func persist(_ session: TimerSession) {
        var all = storedSnapshots()
        if session.state == .stopped {
            all.removeValue(forKey: session.id)
        } else {
            all[session.id] = session.snapshot()
        }
        save(all)
    }

    private func storedSnapshots() -> [String: TimerSession.Snapshot] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: TimerSession.Snapshot].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func save(_ snapshots: [String: TimerSession.Snapshot]) {
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
