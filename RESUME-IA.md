# RESUME-IA — Reprise en main AlphaNote (nettoyage IA à la JEV)

> Fichier de transfert de session. À lire en entier avant toute reprise.
> Session du 2026-10-09. Plan validé par Paul, exécution en cours.

## Contexte & décisions validées

- **Objectif** : reprendre AlphaNote (scratchpad macOS/iOS/Android), nettoyer les
  fonctionnalités IA que Paul ne veut plus, rendre ce qui reste **transparent**
  (affichage du modèle/serveur utilisé, de la source de chaque décision, aucune
  IA silencieuse).
- **Inspiration JEV** (jevai.net, appris dans `/Users/paul/workspace/cockpit`,
  voir `cockpit/src/lib/jev.ts` et `cockpit/LECTURE-DEMANDE.md`) :
  - un petit modèle local **classe** selon un schéma strict (enum/booléen/
    champs bornés), il ne **rédige jamais** ;
  - la confiance du modèle ne sert jamais seule à décider ;
  - la qualité des descriptions du schéma fait presque tout le résultat ;
  - réponse incomplète = échec franc, pas un demi-succès ;
  - serveur injoignable n'empêche jamais l'app de tourner : fallback mots-clés,
    et **l'écran le dit**.
- **Features IA GARDÉES** : recherche sémantique + routage de mode par IA.
- **Features IA SUPPRIMÉES** : summarize, rewrite, extract actions, Q/R
  (askNotes), recherche web/contexte remote (Brave), transform, intent timer
  par IA, tout le runtime local (MLX/GGUF/llama.cpp, registry, diagnostics).
- **Backend** : serveur **JEV du LAN** `http://192.168.3.169:8096` (endpoint
  `POST /v1/decision`), plus de runtime local embarqué.
- **Périmètre** : **macOS d'abord**. iOS/Android figés (Android a des modifs
  locales non commitées — NE PAS TOUCHER, ne pas stasher).

## Déjà fait (non commité — tout est dans l'index/working tree)

### Supprimés (git rm)
- `Sources/AlphaNote/AI/` : AIService, AIModels, AIPromptBuilder,
  AIResponseParser, AIInferenceEngine (MLX), LlamaCppInferenceEngine,
  GGUFDownloadManager, AIModelRegistry, AIModelDiagnostics, AIManagedRuntime,
  AIMetricsLogger, AIIntentDetector, Features/RemoteContextFeature (contenait
  une clé Brave API en dur — supprimée), Features/Summarize|Rewrite|ActionItems,
  UI/AIAssistantBar, UI/AIResultSheet, UI/AISettingsView (à réécrire).
- `Tests/AlphaNoteTests/AIServiceTests.swift`.
- `iOS/Sources/AlphaNoteiOS/` (arborescence orpheline, aucun target SPM ne la
  référençait).
- ~4 600 lignes macOS + l'arbre iOS mort.

### Créés
- `Sources/AlphaNote/Services/URLDetector.swift` — extrait de
  RemoteContextFeature (conservé, testé par AlphaNoteTests).
- `Sources/AlphaNote/AI/AISettingsKeys.swift` — nouveaux clés : `aiEnabled`,
  `jevURL` (défaut suggéré `http://192.168.3.169:8096`), `jevDelaiMs` (20 000).
- `Sources/AlphaNote/AI/JEVClient.swift` — port Swift fidèle de jev.ts :
  `JEVField` (string/enum, boolean, integer/number bornés), `JEVSchema`,
  `JEVValue`, `JEVOutcome`, `JEVConfig` (lu depuis UserDefaults à chaque appel),
  `verifierSchema`, `decider` (transport injectable `JEVTransport` pour tests),
  `lireReponse` (champ invalide/absent ignoré), réponse incomplète = `.erreur`.
- `Sources/AlphaNote/AI/KeywordIntentRouter.swift` — fallback déterministe
  slim : `classify` → `NoteMode`, `isMathRequest`, `isListRequest`,
  `isTimerRequest`, `parseTimerRequest`. Plus de webResearch/transform/question.
- `Sources/AlphaNote/AI/Features/ModeRoutingFeature.swift` — contrat JEV :
  `NoteMode` (math|list|timer|code|plain), `RouteSource` (jev|motsCles),
  `ModeDecision {mode, source, echec?}`, schéma enum avec descriptions
  soignées, JEV d'abord puis fallback mots-clés avec `echec` propagé.
  Contient aussi `AIFeatureGate` (UserDefaults `aiEnabled`).
- `Sources/AlphaNote/AI/Features/SemanticSearchFeature.swift` — réduit à
  `index(note)` + `search(query,notes,topK)` (embeddings hash-64 locaux,
  inchangés : `AI/Storage/EmbeddingStore.swift`, `AI/Storage/VectorIndex.swift`).

### Réécrits / modifiés
- `Sources/AlphaNote/ViewModels/AIStore.swift` (1 443 → ~300 l.) :
  `routeQuestion(_:)` → décision JEV/mots-clés puis application **locale
  déterministe** (math : expression notée via MathEvaluator/Converter, block
  `math:` préfixé sans écraser le contenu ; list : items virgules ou
  ListModeFormatter ; timer : `createNote(keyword:"timer")` ; code : préfixe
  `code` ; plain : rien). Message de statut = « Mode X via JEV|mots-clés » +
  raison d'échec JEV le cas échéant. `semanticSearch` conservée.
- `Sources/AlphaNote/ViewModels/NoteStore.swift` : publie désormais
  `lastRoute: ModeDecision?` + `aiStatusMessage: String?` (suppression de
  `aiError`, `lastAIResult`) ; délégation réduite à `routeQuestion` +
  `semanticSearch`.
- `Sources/AlphaNote/UI/NoteListView.swift` : barre de question = détection de
  mode (aperçu live via KeywordIntentRouter avec badge « MODE ? », puis badge
  final « MODE · source » après envoi via `lastRoutedQuestion`) ; panneau
  Q/R supprimé, remplacé par une ligne de statut (icône sparkles si JEV,
  loupe si mots-clés) ; micro conservé ; recherche sémantique sidebar
  conservée.
- `Sources/AlphaNote/UI/NoteViews/PlainNoteView.swift` : éditeur nu
  (AIAssistantBar + AIResultSheet retirés).
- `Sources/AlphaNote/UI/SettingsView.swift` : onglet « Web Search » et
  `WebSearchSettingsView` supprimés (clé Brave).

## RESTE À FAIRE (ordre conseillé)

1. **Recréer `Sources/AlphaNote/AI/UI/AISettingsView.swift`** (il est supprimé
   mais SettingsView.swift:22 l'appelle encore → **le build casse ici**) :
   - Toggle « Activer le routage de mode IA » (`AISettingsKeys.enabled`)
   - TextField URL serveur JEV (`AISettingsKeys.jevURL`) + Stepper délai
   - Bouton « Tester le serveur » : un `JEVClient.decider` probe (1 fragment,
     schéma de routage) → vert « joignable » / rouge + message
   - **Transparence** : afficher le schéma (`ModeRoutingFeature.schema`,
     descriptions des modes) dans l'onglet.
2. **Tests** :
   - `Tests/AlphaNoteTests/AlphaNoteTests.swift` : remplacer la section
     « AI intents » (références `AIIntentDetector` → `KeywordIntentRouter`,
     retirer les tests webResearch/transform et le test `AIResponseParser`
     ligne ~282 ; garder les tests URLDetector).
   - Créer `Tests/AlphaNoteTests/JEVClientTests.swift` avec un faux
     `JEVTransport` : config absente → erreur ; schéma sans description →
     erreur ; enum < 2 choix → erreur ; réponse incomplète → `.erreur` ;
     `lireReponse` ignore valeurs hors enum/type ; happy path → décision.
   - Idéalement un test `ModeRoutingFeature` : JEV non configuré →
     `source == .motsCles`.
3. **`Sources/AlphaNote/Services/PreferencesMigration.swift`** : remplacer les
   clés IA obsolètes (selectedModelID, customModelID, qualityMode, maxTokens,
   allowFallbackHeuristics, conservativePolicyEnabled, companionAwarenessEnabled)
   par `AISettingsKeys.enabled`, `jevURL`, `jevDelaiMs`.
4. **Build & tests** : `swift build && swift test` à la racine.
   Vérifier aussi les warnings (KeychainService.readGenericSecret/
   saveGenericSecret peut-être plus appelés — à garder si Sync s'en sert,
   à nettoyer sinon).
5. **GOALS.md** : ajouter une section « IA (contrat JEV) » : features gardées,
   schéma de routage, fallback, transparence ; retirer toute idée de génération.
6. **Docs in-app** : `Sources/AlphaNote/Resources/Docs/ALPHANOTE_HELP_FR.md`
   — vérifier les mentions IA (résumé/réécriture/web) et mettre à jour.
7. Vérifier `TimerNoteView`/`NoteStore.parseTimerContent` : la création de
   minuteur passe maintenant uniquement par `AIStore.applyTimer` (mots-clés
   ou JEV) — contenu `timer\ncountdown mm:ss` inchangé, OK a priori.

## Points d'attention

- **Ne pas committer les modifs Android** (working tree plein de changements
  Android non commités : NoteViewModel.kt, SettingsScreen.kt, TimerNoteScreen.kt,
  etc.) ni les toucher. Commit futur = macOS uniquement, demander à Paul avant
  tout commit.
- Modifs non commitées préexistantes à respecter aussi :
  `Sources/AlphaNote/Database/DatabaseManager.swift`,
  `Sources/AlphaNote/Services/KeychainService.swift` (non commités, utiles).
- Colonnes DB `aiSummary`/`aiLastProcessedAt` : **conservées** dans le schéma
  et le modèle `Note` (compat sync iOS/Android) mais plus écrites par l'app.
- `iOS/Sources/AlphaNote/AI/` contient encore l'ancienne pile IA iOS :
  **figée** (macOS d'abord), à ressouder plus tard avec JEVClient.
- Le serveur JEV du LAN tourne déjà (utilisé par cockpit, `JEV_URL`
  `http://192.168.3.169:8096`, endpoint `/v1/decision`, body
  `{instructions, schema, contexts, temperature}`).
- Le schéma JEV refuse un enum sans description (HTTP 400) — d'où
  `verifierSchema` côté client.
- Recherche sémantique = embeddings hash-64 locaux (aucun modèle, aucun
  réseau) : fonctionne hors-ligne, ne pas la brancher sur JEV.

## Commandes

```bash
swift build          # racine du repo (macOS 14+, SPM)
swift test
# serveur JEV : http://192.168.3.169:8096 (POST /v1/decision)
```

## Références

- Contrat JEV de référence : `/Users/paul/workspace/cockpit/src/lib/jev.ts`
  + commentaires d'en-tête (leçons d'étalonnage).
- `cockpit/LECTURE-DEMANDE.md` §4.1 « Le schéma jev reste court ».
- GOALS.md = spec produit (philosophie : ephemeral, zero-friction, words as
  commands, local-first — l'IA ne doit rien y contredire).
