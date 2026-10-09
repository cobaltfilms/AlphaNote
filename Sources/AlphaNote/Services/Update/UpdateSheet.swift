import SwiftUI
import AppKit

struct UpdateSheet: View {
    @ObservedObject var updater: UpdateManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                Text(title).font(.headline)
            }

            content

            HStack {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var iconName: String {
        switch updater.phase {
        case .available: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .upToDate: return "checkmark.circle.fill"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private var title: String {
        switch updater.phase {
        case .checking: return "Recherche de mises à jour…"
        case .upToDate: return "Vous êtes à jour"
        case .available(let info): return "AlphaNote \(info.version) est disponible"
        case .downloading: return "Téléchargement…"
        case .installing: return "Installation…"
        case .failed: return "Problème de mise à jour"
        case .idle: return "Mises à jour"
        }
    }

    @ViewBuilder private var content: some View {
        switch updater.phase {
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Text("AlphaNote \(updater.currentVersion) est la dernière version.")
                .font(.callout).foregroundStyle(.secondary)
        case .available(let info):
            VStack(alignment: .leading, spacing: 8) {
                let buildSuffix = info.build.map { " (\($0))" } ?? ""
                Text("Vous avez \(updater.currentVersion). Mise à jour vers \(info.version)\(buildSuffix).")
                    .font(.callout).foregroundStyle(.secondary)
                if let notes = info.notes, !notes.isEmpty {
                    ScrollView {
                        Text(LocalizedStringKey(notes))
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        case .downloading(let p):
            ProgressView(value: p) { Text("Téléchargement…").font(.caption) }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installation et relance…").font(.callout)
            }
        case .failed(let message):
            Text(message).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var buttons: some View {
        switch updater.phase {
        case .available(let info):
            Button("Plus tard") { dismiss() }
            Button("Télécharger et installer") { updater.downloadAndInstall(info) }
                .keyboardShortcut(.defaultAction)
        case .downloading, .installing:
            Button("Annuler") { dismiss() }.disabled(true)
        case .failed:
            Button("Fermer") { dismiss() }
            Button("Réessayer") { updater.check(userInitiated: true) }
        default:
            Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }
}
