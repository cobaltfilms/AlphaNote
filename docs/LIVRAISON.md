# Livraison d'AlphaNote

Trois briques, un même cœur : `swift build` + `swift test` sont écrits une fois
dans `scripts/test.sh`, réutilisés par la validation, la CI et la livraison.

| Besoin | Commande |
|--------|----------|
| Build + tests rapides en local | `scripts/test.sh` |
| Validation pré-fusion (build+tests, build release, `.app`+zip, garde-fou secrets) | `scripts/validate.sh` |
| CI (PR + push `main`) | `.gitea/workflows/ci.yml` → appelle `scripts/test.sh` |
| Emballer un `.app` signé | `scripts/build-app.sh <version> [--zip]` |
| Livrer une version (tag + release Gitea + appcast) | `scripts/release.sh <version> "notes"` |

## Chaîne de livraison

```bash
# 1. Tout est vert en local
scripts/validate.sh 1.0.0

# 2. Livrer : tag v1.0.0, release Gitea avec le zip, appcast.json
GITEA_TOKEN=<jeton> scripts/release.sh 1.0.0 "Corrections du minuteur."

# 3. Publier l'appcast
git add appcast.json && git commit -m "release: 1.0.0" && git push
```

`release.sh` :
- lance `validate.sh` (ne livre que si tout passe) ;
- crée et pousse le tag `v1.0.0` ;
- si `GITEA_TOKEN` est posé : crée la release Gitea `v1.0.0`, attache
  `dist/AlphaNote-1.0.0.zip`, et écrit `appcast.json` avec l'URL de la pièce
  jointe ; sinon il laisse un `appcast.json` à compléter à la main ;
- écrit `appcast.json` à la racine (version, notes, url, minimumSystemVersion).

## Côté app (pour que les mises à jour arrivent)

Réglages > Updates → **Appcast URL** :

```
https://git.cobaltfilms.be/paul/AlphaNote/raw/branch/main/appcast.json
```

L'app compare la version de son bundle (`CFBundleShortVersionString`, posée par
`scripts/build-app.sh`) à celle de l'appcast, propose la mise à jour, télécharge
le zip, vérifie l'identité du bundle, se remplace et se relance.

## Jeton Gitea

Un jeton avec portée `repo` (write) suffit pour créer une release et y attacher
le zip. Ne pas le mettre dans le dépôt : le passer en variable d'environnement
(`GITEA_TOKEN=… scripts/release.sh …`).
