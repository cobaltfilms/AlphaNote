import SwiftUI

/// Création d'un rappel sur une note : une date et une heure, et une ou plusieurs alertes.
struct ReminderSheet: View {
    let onAdd: (Date, Set<ReminderKind>) -> Void
    let onCancel: () -> Void

    @State private var date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var kinds: Set<ReminderKind> = [.notification, .sonnerie]

    private var isValid: Bool { date > Date() && !kinds.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rappel").font(.headline)

            DatePicker("Date et heure", selection: $date, displayedComponents: [.date, .hourAndMinute])

            VStack(alignment: .leading, spacing: 6) {
                Text("Alertes").font(.subheadline).foregroundStyle(.secondary)
                ForEach(ReminderKind.allCases, id: \.self) { kind in
                    Toggle(label(kind), isOn: Binding(
                        get: { kinds.contains(kind) },
                        set: { isOn in
                            if isOn { kinds.insert(kind) } else { kinds.remove(kind) }
                        }
                    ))
                }
            }

            if date <= Date() {
                Text("Cette date est déjà passée.").font(.callout).foregroundStyle(.red)
            } else if kinds.isEmpty {
                Text("Choisissez au moins une alerte.").font(.callout).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Annuler", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Ajouter") { onAdd(date, kinds) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func label(_ kind: ReminderKind) -> String {
        switch kind {
        case .notification: return "Notification"
        case .sonnerie: return "Sonnerie"
        case .vibration: return "Vibration"
        }
    }
}
