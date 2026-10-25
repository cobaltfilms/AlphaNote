import Foundation
import AppKit
import AVFoundation
import Combine

/// État d'un minuteur, indépendant de la vue : il survit au changement de
/// note, à la fermeture de la fenêtre et au redémarrage (persisté dans
/// UserDefaults par UUID de note). La sonnerie appartient à la session, pas à
/// la vue, pour qu'un compte à rebours sonne même si la note n'est plus affichée.
@MainActor
final class TimerSession: ObservableObject, Identifiable {
    enum Mode: String, CaseIterable, Codable {
        case stopwatch, countdown, pomodoro

        var label: String {
            switch self {
            case .stopwatch: return "Chrono"
            case .countdown: return "Minuteur"
            case .pomodoro: return "Pomodoro"
            }
        }

        init?(keyword: String) {
            let lower = keyword.lowercased()
            if lower.contains("pomodoro") { self = .pomodoro }
            else if lower.contains("stopwatch") || lower.contains("chrono") { self = .stopwatch }
            else if lower.contains("countdown") || lower.contains("minuteur") { self = .countdown }
            else { return nil }
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

    private var runStartDate: Date?
    private var tick: Timer?
    private let alarm = AlarmPlayer()

    init(id: String, mode: Mode, targetDuration: TimeInterval) {
        self.id = id
        self.mode = mode
        self.targetDuration = targetDuration
    }

    // MARK: - Lecture

    var remaining: TimeInterval { max(0, targetDuration - elapsed) }

    var displayTime: String {
        let total = mode == .stopwatch ? elapsed : remaining
        return Self.format(total)
    }

    var progress: Double {
        guard mode != .stopwatch, targetDuration > 0 else { return 0 }
        return min(1, elapsed / targetDuration)
    }

    // MARK: - Commandes

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        reset()
        if newMode == .pomodoro { targetDuration = 25 * 60 }
        persist()
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
        case .running: pause()
        case .stopped, .paused: start()
        case .finished:
            reset()
            start()
        }
    }

    func start() {
        guard state != .running else { return }
        stopSound()
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
        NSApp.requestUserAttention(.criticalRequest)
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

    // MARK: - Persistance

    struct Snapshot: Codable {
        let mode: Mode
        let state: State
        let targetDuration: TimeInterval
        let elapsed: TimeInterval
        let runStartDate: Date?
    }

    func snapshot() -> Snapshot {
        Snapshot(mode: mode, state: state, targetDuration: targetDuration, elapsed: elapsed, runStartDate: runStartDate)
    }

    func restore(from snapshot: Snapshot) {
        mode = snapshot.mode
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

    private func persist() {
        TimerRegistry.shared.persist(self)
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
        let session = TimerSession(id: noteUUID, mode: defaultMode, targetDuration: TimeInterval(defaultSeconds))
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
