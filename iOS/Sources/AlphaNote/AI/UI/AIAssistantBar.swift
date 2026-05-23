import SwiftUI

struct AIAssistantBar: View {
    let isProcessing: Bool
    let onCancel: () -> Void
    let onSummarize: () -> Void
    let onRewrite: (RewriteStyle) -> Void
    let onExtractActions: () -> Void

    @AppStorage("aiEnabled") private var aiEnabled = false

    var body: some View {
        if !aiEnabled { return AnyView(EmptyView()) }

        return AnyView(
            HStack(spacing: 12) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Button("Annuler") { onCancel() }
                        .font(.caption)
                } else {
                    Button(action: onSummarize) {
                        Label("Résumer", systemImage: "text.justify.left")
                            .font(.caption)
                    }

                    Menu {
                        ForEach(RewriteStyle.allCases, id: \.self) { style in
                            Button(style.label) { onRewrite(style) }
                        }
                    } label: {
                        Label("Réécrire", systemImage: "pencil")
                            .font(.caption)
                    }

                    Button(action: onExtractActions) {
                        Label("Actions", systemImage: "checklist")
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        )
    }
}
