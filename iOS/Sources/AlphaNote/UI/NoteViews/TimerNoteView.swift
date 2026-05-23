import SwiftUI

struct TimerNoteView: View {
    @Binding var note: Note
    @ObservedObject var store: NoteStore

    @State private var elapsed: TimeInterval = 0
    @State private var isRunning = false
    @State private var timer: Timer?
    @State private var countdownInput: String = ""
    @State private var remaining: TimeInterval = 0
    @State private var mode: TimerMode = .stopwatch

    enum TimerMode: String, CaseIterable {
        case stopwatch = "Chronomètre"
        case countdown = "Compte à rebours"
        case pomodoro = "Pomodoro"
    }

    var body: some View {
        VStack(spacing: 16) {
            // Timer display
            Text(formatTime(mode == .stopwatch ? elapsed : remaining))
                .font(.system(size: 48, design: .monospaced))
                .foregroundStyle(.primary)

            // Mode picker
            Picker("Mode", selection: $mode) {
                ForEach(TimerMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Countdown input
            if mode == .countdown {
                HStack {
                    TextField("Minutes", text: $countdownInput)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Text("min")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            // Controls
            HStack(spacing: 24) {
                Button(action: toggleTimer) {
                    Image(systemName: isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }

                if isRunning {
                    Button(action: stopTimer) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.red)
                    }
                }

                if !isRunning && (elapsed > 0 || remaining > 0) {
                    Button(action: resetTimer) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 44))
                    }
                }
            }
        }
        .padding()
        .onDisappear { timer?.invalidate() }
    }

    private func toggleTimer() {
        if isRunning {
            timer?.invalidate()
            isRunning = false
        } else {
            startTimer()
        }
    }

    private func startTimer() {
        isRunning = true
        if mode == .countdown {
            let mins = Double(countdownInput) ?? 0
            remaining = mins * 60
        } else if mode == .pomodoro {
            remaining = 25 * 60
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if mode == .stopwatch {
                elapsed += 0.1
            } else {
                if remaining > 0 {
                    remaining -= 0.1
                } else {
                    timer?.invalidate()
                    isRunning = false
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        isRunning = false
    }

    private func resetTimer() {
        timer?.invalidate()
        isRunning = false
        elapsed = 0
        remaining = 0
        countdownInput = ""
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
