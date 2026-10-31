import SwiftUI
import UserNotifications

/// Réglages propres à l'interface (mêmes clés que macOS quand elles existent).
enum AppSettings {
    static let themeKey = "theme"                    // system | light | dark
    static let autoCleanupKey = "autoCleanup"        // notes vides supprimées à l'ouverture de la liste
    static let confirmDeleteKey = "confirmDelete"    // confirmation avant de supprimer une note non vide
    static let fontSizeKey = "fontSize"
    static let listCheckTriggerKey = "listCheckTrigger"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            themeKey: "system",
            autoCleanupKey: true,
            confirmDeleteKey: true,
            fontSizeKey: 17.0,
            listCheckTriggerKey: "/x",
            ColorTheme.storageKey: ColorTheme.or.rawValue,
            AlarmSound.storageKey: AlarmSound.minuterie.rawValue
        ])
    }

    static func colorScheme(for raw: String) -> ColorScheme? {
        switch raw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

@main
struct AlphaNoteApp: App {
    @StateObject private var store = NoteStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.themeKey) private var theme = "system"
    @AppStorage(ColorTheme.storageKey) private var colorTheme = ColorTheme.or.rawValue
    @State private var showSettings = false

    init() {
        AppSettings.registerDefaults()
        DatabaseManager.shared.setup()
        TimerNotifier.shared.install()
        // Tests d'interface : coffre vierge (le trousseau du simulateur persiste).
        if ProcessInfo.processInfo.arguments.contains("-resetVault") {
            VaultKeyring.shared.forget()
        }
    }

    var body: some Scene {
        WindowGroup {
            NoteListView(showSettings: $showSettings)
                .environmentObject(store)
                .preferredColorScheme(AppSettings.colorScheme(for: theme))
                .tint(Palette.accentColor)
                .id(colorTheme) // nouvelles couleurs : on reconstruit les vues
                // Hors du sous-arbre reconstruit : changer de couleurs depuis
                // les Réglages ne les referme pas.
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .environmentObject(store)
                        .tint(Palette.accentColor)
                }
                .onAppear {
                    store.loadNotes()
                    SyncEngine.shared.start()
                    SharedInbox.importPending(into: store)
                }
                .onReceive(NotificationCenter.default.publisher(for: .alphaNoteDidSync)) { _ in
                    store.flushPendingSaves()
                    store.loadNotes()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                SharedInbox.importPending(into: store)
                SyncEngine.shared.runManualSync()
            case .background:
                // Rien ne doit rester en attente quand iOS suspend l'app, et
                // le coffre se referme.
                store.flushPendingSaves()
                VaultKeyring.shared.lock()
            default:
                break
            }
        }
    }
}
