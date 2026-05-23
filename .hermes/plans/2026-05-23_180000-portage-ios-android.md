# Stratégie de Portage AlphaNote — iOS & Android

> **De :** Paul — 23 mai 2026
> **Contexte :** AlphaNote v2 macOS (Swift/SwiftUI + AppKit) avec IA locale MLX.
> **Objectif :** Définir une stratégie réaliste et chiffrée pour porter l'application sur iOS et Android.

---

## Résumé Exécutif

AlphaNote macOS ≈ **12 500 lignes de Swift** réparties en 3 couches distinctes. Le portage est un projet lourd mais faisable avec une approche par phases. La recommandation : **iOS d'abord** (18-25 jours de dev), puis **Android** (25-35 jours) ou une approche **Kotlin Multiplatform** (35-50 jours pour les deux).

| Cible | Approche | Effort estimé | Qualité | Code réutilisé |
|---|---|---|---|---|
| **iOS** | SwiftUI natif | 18-25 j/h | Excellente | ~55% |
| **Android** | Kotlin natif | 25-35 j/h | Excellente | ~15% (spec + design) |
| **iOS + Android** | Kotlin Multiplatform | 35-50 j/h | Très bonne | ~40% (logique partagée) |
| **iOS + Android** | Flutter | 30-45 j/h | Bonne | ~30% |

---

## 1. Analyse du Code Actuel — Qu'est-ce qui survit ?

### ✅ Portable tel quel (logique pure, pas de frameworks macOS)

| Fichier | Lignes | Notes |
|---|---|---|
| `Models/Note.swift` | 355 | Modèle avec GRDB — à adapter |
| `Models/ListModeFormatter.swift` | ~100 | Parsing markdown → checklist |
| `Evaluation/MathEvaluator.swift` | 242 | Recursive-descent parser, 0 dépendance |
| `Evaluation/Converter.swift` | 309 | Unités + devises (URLSession pour API) |
| `AI/AIPromptBuilder.swift` | 162 | Construction de prompts |
| `AI/AIResponseParser.swift` | ~200 | Parsing des réponses LLM |
| `AI/AIIntentDetector.swift` | 249 | Classification d'intention |
| `AI/Features/ModeRoutingFeature.swift` | ~50 | Routage keyword → mode |
| `AI/Features/RemoteContextFeature.swift` (partie URLDetector) | ~70 | Extraction d'URLs, normalisation |
| `Services/DeviceIdentity.swift` | ~50 | UUID device |
| `Sync/SyncModels.swift` | ~100 | Modèles de synchro |

**Total : ±1 800 lignes réutilisables quasi telles quelles.**

### ⚠️ Portable avec adaptation

| Composant | Problème | Solution |
|---|---|---|
| `DatabaseManager.swift` | GRDB.swift = Swift-only | iOS : `GRDB` (OK). Android : `Room` (Kotlin) ou `SQLDelight` (KMP) |
| `NoteStore.swift` (logique métier) | 1628 lignes, mix UI + logique | Splitter : extraire `NoteBusinessLogic` pur |
| `SyncEngine.swift` | Timer, UserDefaults, Keychain | iOS : OK avec adaptation. Android : WorkManager + EncryptedSharedPreferences |
| `KeychainService.swift` | macOS Keychain | iOS : Keychain Services. Android : EncryptedSharedPreferences |
| `NextcloudWebDAVClient.swift` | Foundation URLSession | Fonctionne sur iOS tel quel. Android : OkHttp |
| AI Features (SemanticSearch, Rewrite, Summarize) | MLX seulement | iOS : utiliser Core ML. Android : MediaPipe ou API cloud |
| `VectorIndex.swift` / `EmbeddingStore.swift` | MLX embeddings | iOS : Core ML embeddings. Android : TensorFlow Lite |

### ❌ À réécrire complètement

| Composant | Raison |
|---|---|
| `AlphaNoteApp.swift` (AppDelegate, NSApplication, CommandMenu) | macOS AppKit lifecycle |
| `NoteWindowController.swift` | NSWindowController, floating overlay |
| `HotkeyManager.swift` | NSEvent global monitors |
| `NoteListView.swift` (VisualEffectView, AppKit imports) | AppKit-specific UI |
| `AIModelDiagnostics.swift` (NSWorkspace, sysctl, Cotypist detection) | macOS system APIs |
| `AIManagedRuntime.swift` (MLX, brew paths, Python management) | Apple Silicon MLX only |
| `MLXSwiftInferenceEngine` | MLX bindings |
| `NoteImportService.swift` (AppleEvents, AppleScript) | macOS automation |
| `NoteViews/*` (AppKit bridging) | NSHostingView wrappers |

**Total à réécrire : ±6 000 lignes.**

---

## 2. Stratégie iOS

### 2.1 Architecture cible

```
AlphaNote-iOS/
├── Shared/                          # Code partagé macOS ↔ iOS (≈55%)
│   ├── Models/Note.swift            # Adapté (GRDB → GRDB iOS OK)
│   ├── Evaluation/                  # Copié tel quel ✅
│   ├── AI/Prompts+Parser+Intent     # Copié tel quel ✅
│   ├── AI/Features (hors MLX)      # Adapté (Core ML au lieu de MLX)
│   ├── Services/NextcloudWebDAV     # Adapté (Keychain iOS)
│   └── Sync/                        # Adapté (Keychain iOS)
├── iOS/                             # UI iOS native
│   ├── AlphaNoteApp.swift           # @main SwiftUI (pas de AppDelegate)
│   ├── ContentView.swift            # TabView ou NavigationSplitView
│   ├── NoteListView.swift           # List + swipe actions iOS natives
│   ├── NoteEditorView.swift         # TextEditor plein écran
│   ├── NoteModeViews/               # Adaptés des NoteViews macOS
│   ├── SettingsView.swift           # Form iOS natif
│   ├── AI/InferenceEngine.swift     # Core ML + fallback heuristique
│   └── Widget/                      # Widget iOS (remplace le floating overlay)
└── Tests/
```

### 2.2 Ce qui change dans l'UX

Le paradigme « fenêtre flottante one-keystroke » n'existe pas sur iOS. Alternatives :

| Fonction macOS | Équivalent iOS |
|---|---|
| ⌥A global hotkey | ❌ Pas possible. Alternatives : |
|  | → **Widget** écran d'accueil/verrouillage (1-tap → nouvelle note) |
|  | → **Control Center** toggle (iOS 18+) |
|  | → **Back Tap** (Accessibilité → toucher arrière) |
|  | → **Share Sheet** (« Note rapide » depuis n'importe quelle app) |
| Fenêtre flottante | **Slide-over** sur iPad. **Plein écran** sur iPhone |
| Swipe trackpad | Swipe doigt natif (TabView page-style) |
| Status bar item | Widget + badge |

### 2.3 Plan détaillé — 4 sprints de 4-5 jours

#### Sprint 1 : Fondations (4 jours)

**Tâche 1.1 — Créer le projet Xcode iOS**
- Cible : iOS 17+ (ou 18 selon date de sortie)
- SwiftUI App lifecycle, pas de AppDelegate
- Fichiers : `AlphaNoteApp.swift`, `ContentView.swift`

**Tâche 1.2 — Porter le modèle Note**
- Copier `Note.swift` — supprimer les colonnes sync pour l'instant
- GRDB fonctionne sur iOS → garder la même DB
- `DatabaseManager` adapté : utiliser `FileManager.default.urls(for: .documentDirectory)`
- Test : CRUD basique dans un preview SwiftUI

**Tâche 1.3 — Porter MathEvaluator + Converter**
- Copie brute → ces fichiers n'ont aucune dépendance système
- Test : mêmes tests unitaires que macOS, copiés dans la target iOS

**Tâche 1.4 — Porter l'UI Plain Note**
- `PlainNoteView` → `NoteEditorView` iOS
- TextEditor + barre d'outils (keyboard toolbar pour les actions AI)
- Test : écrire une note, elle persiste

#### Sprint 2 : Modes & Keywords (5 jours)

**Tâche 2.1 — Keyword Detection + View Router**
- Copier `AIIntentDetector` → classifier la première ligne
- Router iOS : `switch keyword { case "math": MathNoteView ... }`
- Test : taper "math" en première ligne → le mode change

**Tâche 2.2 — MathNoteView iOS**
- Adapter `MathNoteView.swift` — logique d'évaluation identique
- UI adaptée : évaluation inline en gris sous chaque ligne
- Test : "2+2=" → affiche "4"

**Tâche 2.3 — ListNoteView iOS**
- Adapter `ListNoteView.swift` — même parsing markdown (`/x`, `#`)
- UI : SwiftUI List avec checkboxes natives
- Test : créer une checklist, cocher/décocher

**Tâche 2.4 — CodeNoteView + TimerNoteView iOS**
- Code : monospace font, coloration syntaxique basique
- Timer : `Timer.publish` SwiftUI, stopwatch/countdown/pomodoro
- Test : chaque mode fonctionne

**Tâche 2.5 — Navigation entre notes**
- TabView(pageStyle) pour swipe horizontal
- Liste latérale (sidebar sur iPad, sheet sur iPhone)
- Test : créer 3 notes, swiper entre elles

#### Sprint 3 : IA locale iOS (4 jours)

**Tâche 3.1 — Portage du pipeline AI**
- `AIPromptBuilder` → copié tel quel ✅
- `AIResponseParser` → copié tel quel ✅
- `AIIntentDetector` → déjà porté au Sprint 2

**Tâche 3.2 — Inference Engine iOS (Core ML)**
- Remplacer `MLXSwiftInferenceEngine` par un `CoreMLInferenceEngine`
- Modèles Core ML téléchargeables (HuggingFace → coremltools)
- Au minimum : fallback heuristique (déjà portable)
- Modèles recommandés pour iOS :
  - `apple/OpenELM-270M` → rapide, < 200 MB
  - `google/gemma-2b-it` (Core ML) → bonne qualité, ~1.5 GB
  - `Qwen2.5-1.5B-Instruct` (Core ML) → bon compromis

**Tâche 3.3 — Semantic Search iOS**
- `VectorIndex` : remplacer MLX par Core ML embeddings (`NLEmbedding` ou modèle sentence-transformers converti)
- Stockage : SQLite avec vecteurs dans GRDB (déjà prévu)
- Test : indexer 10 notes, chercher sémantiquement

**Tâche 3.4 — AI Assistant Bar iOS**
- Barre d'outils au-dessus du clavier
- Boutons : Résumer, Réécrire, Questions/Réponses, Recherche Web
- Test : sélectionner du texte → résumer

#### Sprint 4 : Polish & Settings (5 jours)

**Tâche 4.1 — Settings iOS natif**
- `SettingsView` adapté → Form sections iOS
- @AppStorage pour toutes les préférences
- Onglets : Général, Apparence, Mots-clés, IA, Avancé

**Tâche 4.2 — Widget iOS**
- WidgetKit : « Note Rapide », « Nouvelle Note », afficher dernière note
- Medium + Large sizes
- Intent donation pour Siri Shortcuts

**Tâche 4.3 — Unit/Currency Conversion**
- Convertir déjà porté. Tester l'API devises via URLSession (fonctionne sur iOS)
- Cache UserDefaults → OK

**Tâche 4.4 — Import (Nextcloud)**
- `NextcloudWebDAVClient` → fonctionne sur iOS (URLSession)
- `NoteImportService` (Nextcloud uniquement, pas Apple Notes)
- UI : Settings > Import

**Tâche 4.5 — Tests complets + App Store preparation**
- UI tests sur iPhone + iPad
- Capture d'écrans (6.7" + 12.9")
- App Store Connect setup

### 2.4 Estimation iOS

| Phase | Jours/homme |
|---|---|
| Sprint 1 — Fondations | 4 |
| Sprint 2 — Modes & Keywords | 5 |
| Sprint 3 — IA locale | 4 |
| Sprint 4 — Polish & Settings | 5 |
| **Total** | **18 jours** |

---

## 3. Stratégie Android

### 3.1 Architecture cible

```
AlphaNote-Android/
├── app/src/main/java/be/cobaltfilms/alphanote/
│   ├── model/
│   │   └── Note.kt                     # Data class Room entity
│   ├── data/
│   │   ├── AppDatabase.kt              # Room database
│   │   ├── NoteDao.kt                  # Data Access Object
│   │   └── NoteRepository.kt           # Repository pattern
│   ├── domain/
│   │   ├── MathEvaluator.kt            # Port de Swift → Kotlin
│   │   ├── Converter.kt                # Port de Swift → Kotlin
│   │   ├── KeywordDetector.kt          # Port de l'intent detector
│   │   ├── ListModeFormatter.kt        # Parsing checklist
│   │   └── AIPromptBuilder.kt          # Port des prompts
│   ├── ui/
│   │   ├── MainActivity.kt             # Single Activity
│   │   ├── NoteListScreen.kt           # Jetpack Compose
│   │   ├── NoteEditScreen.kt
│   │   ├── modes/
│   │   │   ├── MathNoteScreen.kt
│   │   │   ├── ListNoteScreen.kt
│   │   │   ├── CodeNoteScreen.kt
│   │   │   └── TimerNoteScreen.kt
│   │   └── settings/SettingsScreen.kt
│   ├── ai/
│   │   ├── LocalInferenceEngine.kt     # MediaPipe ou TFLite
│   │   ├── HeuristicFallback.kt
│   │   └── AIService.kt
│   └── service/
│       ├── SyncWorker.kt               # WorkManager sync
│       └── NextcloudClient.kt          # OkHttp WebDAV
└── Tests/
```

### 3.2 Ce qu'on peut réutiliser du code Swift

Pas de copier-coller possible, mais :
- Les **algorithmes** sont documentés et testés — le portage est une traduction, pas une réinvention
- `MathEvaluator.swift` → `MathEvaluator.kt` : 242 lignes de parsing → traduisible en 1-2 jours
- `Converter.swift` → `Converter.kt` : même logique, adaptations pour les APIs Android
- `AIPromptBuilder.swift` → `AIPromptBuilder.kt` : simple traduction de strings

### 3.3 Stack technique recommandée

| Couche | Technologie | Équivalent macOS |
|---|---|---|
| UI | Jetpack Compose | SwiftUI |
| DB | Room (SQLite) | GRDB.swift |
| Async | Kotlin Coroutines + Flow | async/await + @Published |
| HTTP | OkHttp + Retrofit (optionnel) | URLSession |
| IA locale | MediaPipe LLM Inference | MLX |
| Sync | WorkManager | Timer + async task |
| DI | Hilt (Dagger) | Singleton pattern |
| Navigation | Compose Navigation | NavigationStack |

### 3.4 Plan détaillé Android — 5 sprints

#### Sprint 1 : Projet & Fondations (5 jours)

**Tâche 1.1 — Setup Android Studio project**
- Gradle KTS, min SDK 26 (Android 8), target 34+
- Jetpack Compose + Material 3
- Dépendances : Room, Hilt, Coroutines, OkHttp

**Tâche 1.2 — Room Database + Note Entity**
- `Note.kt` data class avec annotations Room
- `AppDatabase.kt`, `NoteDao.kt`, `NoteRepository.kt`
- Migration v1 identique au schéma macOS

**Tâche 1.3 — MathEvaluator.kt (port de Swift)**
- Traduire le recursive-descent parser
- Token types, precedence climbing
- Tests unitaires exhaustifs (copier les cas de test Swift)

**Tâche 1.4 — Converter.kt (port de Swift)**
- Unités : distance, masse, température
- Devises : API exchangerate.host via OkHttp, cache SharedPreferences
- Tests unitaires

#### Sprint 2 : UI Core (6 jours)

**Tâche 2.1 — MainActivity + Navigation**
- Single Activity architecture
- Bottom navigation ou Navigation rail
- Scaffold avec TopAppBar

**Tâche 2.2 — NoteListScreen**
- LazyColumn avec swipe-to-dismiss
- FloatingActionButton → nouvelle note
- État : empty state, liste, chargement

**Tâche 2.3 — NoteEditScreen (Plain mode)**
- BasicTextField ou TextField multiligne
- Barre d'outils : undo, redo, AI actions
- Focus management

**Tâche 2.4 — Keyword detection + mode routing**
- `KeywordDetector.kt` → classifier la première ligne
- Router Compose : `when(keyword) { "math" -> MathNoteScreen ... }`

**Tâche 2.5 — Math + List Note Screens**
- Math : évaluation inline, affichage résultats
- List : Checkbox + texte, parsing markdown

**Tâche 2.6 — Code + Timer Note Screens**
- Code : monospace, coloration (basique)
- Timer : CountDownTimer Android, stopwatch, pomodoro

#### Sprint 3 : IA locale (5 jours)

**Tâche 3.1 — AIPromptBuilder.kt + AIResponseParser.kt**
- Traduction simple des prompts et parsing de réponses

**Tâche 3.2 — LocalInferenceEngine (MediaPipe)**
- MediaPipe LLM Inference API
- Modèles recommandés :
  - `Gemma 2B` (version MediaPipe) → bon compromis taille/qualité
  - `Gemma 3 1B` → encore plus léger
  - Fallback : heuristique pure (aucun téléchargement requis)

**Tâche 3.3 — AI Service**
- Ordonnancement : MediaPipe → fallback heuristique
- Gestion des timeouts, erreurs
- Feature : summarize, rewrite, semantic search

**Tâche 3.4 — VectorIndex + Semantic Search**
- TensorFlow Lite pour embeddings (Universal Sentence Encoder ou modèle converti)
- SQLite FTS5 pour stockage vecteurs
- Recherche sémantique locale

**Tâche 3.5 — AI UI**
- Barre d'assistant intégrée au NoteEditScreen
- Résultats affichés en overlay ou bottom sheet

#### Sprint 4 : Features avancées (5 jours)

**Tâche 4.1 — Settings Screen**
- Jetpack Compose Preference equivalent
- DataStore pour préférences (alternative à SharedPreferences)

**Tâche 4.2 — Nextcloud Sync**
- `NextcloudClient.kt` via OkHttp
- `SyncWorker.kt` via WorkManager (periodic)
- UI dans Settings

**Tâche 4.3 — Import de notes**
- Nextcloud import (fichiers texte)
- Pas d'Apple Notes (Android)
- Import depuis fichiers locaux (Storage Access Framework)

**Tâche 4.4 — Widget Android**
- App Widget (écran d'accueil)
- « Nouvelle note rapide » — 1 tap → ouvre l'app en mode édition

**Tâche 4.5 — Notifications + Quick Settings Tile**
- Notification persistante « AlphaNote » → ouverture rapide
- Quick Settings tile (Android 7+) → toggle rapide

#### Sprint 5 : Polish & Release (4 jours)

**Tâche 5.1 — Tests UI + unitaires**
- Tests Compose (Compose Testing)
- Tests Room (in-memory DB)
- Tests ViewModel

**Tâche 5.2 — Performance & optimisation**
- Profiling mémoire (IA locale)
- Cold start time
- APK size optimization

**Tâche 5.3 — Play Store preparation**
- Captures d'écran (phone + tablet)
- Play Store listing
- Privacy policy

### 3.5 Estimation Android

| Phase | Jours/homme |
|---|---|
| Sprint 1 — Fondations | 5 |
| Sprint 2 — UI Core | 6 |
| Sprint 3 — IA locale | 5 |
| Sprint 4 — Features avancées | 5 |
| Sprint 5 — Polish & Release | 4 |
| **Total** | **25 jours** |

---

## 4. Approche Cross-Platform : Kotlin Multiplatform (KMP)

Si l'objectif est de sortir sur iOS **et** Android avec une base de code partagée.

### 4.1 Ce que KMP permet de partager

```
shared/                                # Code Kotlin partagé iOS + Android
├── commonMain/
│   ├── model/Note.kt                  # SQLDelight
│   ├── domain/MathEvaluator.kt        # Kotlin pur — partagé à 100%
│   ├── domain/Converter.kt            # Kotlin pur + Ktor pour API
│   ├── domain/KeywordDetector.kt      # Kotlin pur
│   ├── domain/AIPromptBuilder.kt      # Kotlin pur
│   ├── data/Database.kt               # SQLDelight (compile iOS + Android)
│   ├── data/NoteRepository.kt
│   └── data/NextcloudClient.kt        # Ktor WebDAV
├── androidMain/                       # Room, WorkManager, MediaPipe
└── iosMain/                           # GRDB, Keychain, Core ML
```

### 4.2 Stack KMP

| Couche | Technologie | Partagé ? |
|---|---|---|
| Modèles + Logique | Kotlin commonMain | ✅ 100% |
| Database | SQLDelight | ✅ 100% |
| HTTP | Ktor | ✅ 100% |
| Math/Conversion | Kotlin commonMain | ✅ 100% |
| AI Prompts/Parsing | Kotlin commonMain | ✅ 100% |
| IA inference | expect/actual (Core ML / MediaPipe) | ⚠️ Plateforme |
| UI iOS | SwiftUI | ❌ |
| UI Android | Jetpack Compose | ❌ |
| Settings | expect/actual (DataStore / UserDefaults) | ⚠️ Plateforme |

### 4.3 Estimation KMP

| Phase | Jours/homme |
|---|---|
| Setup KMP project + shared module | 3 |
| Porter toute la logique en Kotlin | 8 |
| UI iOS (SwiftUI natif) | 12 |
| UI Android (Compose natif) | 12 |
| IA inference expect/actual | 5 |
| Tests + Polish | 5 |
| **Total** | **45 jours** |

Avantage : maintenance future simplifiée (une seule base pour la logique métier).
Inconvénient : setup plus complexe, tooling moins mature, besoin d'un dev KMP expérimenté.

---

## 5. Recommandations

### Court terme (maintenant)

1. **Splitter `NoteStore.swift`** en plusieurs fichiers avant tout portage :
   - `NoteStore.swift` → CRUD + navigation uniquement
   - `AIStore.swift` → logique IA
   - `ImportStore.swift` → logique d'import
   - `SearchStore.swift` → recherche sémantique

2. **Extraire les protocoles** pour l'inference engine :
   ```swift
   protocol InferenceEngine {
       func generate(prompt: String, system: String, modelID: String, options: RequestOptions) -> AsyncThrowingStream<String, Error>
   }
   ```
   → Facilitera l'implémentation Core ML sur iOS

3. **Ajouter `#if os(iOS)` / `#if os(macOS)`** aux fichiers de logique pure déjà portables, pour identifier les divergences

### Recommandation principale

> **Faire iOS en premier** (18 jours). C'est le chemin le plus court, tu réutilises 55% de ton code, tu capitalises sur Swift/SwiftUI que tu maîtrises. Une fois iOS sorti, évaluer si le marché justifie Android (25 jours) ou si une approche KMP (45 jours, mais les deux plateformes) est plus rentable.

### Ce qu'il ne faut PAS faire

- ❌ Réécrire de zéro sans regarder le code existant — les algorithmes sont bons et testés
- ❌ Choisir React Native ou Flutter pour cette app spécifique — trop de logique pure qui bénéficie du natif (math parser, MLX/Core ML)
- ❌ Vouloir l'App Store ET le Play Store en même temps sans équipe — prioriser une plateforme

### Coûts estimés (ordre de grandeur)

| Scénario | Jours/homme | Coût indicatif* |
|---|---|---|
| iOS seul | 18 j | 9 000 – 14 400 € |
| Android seul | 25 j | 12 500 – 20 000 € |
| iOS + Android (séquentiel) | 43 j | 21 500 – 34 400 € |
| KMP (iOS + Android simultané) | 45 j | 22 500 – 36 000 € |

*\* Basé sur 500-800 €/jour, freelance Swift/Kotlin senior — marché 2026 estimé.*

---

## 6. Questions Ouvertes

1. **Priorité utilisateurs** : tes utilisateurs sont-ils plutôt iOS ou Android ? (ça détermine par où commencer)
2. **Widget vs overlay** : le widget iOS « Note Rapide » est-il un remplacement acceptable pour le hotkey ⌥A ?
3. **IA cloud fallback** : pour Android (pas de MLX, pas de Core ML), accepterais-tu une option cloud (OpenAI/Claude API) en fallback du MediaPipe local ?
4. **Monétisation** : l'app reste-t-elle gratuite ou payante sur iOS/Android ?
5. **Équipe** : tu développes seul ou tu as un·e dev mobile sous la main ?

---

*Plan généré le 23 mai 2026 — à réviser après chaque phase.*
