import SwiftUI

/// Surface du mode `timer`. L'état vit dans `TimerSession` (registre par note) :
/// changer de note, cacher la fenêtre ou relancer l'app n'arrête rien.
struct TimerNoteView: View {
    @ObservedObject var session: TimerSession
    @AppStorage("fontSize") private var fontSize: Double = 14

    private let presets: [(label: String, seconds: TimeInterval)] = [
        ("5 min", 5 * 60), ("10 min", 10 * 60), ("15 min", 15 * 60),
        ("25 min", 25 * 60), ("45 min", 45 * 60), ("1 h", 3600)
    ]

    var body: some View {
        VStack(spacing: 28) {
            Picker("Mode", selection: Binding(
                get: { session.mode },
                set: { session.setMode($0) }
            )) {
                ForEach(TimerSession.Mode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            ZStack {
                Circle()
                    .stroke(Palette.lineColor, lineWidth: 8)
                    .frame(width: 220, height: 220)

                if session.mode != .stopwatch {
                    Circle()
                        .trim(from: 0, to: session.progress)
                        .stroke(
                            session.mode == .pomodoro ? Color(nsColor: Palette.timer) : Palette.accentColor,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 220, height: 220)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: session.progress)
                }

                VStack(spacing: 4) {
                    Text(session.displayTime)
                        .font(.system(size: 46, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(session.state == .finished ? Color(nsColor: Palette.timer) : Palette.textColor)
                    Text(stateLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondaryColor)
                }
            }

            if session.mode != .stopwatch, session.state == .stopped || session.state == .finished {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.seconds) { preset in
                        Button(preset.label) { session.setTargetDuration(preset.seconds) }
                            .buttonStyle(.bordered)
                            .tint(session.targetDuration == preset.seconds ? Palette.accentColor : nil)
                    }
                }

                Stepper(
                    value: Binding(
                        get: { session.targetDuration / 60 },
                        set: { session.setTargetDuration($0 * 60) }
                    ),
                    in: 1...180,
                    step: 1
                ) {
                    Text("\(Int(session.targetDuration / 60)) min")
                        .font(.system(size: fontSize))
                        .monospacedDigit()
                }
                .frame(width: 140)
            }

            if session.isSoundPlaying {
                Button {
                    session.stopSound()
                } label: {
                    Label("Arrêter la sonnerie", systemImage: "speaker.slash.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: Palette.timer))
            }

            HStack(spacing: 16) {
                Button {
                    session.toggle()
                } label: {
                    Image(systemName: session.state == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accentColor)
                .keyboardShortcut(.space, modifiers: [])

                Button {
                    session.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 56)
                }
                .buttonStyle(.bordered)
                .disabled(session.state == .stopped)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stateLabel: String {
        switch session.state {
        case .stopped: return session.mode == .stopwatch ? "Prêt" : "En attente"
        case .running: return "En cours"
        case .paused: return "En pause"
        case .finished: return "Terminé"
        }
    }
}
