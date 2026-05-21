import SwiftUI

struct AIAssistantBar: View {
    var isProcessing: Bool
    var onCancel: () -> Void
    var onSummarize: () -> Void
    var onRewrite: (RewriteStyle) -> Void
    var onExtractActions: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Résumé") { onSummarize() }

                Menu("Réécriture") {
                    ForEach(RewriteStyle.allCases, id: \.rawValue) { style in
                        Button(style.label) { onRewrite(style) }
                    }
                }

                Button("Extraire actions") { onExtractActions() }
            } label: {
                Label("Assistant IA", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)

            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                Button("Annuler", action: onCancel)
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
}
