# AlphaNote - Guide Utilisateur Complet

Version du guide: 21 mai 2026  
Plateforme: macOS 14+

## 1. Vue d'ensemble

AlphaNote est un carnet rapide orienté capture immédiate. L'application est pensée pour ouvrir une fenêtre de note en quelques millisecondes, écrire, calculer, convertir, organiser en checklist, puis fermer.

Principes de fonctionnement:
- Fenêtre flottante toujours accessible.
- Données locales (SQLite) en priorité.
- Syntaxe légère par mots-clés en première ligne (`math`, `list`, `code`, `timer`).
- Synchronisation cloud optionnelle via Nextcloud (WebDAV).

## 2. Première utilisation

1. Lancez AlphaNote.
2. Utilisez `⌥A` pour afficher/masquer la fenêtre de notes.
3. Créez une note avec le bouton `Nouvelle note` ou le raccourci `⌥⌘N`.
4. Tapez librement, ou démarrez la première ligne avec un mot-clé pour activer un mode.

## 3. Interface principale

La fenêtre contient:
- Une barre supérieure avec bouton de bascule de liste, compteur de position et bouton de création.
- Une colonne gauche (liste des notes) affichable/masquable.
- Une zone d'édition principale qui change selon le mode de la note.

### 3.1 Liste des notes

Dans la colonne gauche, chaque note affiche:
- Un titre (nom explicite si défini, sinon première ligne utile).
- Un aperçu une-ligne du contenu.
- Un menu d'actions:
  - Renommer
  - Dupliquer
  - Archiver / Désarchiver
  - Supprimer

Les notes archivées sont regroupées dans une section repliable `Archives`.

### 3.2 Création et suppression

- Une note vide peut être créée rapidement depuis les commandes.
- La suppression est une suppression logique (`soft delete`) pour permettre la cohérence de sync.

## 4. Navigation et raccourcis

Raccourcis disponibles:
- `⌥A` : afficher/masquer AlphaNote (global hotkey).
- `⌥⌘N` : nouvelle note.
- `⌥⌘L` : afficher/masquer la liste des notes.
- `⌘⇧L` : convertir la note active en mode liste (raccourci configurable).
- `⌘,` : ouvrir les réglages.
- `⌘⇧H` : ouvrir le centre d'aide AlphaNote.

Navigation:
- Swipe horizontal trackpad (gauche/droite) dans la zone d'édition.
- Sélection directe d'une note dans la liste.

## 5. Modes de note

Le mode est détecté par la première ligne.

### 5.1 Mode texte (par défaut)

Aucun mot-clé spécial. La note reste une zone texte standard.

### 5.2 Mode `math`

Activez avec:
- `math`
- `math: Mon titre`

Fonctionnalités:
- Évaluation en ligne des expressions avec `=`.
- Variables via `nom: expression`.
- Réutilisation des variables dans les lignes suivantes.
- Pourcentages et opérateurs usuels (`+`, `-`, `*`, `/`, `^`, parenthèses).
- Conversions d'unités/currency depuis les expressions (`to`, `in`, `en`).

Exemples:
- `budget: 1200`
- `taxe: 21%`
- `total =`
- `12 km to mi =`
- `72 kg in lb =`
- `100 USD to EUR =`

Comportements utiles:
- Si une ligne avec `=` ne peut plus être évaluée, la partie droite est vidée (`expression =`).
- Les unités incompatibles peuvent produire `⚠︎ mixed units`.

### 5.3 Mode `list`

Activez avec:
- `list`
- `list: Courses`

Fonctionnalités:
- Checklist cliquable.
- Marquage coché avec déclencheur configurable (par défaut `/x`).
- Titres de section avec `#`, `##`, `###`.
- Commentaires avec préfixe `//`.

Exemple:
- `list: Déploiement`
- `# Backend`
- `Migrer la base`
- `Vérifier les logs /x`
- `// relancer un backup après prod`

### 5.4 Mode `code`

Activez avec:
- `code`
- `code: swift`

Fonctionnalités:
- Éditeur monospace.
- Badge de langage détecté depuis le titre (swift, python, javascript/js, rust, ruby, go, c++, java, html, css, shell/bash/zsh).

### 5.5 Mode `timer`

Activez avec:
- `timer`
- `timer: focus`

Modes disponibles:
- Stopwatch
- Countdown
- Pomodoro

Fonctionnalités:
- Démarrer / pause / reprise.
- Reset.
- Notification locale à la fin d'un countdown/pomodoro.

## 6. Réglages

Les réglages sont structurés en 4 onglets.

### 6.1 General

Options visibles:
- Enable global hotkey (`⌥A`)
- Show in Dock
- Show in Menu Bar
- Auto-cleanup empty notes

### 6.2 Appearance

- Theme: System / Light / Dark
- Font size: 10 à 24

### 6.3 Keywords

- Keyword `math`
- Keyword `list`
- Keyword `code`
- Keyword `timer`
- Déclencheur check-list (ex: `/x`)
- Raccourci "Convertir en liste" (modifieurs + touche)

### 6.4 Advanced

- Emplacement de la base de données SQLite
- Synchronisation Nextcloud
- Test connection
- Sync now
- Export JSON
- Reveal in Finder

## 7. Synchronisation Nextcloud

AlphaNote peut synchroniser les notes via WebDAV.

### 7.1 Pré-requis

- URL Nextcloud valide (HTTP/HTTPS).
- Nom d'utilisateur Nextcloud.
- Mot de passe applicatif (recommandé).

### 7.2 Configuration

1. Ouvrez `Settings > Advanced`.
2. Activez `Enable cloud sync`.
3. Renseignez URL, username, app password.
4. Cliquez `Test connection`.
5. Ajustez l'intervalle (1 à 60 min).

### 7.3 Détails techniques

- Dossier distant: `AlphaNote/notes/` + `manifest.json`.
- Format des notes: un JSON par UUID.
- Conflits: résolution par `updatedAt`, puis `lastModifiedByDeviceId`, puis état supprimé.
- Suppressions: propagation distante + purge différée des tombstones (au-delà de 30 jours).

## 8. Données, stockage, sécurité

### 8.1 Stockage local

- Base SQLite (GRDB) dans le dossier configuré.
- Nom de fichier par défaut: `alph note.sqlite`.

### 8.2 Mot de passe cloud

- Stockage dans le Keychain macOS.
- Pas de mot de passe en clair dans la base.

### 8.3 Export

- Export JSON manuel depuis `Settings > Advanced > Export Data`.

## 9. Dépannage

### 9.1 Le hotkey global ne fonctionne pas

- Vérifiez qu'AlphaNote est en cours d'exécution.
- Vérifiez les conflits avec un autre raccourci global.

### 9.2 La sync échoue

- Vérifiez URL, username, app password.
- Relancez `Test connection`.
- Vérifiez que l'endpoint WebDAV est disponible côté Nextcloud.

### 9.3 Je ne trouve pas la base de données

- Allez dans `Settings > Advanced`.
- Utilisez `Reveal in Finder`.

### 9.4 Certaines notes semblent "disparaître"

- Vérifiez la section `Archives` dans la barre latérale.
- Vérifiez si la note a été supprimée logiquement, puis synchronisée.

## 10. État réel de certaines options

Le code actuel expose certaines options dans l'interface qui ne pilotent pas encore entièrement le comportement runtime.

Au 21 mai 2026:
- `fontSize`: appliqué.
- `listCheckTrigger`: appliqué.
- raccourci `Convertir en liste`: appliqué.
- `theme`: option présente, application visuelle partielle/non centralisée.
- `keywordMath/keywordList/keywordCode/keywordTimer`: options présentes, routing principal encore basé sur les mots-clés standards codés.
- `hotkeyEnabled`, `showInDock`, `showInMenuBar`, `autoCleanup`: options présentes, branchement runtime incomplet.

## 11. Confidentialité

- L'app est local-first.
- L'accès réseau est limité aux opérations de synchronisation Nextcloud et aux conversions de devises en mode math.

## 12. Raccourci support

Le centre d'aide est disponible via:
- Menu `Help` > `AlphaNote Help`
- `⌘⇧H`
