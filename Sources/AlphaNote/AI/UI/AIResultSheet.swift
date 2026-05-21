import SwiftUI

struct AIResultSheet: View {
    let title: String
    let resultText: String
    let onReplace: () -> Void
    let onInsert: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ScrollView {
                Text(resultText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 220)

            HStack {
                Spacer()
                Button("Annuler", action: onCancel)
                Button("Insérer", action: onInsert)
                Button("Remplacer", action: onReplace)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520)
    }
}
