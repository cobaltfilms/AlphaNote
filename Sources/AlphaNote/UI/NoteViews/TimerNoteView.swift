import SwiftUI

/// Surface du mode `timer`. L'état vit dans `TimerSession` (registre par note) :
/// changer de note, cacher la fenêtre ou relancer l'app n'arrête rien.
struct TimerNoteView: View {
    @ObservedObject var session: TimerSession
    /// Mode, durée ou heure changés : la note garde le réglage (« countdown 4:30 »,
    /// « alarm 07:30 »).
    var onSettingsChange: (TimerSession.Mode, TimeInterval) -> Void = { _, _ in }
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
                            session.mode == .alarm ? Color(platform: Palette.timer) : Palette.accentColor,
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
                        .foregroundStyle(session.state == .finished ? Color(platform: Palette.timer) : Palette.textColor)
                    Text(stateLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondaryColor)
                }
            }

            if session.mode == .alarm {
                DatePicker("Heure de l'alarme", selection: alarmDateBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    #if os(macOS)
                    .datePickerStyle(.stepperField)
                    #endif
                    .font(.system(size: fontSize))
                    .help("L'alarme sonne à cette heure, demain si elle est déjà passée.")
            } else if session.mode != .stopwatch, session.state == .stopped || session.state == .finished {
                // Grille souple : les boutons passent à la ligne au lieu d'être rognés.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                    ForEach(presets, id: \.seconds) { preset in
                        Button(preset.label) { session.setTargetDuration(preset.seconds) }
                            .buttonStyle(.bordered)
                            .tint(session.targetDuration == preset.seconds ? Palette.accentColor : nil)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: 440)

                HStack(spacing: 18) {
                    Stepper(value: minutesBinding, in: 0...180, step: 1) {
                        Text("\(Int(session.targetDuration) / 60) min")
                            .font(.system(size: fontSize))
                            .monospacedDigit()
                    }
                    Stepper(value: secondsBinding, in: 0...59, step: 5) {
                        Text("\(Int(session.targetDuration) % 60) s")
                            .font(.system(size: fontSize))
                            .monospacedDigit()
                    }
                    .help("Secondes, par pas de 5 s.")
                }
            }

            if session.isSoundPlaying {
                Button {
                    session.stopSound()
                } label: {
                    Label("Arrêter la sonnerie", systemImage: "speaker.slash.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(platform: Palette.timer))
            }

            HStack(spacing: 16) {
                Button {
                    session.toggle()
                } label: {
                    Image(systemName: playSymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accentColor)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(playLabel)

                Button {
                    session.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 56)
                }
                .buttonStyle(.bordered)
                .disabled(session.state == .stopped)
                .accessibilityLabel("Remettre à zéro")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: session.mode) { _, mode in onSettingsChange(mode, session.settingSeconds) }
        .onChange(of: session.targetDuration) { _, _ in onSettingsChange(session.mode, session.settingSeconds) }
        .onChange(of: session.alarmTime) { _, _ in onSettingsChange(session.mode, session.settingSeconds) }
    }

    private var playSymbol: String {
        if session.mode == .alarm { return session.state == .running ? "bell.slash.fill" : "bell.fill" }
        return session.state == .running ? "pause.fill" : "play.fill"
    }

    private var playLabel: String {
        if session.mode == .alarm { return session.state == .running ? "Désarmer" : "Armer" }
        return session.state == .running ? "Pause" : "Démarrer"
    }

    /// L'heure de l'alarme vue comme une date du jour, pour le sélecteur.
    private var alarmDateBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: session.alarmTime / 3600, minute: (session.alarmTime % 3600) / 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                session.setAlarmTime((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60)
            }
        )
    }

    // Minutes et secondes réglées séparément ; jamais moins de 5 s au total.
    private var minutesBinding: Binding<Int> {
        Binding(
            get: { Int(session.targetDuration) / 60 },
            set: { session.setTargetDuration(TimeInterval(max(5, $0 * 60 + Int(session.targetDuration) % 60))) }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { Int(session.targetDuration) % 60 },
            set: { session.setTargetDuration(TimeInterval(max(5, Int(session.targetDuration) / 60 * 60 + $0))) }
        )
    }

    private var stateLabel: String {
        if session.mode == .alarm {
            switch session.state {
            case .running: return "Sonne dans \(TimerSession.format(session.remaining))"
            case .finished: return "Alarme"
            case .stopped, .paused: return "Désarmée"
            }
        }
        switch session.state {
        case .stopped: return session.mode == .stopwatch ? "Prêt" : "En attente"
        case .running: return "En cours"
        case .paused: return "En pause"
        case .finished: return "Terminé"
        }
    }
}
