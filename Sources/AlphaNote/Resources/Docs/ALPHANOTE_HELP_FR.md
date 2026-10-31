# AlphaNote - Guide Utilisateur Complet

Version du guide : 23 octobre 2026  
Plateforme : macOS 14+

## 1. Vue d'ensemble

AlphaNote est un bloc-notes de capture immédiate, inspiré d'Antinote : une fenêtre
flottante, un raccourci global, et des mots en première ligne qui changent le
comportement de la note (`math`, `list`, `code`, `timer`).

Principes :
- **Éphémère** : écrire et jeter doivent coûter le même effort. Les notes vides
  disparaissent seules ; on épingle ce qui doit rester.
- **Zéro friction** : un raccourci pour ouvrir, Échap pour cacher. La fenêtre
  mémorise sa place et suit l'espace actif.
- **Les mots sont des commandes** : la première ligne pilote le mode.
- **Local-first** : base SQLite locale ; Nextcloud en option.

## 2. Première utilisation

1. Lancez AlphaNote.
2. Appuyez sur le raccourci global (⌥A par défaut, réglable dans Réglages › Général).
3. Écrivez. Tapez `math`, `list`, `code` ou `timer` en première ligne, ou choisissez
   le mode dans la pastille en haut à droite.
4. Échap cache la fenêtre.

## 3. Interface principale

La fenêtre ne contient que :
- Une barre fine : bouton du volet des notes, titre de la note, pastille de mode
  (menu), menu d'actions (épingler, renommer, dupliquer, copier, archiver,
  supprimer), bouton nouvelle note.
- L'éditeur, qui occupe tout le reste.

Volet des notes (`⌥⌘L`) : colonne de gauche qui **pousse** l'éditeur (il ne le
recouvre pas) et reste ouverte d'une session à l'autre. Recherche (texte +
sémantique locale), notes épinglées, notes, archives ; chaque ligne montre le
titre, la date et un aperçu. ↑ / ↓ dans la recherche changent de note, Entrée
ouvre le premier résultat, Échap referme le volet. Clic droit pour les actions.

Volets éphémères :
- **Demande en langage naturel** (`⌘K`) : une phrase, un mode choisi, une action
  locale (voir §5.6). Dictée possible via le micro.
- **Toast** en bas : retour des actions (archivée, copiée, mode appliqué…).

### 3.1 Création et suppression

- `⌥⌘N`, le bouton en haut à droite, ou swiper au-delà de la dernière note.
- Swiper depuis une note vide la supprime. Les notes vides sont supprimées quand la
  fenêtre se cache (réglable).
- Supprimer une note non vide demande confirmation ; la suppression est logique
  (`soft delete`) pour la synchronisation.

## 4. Navigation et raccourcis

- Raccourci global (défaut `⌥A`) : afficher / masquer.
- `Échap` : fermer la demande ⌘K, sinon cacher la fenêtre.
- `⌥⌘N` : nouvelle note · `⌥⌘←` / `⌥⌘→` : note précédente / suivante.
- `⌥⌘L` : afficher / masquer le volet des notes · `⇧⌘F` : rechercher dans les notes.
- `⌘K` : demande en langage naturel.
- `⌥⌘1` … `⌥⌘5` : mode Texte, Math, Liste, Code, Minuteur.
- `⇧⌘L` (réglable) : convertir la note en liste.
- `⌥⌘P` : épingler · `⌥⌘E` : archiver · `⌥⌘⌫` : supprimer.
- `⌘F` : rechercher dans la note · `⌘,` : réglages · `⇧⌘H` : aide.
- Swipe horizontal (trackpad) dans l'éditeur.

## 5. Modes de note

Un seul éditeur sert à tous les modes texte : changer de mode ne détruit jamais
l'éditeur, le focus ni le curseur. Le mode ne fait que décorer le texte.

### 5.1 Texte (par défaut)

Aucun mot-clé. Les adresses web sont cliquables.

### 5.2 `math`

Activez avec `math` ou `math: Mon titre`.

- Variables : `loyer: 900`. `nom: expr =` affiche aussi le résultat.
- Résultat inline sur toute ligne terminée par `=`.
- Opérateurs `+ - * / ^`, parenthèses, `x` ou `×` pour multiplier, virgule décimale.
- Fonctions : `sqrt`, `abs`, `round`, `floor`, `ceil`, `ln`, `log`, `log2`, `exp`,
  `sin`, `cos`, `tan`, `min`, `max` ; factorielle `5!` ; constante `pi`.
- Pourcentages : `50% of 200 =`, `prix - 15% =`, variables en pourcentage
  (`tva: 21%` puis `total + tva =` ajoute 21 % de `total`).
- Unités : `10 kg + 500 g =` (résultat dans la première unité), `12 km to mi =`,
  `72°F to °C =`. Unités incompatibles : `⚠︎ unités incompatibles`.
- Devises : `100 USD to EUR =`. Taux BCE (Frankfurter) avec repli, mis en cache
  une heure. Pendant le chargement, la ligne affiche `…`.
- `//` commence un commentaire. Les mots inconnus sont ignorés (`5 pommes + 3 =`).
- Si une ligne avec `=` ne peut plus être évaluée, la partie droite est vidée.

### 5.3 `list`

Activez avec `list` ou `list: Courses`.

- Chaque ligne non vide est un élément ; cliquez la case en marge pour cocher.
- Une ligne cochée se termine par le déclencheur (défaut `/x`, réglable).
- `# Titre`, `## Sous-titre` pour les sections ; `// texte` pour un commentaire.
- Entrée après une ligne commençant par `- ` continue la puce ; Entrée sur une puce
  vide la retire.
- `⇧⌘L` convertit n'importe quelle note (les virgules deviennent des lignes).

### 5.4 `code`

Activez avec `code` ou `code: swift`. Police monospace, interligne serré.

### 5.5 `timer`

Activez avec `timer` ou `timer: focus`, ou via `⌘K` (« minuteur 25 min »).

- Minuteur, Chrono, Pomodoro (25 min par défaut) ; préréglages 5 min à 1 h,
  réglage fin en minutes et en secondes (pas de 5 s).
- Le minuteur continue si vous changez de note ou cachez la fenêtre, et est
  restauré au redémarrage.
- Sonnerie au choix dans Réglages › Général › Minuteur : dix sonneries
  (Minuterie, Cloche, Téléphone, Réveil, Alerte, Montre, Sonar, Cristal, Bois,
  Pulsation) ou Verre (macOS) ; ▶︎ pour écouter.
- À la fin : sonnerie en boucle jusqu'à « Arrêter la sonnerie », icône du Dock
  qui rebondit.
- Espace démarre / met en pause.

### 5.6 Demande en langage naturel (⌘K)

Une phrase est **classée** dans un mode, puis une action locale est appliquée.
L'IA ne rédige qu'une chose : une formule, en mode math.

- `math` : l'expression est notée dans la note, calculée par la note. Une
  demande en mots (« aire d'un cercle de rayon 3 », « mensualité d'un prêt de
  200 000 € à 3 % sur 20 ans ») devient une formule rédigée par l'IA (une
  dizaine de secondes), marquée « formule proposée par l'IA, à vérifier ».
  Désactivable dans Réglages › IA.
- `list` : les éléments (virgules) deviennent une liste cochable. Un lien de
  recette devient la liste de ses ingrédients (lue dans la page, sans IA).
- `timer` : crée une note minuteur / chrono / pomodoro.
- `code` : passe la note en mode code.
- `plain` : rien n'est appliqué.

Pendant la saisie, une pastille `MODE ?` montre la prévision par mots-clés. Après
envoi, le toast indique `Mode X via JEV` ou `via mots-clés`, et la raison si le
serveur JEV n'a pas répondu.

La recherche du volet des notes combine filtre texte et similarité sémantique
locale (embeddings hash-64, aucun réseau).

## 6. Réglages

### 6.1 Général

- Raccourci global : activé, combinaison (cliquez le champ puis appuyez).
  Le raccourci est physique : l'étiquette suit la disposition du clavier.
- Toujours au premier plan.
- Afficher dans le Dock / dans la barre des menus (l'un des deux reste actif).
- Supprimer les notes vides à la fermeture.

### 6.2 Apparence

- Thème : Système / Clair / Sombre (appliqué à toutes les fenêtres).
- Couleurs : six thèmes coordonnés (Encre & or par défaut, Corail, Sauge, Lavande, Framboise, Bleu nuit). Chacun change l'accent (contours, cases, curseur) et la teinte des fonds, de jour comme de nuit. L'icône du Dock prend la couleur du thème pendant que l'app tourne ; celle du Finder reste corail. Sur Android, l'icône de lancement suit aussi.
- Taille du texte : 10 à 24.
- Déclencheur « coché » ; raccourci « Convertir en liste ».

### 6.3 Synchronisation

- Nextcloud : activation, serveur, utilisateur, mot de passe d'application,
  intervalle, test, sync manuelle.
- Imports : Nextcloud Notes (dossier .md/.txt) et Apple Notes.

### 6.4 IA

- Activation du routage de mode par serveur JEV (désactivé par défaut).
- URL du serveur, délai, test.
- Jeton d'accès (ID et secret) : pour un serveur publié derrière Cloudflare Access
  (ex. `https://jev.cobaltfilms.be`), joignable sans VPN. Le secret reste dans le
  trousseau. Vide pour un serveur du réseau local ou de Tailscale.
- Transparence : le schéma exact envoyé est affiché (un champ `mode`, enum).
- Sans serveur, AlphaNote reste sur les mots-clés et l'écran le dit.

### 6.5 Mises à jour

- Appcast, vérification, installation avec contrôle d'identité du paquet.

### 6.6 Avancé

- Dossier de la base : affichage, déplacement (copie + relance), Finder.
- Export JSON (toutes les notes actives) et Markdown (un fichier par note).

## 7. Synchronisation Nextcloud

### 7.1 Pré-requis

- URL Nextcloud (HTTPS recommandé), identifiant, mot de passe d'application.

### 7.2 Détails techniques

- Dossier distant `AlphaNote/notes/` + `manifest.json` ; un JSON par UUID.
- Sync toutes les N minutes, 30 s après une modification locale, et au lancement.
- Les notes distantes dont l'ETag n'a pas changé ne sont pas re-téléchargées.
- Conflit : `updatedAt` le plus récent gagne, puis `lastModifiedByDeviceId`.
- Suppressions propagées ; tombstones purgés après 30 jours.

## 8. Données, stockage, sécurité

- Base SQLite (GRDB) `alphanote.sqlite` dans le dossier configuré (par défaut
  `~/Library/Application Support/AlphaNote`).
- Écritures groupées : une sauvegarde au plus toutes les 400 ms par note, et
  immédiate quand on change de note ou cache la fenêtre.
- Mot de passe Nextcloud dans le trousseau macOS.
- Signature : une app signée ad-hoc change d'identité à chaque build, et macOS
  redemande l'accès au trousseau. Utilisez `CODESIGN_IDENTITY` avec
  `scripts/build-app.sh` pour une identité stable.

## 9. Dépannage

- **Raccourci muet** : vérifiez Réglages › Général ; une autre app peut l'utiliser.
- **Sync en erreur** : « Tester la connexion » ; vérifiez le WebDAV
  (`remote.php/dav/files/<utilisateur>/`).
- **Devise `…`** : taux en cours de chargement, ou pas de réseau.
- **Base introuvable** : Réglages › Avancé › Afficher dans le Finder. Si le dossier
  configuré est inaccessible, AlphaNote revient au dossier par défaut et l'indique.
- **Note disparue** : volet des notes › Archives ; notes vides supprimées à la
  fermeture (réglable).

## 10. Confidentialité

- Local-first. Réseau uniquement pour : Nextcloud (si activé), taux de change en
  mode math (Frankfurter / open.er-api), serveur JEV (si activé), appcast (si configuré).
- L'IA ne reçoit que la phrase de la demande, jamais le contenu des notes.
- La recherche sémantique est entièrement locale.

## 11. Support

- Menu `Aide` › `Aide AlphaNote`, ou `⇧⌘H`.
