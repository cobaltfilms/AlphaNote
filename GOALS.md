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
| `timer` | Timer | Stopwatch, countdown, alarm (time of day) |

### Unit & Currency Conversion
- Parse expressions like `10 km to mi`, `72 kg to lbs`, `100°F to °C`
- Currency via Frankfurter / open.er-api (no key), fetched asynchronously, 1-hour cache; the note shows `…` until rates arrive
- Parse `10 USD to JPY` style input

### OCR
- Apple Vision framework for on-device text recognition
- Triggered by pasting image data into a note
- Completely offline

### Search & Replace
- Quick search across all notes
- Find and replace within a note

## AI (JEV contract)

AI in AlphaNote **classifies, it never drafts** — with one exception (below).
It follows the JEV contract (jevai.net, same as the cockpit project): a small
model sorts a request into a strict schema (enum / bounded fields) and the app
applies the chosen mode with deterministic local code.

**Exception: math formulas (decided by Paul, 2026-10-24).** In math mode, a
request in words ("aire d'un cercle de rayon 3", "mensualité d'un prêt…") may
be turned into a formula **written by the model** (`FormulaDraftFeature`,
`POST /v1/chat/completions` on the same server, Qwen3 with thinking — slower,
~10 s, but the no-thinking answers were wrong on simple cases). Guardrails:
- the formula is kept only if every word is a known function, `pi` or a
  variable it defines, and the note actually computes the last line;
- it is written under a `// … formule proposée par l'IA (modèle), à vérifier`
  comment, and the status line says so;
- only the request is sent, never note content; Settings → AI shows the exact
  prompt and has a toggle to turn drafting off.

**Recipe link → list (no AI).** A recipe URL in list mode is fetched and its
schema.org `recipeIngredient` list (JSON-LD or microdata) becomes the list
(`RecipeIngredientExtractor`). A page without structured data is a frank
failure. This replaced the recipe part of the removed remote-context module.

**Kept features**
- **Semantic search** — local hash-64 embeddings (`AI/Storage/`), fully offline,
  never routed through the network.
- **Mode routing** — a question is classified into a `NoteMode`
  (`math | list | timer | code | plain`).

**How routing works**
1. If enabled and a JEV server is configured, `JEVClient.decider` posts to
   `POST /v1/decision` with a one-field enum schema (`mode`) whose per-mode
   descriptions do the heavy lifting.
2. A valid answer routes via **JEV**.
3. Any failure — server unreachable, incomplete answer, rejected schema, no
   mode chosen — falls back **frankly** to the deterministic
   `KeywordIntentRouter`, and the failure reason is carried on the decision.

**Transparency (non-negotiable)**
- Every decision carries its `source` (`JEV` or `mots-clés`); the UI badge shows
  `MODE · source` and the status line names the JEV failure when it fell back.
- Settings → AI shows the exact schema sent to the server and a "Tester le
  serveur" probe. Nothing is silent.
- Confidence scores are never used on their own to decide; an incomplete answer
  is a failure, not a half-success.

**Removed** (no longer part of the product): summarize, rewrite, extract-actions,
Q/R (askNotes), remote/web context (Brave), transform, AI timer intent, and the
entire embedded local runtime (MLX / GGUF / llama.cpp, registry, diagnostics).

## Architecture

- **Platform**: macOS 14+ (Sonoma)
- **UI Framework**: SwiftUI + AppKit hybrid (NSWindowController + SwiftUI views via NSHostingView)
- **Database**: SQLite via GRDB.swift 7.0+
- **Math Parser**: Custom recursive-descent parser (safe for untrusted input, NOT NSExpression)
- **Collections**: swift-collections (OrderedCollections) for deterministic note ordering
- **Currency API**: Frankfurter (ECB) with open.er-api.com fallback, async, 1-hour cache (`CurrencyRateService`); never blocks the editor
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
├── AlphaNoteApp.swift          # @main entry, menus, AppDelegate (hotkey, status item, theme, window levels)
├── Database/
│   └── DatabaseManager.swift   # GRDB singleton, migrations, safe fallback + relocation
├── Models/
│   ├── Note.swift              # Note model, CRUD
│   ├── ListModeFormatter.swift
│   └── TimerSession.swift      # Timer state per note (registry, persisted)
├── ViewModels/
│   ├── NoteStore.swift         # notes, debounced saves, modes, toast
│   └── AIStore.swift           # JEV routing → deterministic local action
├── UI/
│   ├── NoteWindowController.swift  # Floating window, frame autosave, Esc
│   ├── NoteListView.swift          # Main view: top bar, editor, overlay sidebar, ⌘K, toast
│   ├── Editor/NoteEditorView.swift # ONE NSTextView for plain/math/list/code (decoration only)
│   ├── NoteViews/TimerNoteView.swift
│   ├── SettingsView.swift          # General, Apparence, Sync, IA, Mises à jour, Avancé
│   ├── Settings/HotkeyRecorderView.swift
│   └── Theme/AlphaNoteTheme.swift  # « Encre & or » palette
├── Evaluation/
│   ├── MathEvaluator.swift         # Safe recursive-descent parser (functions, %, !, pi)
│   ├── MathDocumentEvaluator.swift # Variables, units, inline results (pure, tested)
│   ├── Converter.swift             # Unit + currency conversion
│   └── CurrencyRateService.swift   # Async cached exchange rates
├── AI/                             # JEVClient, KeywordIntentRouter, ModeRoutingFeature, hash-64 embeddings
├── Sync/                           # SyncEngine (ETag-aware), SyncModels
└── Services/                       # HotkeyManager, Keychain, WebDAV, import, speech, updates
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
- [x] Timer note view (stopwatch/countdown/alarm)
- [x] Unit conversion
- [x] Currency conversion with API cache
- [x] Global hotkey (⌥A)
- [x] Status bar icon
- [x] Swipe navigation between notes
- [x] Settings (4 tabs)

### Phase 2 — Polish (2026-10-23 : single-editor rewrite)
- [x] Smooth animations and transitions (overlay sidebar, ⌘K field, toast)
- [x] Keyboard shortcuts within notes (modes ⌥⌘1-5, pin, archive, delete, prev/next)
- [x] Search across notes (text + local semantic, ⇧⌘F)
- [x] Find within note (⌘F find bar)
- [ ] Smart paste with OCR (Apple Vision)
- [x] Note pinning UI
- [x] Theme support (light/dark/auto, applied app-wide)
- [x] Custom font size
- [x] Auto-cleanup of empty notes (on hide, configurable)
- [x] Configurable global hotkey (recorder, layout-aware)
- [x] Floating panel with remembered frame, Esc to hide
- [x] Timer state survives note switches and relaunch

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
- [x] Math functions (sqrt, abs, round, floor, ceil, ln, log, log2, exp, sin, cos, tan, min, max, pi)
- [x] Factorial
- [x] Unit conversion (distance, mass, temp)
- [x] Currency conversion (API + cache)
- [x] Checklist mode
- [x] Code editor mode
- [x] Timer modes (stopwatch, countdown, alarm)
- [x] Settings (general, appearance, sync, AI, updates, advanced)
- [ ] OCR paste (Phase 2)
- [x] Search (Phase 2)
- [ ] Replace (Phase 2)
- [x] Theme support (Phase 2)
- [x] Export JSON / Markdown (Phase 3)