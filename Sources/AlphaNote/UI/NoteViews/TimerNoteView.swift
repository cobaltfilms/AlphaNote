import SwiftUI
import AVFoundation

struct TimerNoteView: View {
    enum TimerMode: String, CaseIterable {
        case stopwatch = "Stopwatch"
        case countdown = "Countdown"
        case pomodoro = "Pomodoro"

        init?(from content: String) {
            let lower = content.lowercased()
            if lower.contains("countdown") {
                self = .countdown
            } else if lower.contains("pomodoro") {
                self = .pomodoro
            } else if lower.contains("stopwatch") || lower.contains("chronometre") || lower.contains("chronomètre") {
                self = .stopwatch
            } else {
                return nil
            }
        }
    }

    enum TimerState {
        case stopped
        case running
        case paused
        case finished
    }

    var initialSeconds: Int = 600
    var initialMode: TimerMode = .countdown

    @State private var mode: TimerMode = .countdown
    @State private var state: TimerState = .stopped
    @State private var elapsed: TimeInterval = 0
    @State private var targetDuration: TimeInterval = 600
    @State private var timer: Timer?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isSoundPlaying = false

    @AppStorage("fontSize") private var fontSize: Double = 14

    private var displayTime: String {
        let total: TimeInterval
        switch mode {
        case .stopwatch:
            total = elapsed
        case .countdown, .pomodoro:
            total = max(0, targetDuration - elapsed)
        }
        return formatTime(total)
    }

    private var progress: Double {
        switch mode {
        case .stopwatch:
            return 0
        case .countdown, .pomodoro:
            guard targetDuration > 0 else { return 0 }
            return min(1, elapsed / targetDuration)
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(mode.rawValue)
                .font(.headline)
                .foregroundStyle(.secondary)

            Picker("Mode", selection: $mode) {
                ForEach(TimerMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                    .frame(width: 180, height: 180)

                if mode != .stopwatch {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(mode == .pomodoro ? Color.red : Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                }

                Text(displayTime)
                    .font(.system(size: 40, design: .monospaced))
                    .foregroundStyle(state == .finished ? .red : .primary)
            }

            if mode == .countdown {
                HStack(spacing: 12) {
                    Stepper("Minutes: \(Int(targetDuration / 60))", value: $targetDuration, in: 60...3600, step: 60)
                        .labelsHidden()
                    Text("\(Int(targetDuration / 60)) min")
                        .font(.system(size: fontSize))
                }
            } else if mode == .pomodoro {
                HStack(spacing: 12) {
                    Button("25 min") { targetDuration = 25 * 60 }
                    Button("15 min") { targetDuration = 15 * 60 }
                    Button("5 min") { targetDuration = 5 * 60 }
                }
                .buttonStyle(.bordered)
            }

            if isSoundPlaying {
                Button(action: stopSound) {
                    Label("Arrêter la sonnerie", systemImage: "speaker.slash.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 20) {
                Button(action: startOrResume) {
                    Image(systemName: state == .running ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
                .disabled(state == .running && mode == .stopwatch)

                Button(action: resetTimer) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .onAppear {
            mode = initialMode
            targetDuration = TimeInterval(initialSeconds)
        }
        .onChange(of: mode) {
            resetTimer()
        }
    }

    private func startOrResume() {
        switch state {
        case .stopped, .paused, .finished:
            state = .running
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                elapsed += 0.1
                if (mode == .countdown || mode == .pomodoro) && elapsed >= targetDuration {
                    stopTimer()
                    state = .finished
                    sendNotification()
                }
            }
        case .running:
            timer?.invalidate()
            timer = nil
            state = .paused
        }
    }

    private func resetTimer() {
        stopTimer()
        stopSound()
        elapsed = 0
        state = .stopped
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func stopSound() {
        audioPlayer?.stop()
        audioPlayer = nil
        isSoundPlaying = false
    }

    private func sendNotification() {
        stopSound()

        DispatchQueue.main.async { [self] in
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                NSSound.beep()
                return
            }

            if let url = Bundle.main.url(forResource: "timer_sound", withExtension: "mp3") {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: url)
                    audioPlayer?.numberOfLoops = -1
                    audioPlayer?.play()
                    isSoundPlaying = true
                } catch {
                    NSSound.beep()
                }
            } else {
                NSSound.beep()
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let tenths = Int((interval - Double(totalSeconds)) * 10)

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, seconds, tenths)
        } else {
            return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
        }
    }
}
