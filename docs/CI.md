# CI d'AlphaNote (Gitea Actions)

La CI est calquée sur celle de cockpit : chaque **Pull Request** et chaque
**commit sur `main`** déclenchent `.gitea/workflows/ci.yml`, qui lance
`swift build` puis `swift test`.

## Pourquoi un runner macOS

AlphaNote est **macOS-only** (SwiftUI, AppKit, Security, Speech). Il ne compile
pas dans le conteneur Linux `ubuntu-latest` utilisé par cockpit. Le job vise donc
un runner **self-hosted sur macOS**, enregistré en **mode hôte** (label
`macos:host`) : les étapes s'exécutent directement sur le Mac, avec la chaîne
d'outils qui y est installée.

Le workflow cible `runs-on: macos`. Un runner enregistré avec `macos:host`
accepte ces jobs ; un job `ubuntu-latest` n'atterrira jamais sur ce Mac.

## Pré-requis sur le Mac

- Xcode **ou** les Command Line Tools (`xcode-select --install`) → `swift --version` répond.
- `git`.
- Le Mac doit rester allumé et connecté à `git.cobaltfilms.be` pour accepter des jobs.

## 1. Créer un jeton d'enregistrement

Sur Gitea : **AlphaNote → Réglages → Actions → Runners → Créer un nouveau runner**
(portée dépôt). Copier le **registration token** (valable un temps limité).

## 2. Installer le runner

Télécharger le binaire `act_runner` (série 3.x) depuis
<https://gitea.com/gitea/runner/releases> (artefact `macOS`/`darwin`), puis :

```bash
chmod +x act_runner
# optionnel : le mettre dans /usr/local/bin
```

## 3. Enregistrer le runner (label hôte macOS)

```bash
./act_runner register \
  --instance https://git.cobaltfilms.be \
  --token <REGISTRATION_TOKEN> \
  --labels macos:host \
  --name alphanote-mac
```

`macos:host` = les jobs `runs-on: macos` tournent directement sur cette machine.

## 4. Lancer le runner

```bash
./act_runner daemon
```

Pour le garder vivant au démarrage, l'enregistrer comme service launchd (ou le
lancer dans un terminal tmux permanent). On peut surcharger les labels sans
re-enregistrer : `./act_runner daemon --labels macos:host`.

## 5. Vérifier

**AlphaNote → Actions → Runners** : le runner `alphanote-mac` doit apparaître
**en ligne**. Pousser une branche et ouvrir une PR : le job *Build et tests
(macOS)* s'exécute dessus.

## 6. (Optionnel) Bloquer la fusion tant que la CI est rouge

**Réglages → Branches → `main` → Protection** : activer les *status checks* et
exiger le contexte de la CI avant merge. C'est ce qui fait de la CI une condition
de fusion, comme dans cockpit.

## Note sécurité

Le mode hôte exécute les jobs **sans isolation** sur le Mac. Réservé à un usage
mono-développeur sur une machine de confiance ; ne pas y faire tourner des jobs
non fiables.
