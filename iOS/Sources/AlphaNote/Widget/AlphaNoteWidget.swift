import SwiftUI
import WidgetKit

struct AlphaNoteEntry: TimelineEntry {
    let date: Date
    let lastNoteTitle: String
    let noteCount: Int
}

struct AlphaNoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlphaNoteEntry {
        AlphaNoteEntry(date: Date(), lastNoteTitle: "Nouvelle note", noteCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (AlphaNoteEntry) -> Void) {
        completion(AlphaNoteEntry(date: Date(), lastNoteTitle: "Nouvelle note", noteCount: 3))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlphaNoteEntry>) -> Void) {
        let entry = AlphaNoteEntry(date: Date(), lastNoteTitle: "Nouvelle note", noteCount: 0)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct AlphaNoteWidgetEntryView: View {
    var entry: AlphaNoteProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "note.text")
                    .font(.title2)
                Spacer()
                Text("\(entry.noteCount)")
                    .font(.caption)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Text(entry.lastNoteTitle)
                .font(.headline)
                .lineLimit(2)
            Text("Appuyer pour une nouvelle note")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct AlphaNoteWidget: Widget {
    let kind = "AlphaNoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AlphaNoteProvider()) { entry in
            AlphaNoteWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AlphaNote")
        .description("Accès rapide à tes notes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
