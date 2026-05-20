# AlphaNote — Goals & Feature Spec

## Product Philosophy

1. **Ephemeral**: Notes are transient by default. Creating and deleting should be equally effortless. Swipe past an empty note → it's gone. No confirmation dialogs.
2. **Zero-friction**: One hotkey to rule them all. ⌥A opens the window. ⌥A closes it. No docking, no resizing, no setup.
3. **Words as commands**: The first line of every note is a keyword that activates a mode. `math` turns the note into a calculator. `list` turns it into a checklist. `code` turns it into a code editor. `timer` gives you a stopwatch/countdown.
4. **Beautiful minimalism**: The window floats above everything. Transparent titlebar. No toolbar clutter. Just you and your words.
5. **Local-first**: No cloud. No accounts. No analytics. SQLite on disk via GRDB. Your data is yours.

## Core Features

### Note Management
- Create new notes by swiping past the last note
- Delete empty notes by swiping away from them
- Swipe (two-finger trackpad gesture) or keyboard arrows to navigate between notes
- Pin important notes so they stay in place
- Auto-assign position for ordering
- First line keyword detection routes to the correct NoteView

### Global Hotkey
- ⌥A (Option+A) toggles the note window from any app
- Configurable in Settings
- Uses NSEvent global and local monitors

### Smart Paste
- Paste images → trigger OCR via Apple Vision framework
- Extracted text replaces or appends to note content
- Offline, on-device processing

### Keyword Modes

| Keyword | Mode | Description |
|---------|------|-------------|
| (none)  | Plain | Default TextEditor |
| `math`  | Math  | Inline evaluation on lines ending with `=` |
| `list`  | List  | Checklist with `/x` checked items, `#` headings |
| `code`  | Code  | Monospace editor with language hint from title |
| `timer` | Timer | Stopwatch, countdown, pomodoro |

### Unit & Currency Conversion
- Parse expressions like `10 km to mi`, `72 kg to lbs`, `100°F to °C`
- Currency via `exchangerate.host` API with 1-hour cache in UserDefaults
- Parse `10 USD to JPY` style input

### OCR
- Apple Vision framework for on-device text recognition
- Triggered by pasting image data into a note
- Completely offline

### Search & Replace
- Quick search across all notes
- Find and replace within a note

## Architecture

- **Platform**: macOS 14+ (Sonoma)
- **UI Framework**: SwiftUI + AppKit hybrid (NSWindowController + SwiftUI views via NSHostingView)
- **Database**: SQLite via GRDB.swift 7.0+
- **Math Parser**: Custom recursive-descent parser (safe for untrusted input, NOT NSExpression)
- **Collections**: swift-collections (OrderedCollections) for deterministic note ordering
- **Currency API**: `exchangerate.host` with 1-hour UserDefaults cache
- **OCR**: Apple Vision VNRecognizeTextRequest (offline)

### Database Schema (v1)

**note** table:
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PRIMARY KEY | Auto-increment |
| content | TEXT | Note body |
| keyword | TEXT | Detected keyword from first line |
| title | TEXT | First line of content |
| position | INTEGER | Ordering index |
| isPinned | BOOLEAN | Pin state |
| createdAt | DATETIME | Creation timestamp |
| updatedAt | DATETIME | Last modification timestamp |

**app_state** table:
| Column | Type | Description |
|--------|------|-------------|
| key | TEXT PRIMARY KEY | State key |
| value | TEXT | State value |

### Project Structure
```
Sources/AlphaNote/
├── AlphaNoteApp.swift          # @main entry, AppDelegate, status item
├── Database/
│   └── DatabaseManager.swift   # GRDB singleton, migrations
├── Models/
│   └── Note.swift              # Note model, CRUD
├── ViewModels/
│   └── NoteStore.swift         # @Published notes, business logic
├── UI/
│   ├── NoteWindowController.swift  # Floating window management
│   ├── NoteListView.swift          # Main list, swipe nav
│   ├── SettingsView.swift          # 4-tab settings
│   └── NoteViews/
│       ├── PlainNoteView.swift     # Default text editor
│       ├── MathNoteView.swift      # Inline math evaluation
│       ├── ListNoteView.swift      # Checklist mode
│       ├── CodeNoteView.swift      # Code editor mode
│       └── TimerNoteView.swift     # Timer (stopwatch/countdown/pomodoro)
├── Evaluation/
│   ├── MathEvaluator.swift         # Safe recursive-descent parser
│   └── Converter.swift             # Unit + currency conversion
└── Services/
    └── HotkeyManager.swift         # Global hotkey registration
```

## Phase Plan

### Phase 1 — MVP
- [x] Project scaffold with SPM
- [x] GRDB database setup with migrations
- [x] Note model with CRUD
- [x] NoteStore ViewModel
- [x] Floating window with hotkey toggle
- [x] Plain note view
- [x] Math note view with safe evaluator
- [x] List note view with checkboxes
- [x] Code note view with monospace font
- [x] Timer note view (stopwatch/countdown/pomodoro)
- [x] Unit conversion
- [x] Currency conversion with API cache
- [x] Global hotkey (⌥A)
- [x] Status bar icon
- [x] Swipe navigation between notes
- [x] Settings (4 tabs)

### Phase 2 — Polish
- [ ] Smooth animations and transitions
- [ ] Keyboard shortcuts within notes
- [ ] Search across notes
- [ ] Find & replace within note
- [ ] Smart paste with OCR (Apple Vision)
- [ ] Note pinning UI
- [ ] Theme support (light/dark/auto)
- [ ] Custom font size
- [ ] Auto-cleanup of empty notes

### Phase 3 — Advanced
- [ ] Note tagging / categories
- [ ] Export to Markdown / PDF
- [ ] Import from text files
- [ ] Shared extensions
- [ ] Custom keyword definitions
- [ ] Plugin system for new note modes
- [ ] iCloud sync (optional, off by default)
- [ ] Spotlight indexing

## Feature Coverage Checklist

- [x] Note CRUD
- [x] Note ordering (position field)
- [x] Keyword detection
- [x] Keyword-based view routing
- [x] SQLite persistence
- [x] Database migration
- [x] Global hotkey
- [x] Floating window
- [x] Status bar item
- [x] Swipe navigation
- [x] Auto-delete empty notes
- [x] Math evaluation (safe parser)
- [x] Percent calculations
- [x] Math functions (sqrt, log, etc.)
- [x] Factorial
- [x] Unit conversion (distance, mass, temp)
- [x] Currency conversion (API + cache)
- [x] Checklist mode
- [x] Code editor mode
- [x] Timer modes (stopwatch, countdown, pomodoro)
- [x] Settings (general, appearance, keywords, advanced)
- [ ] OCR paste (Phase 2)
- [ ] Search (Phase 2)
- [ ] Replace (Phase 2)
- [ ] Theme support (Phase 2)
- [ ] Export (Phase 3)