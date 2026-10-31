# Synchro directe sur le réseau local (0.3.0)

Le Mac et le téléphone Android se synchronisent directement quand ils sont sur le
même Wi-Fi. Nextcloud reste le repli quand ils ne le sont pas. Rien ne sort du
réseau local, conformément à `GOALS.md` (local-first).

## Découverte

- Le Mac s'annonce en Bonjour avec le type `_alphanote._tcp`, sous le nom de la
  machine (ex. « Mac de Paul »). Il ne s'annonce que si la synchro réseau est
  activée (Réglages › Synchronisation › Réseau local).
- Le téléphone cherche ce service avec `NsdManager` au moment de synchroniser.
  Le port est choisi par le Mac et lu dans l'annonce.

## Appairage (une seule fois)

1. Sur le Mac : « Appairer un téléphone » affiche un code à 6 chiffres.
2. Sur le téléphone : Réglages › Mac sur le Wi-Fi, saisir le code, « Appairer ».
3. Le téléphone envoie `POST /v1/pair` avec `{code, deviceId, deviceName}`.
   Le Mac répond `{token, serverName}`.

Règles côté Mac :
- le code expire après 5 minutes et ne sert qu'une fois ;
- après 5 essais faux, il est invalidé et il faut en générer un autre ;
- le jeton est un aléatoire de 256 bits ; le Mac ne garde que son empreinte
  SHA-256, dans `UserDefaults` (clé `lanPairedDevices`) ;
- « Retirer » dans les réglages révoque le jeton du téléphone.

Côté téléphone, le jeton est stocké chiffré (Android Keystore, emplacement `lan`
de `SecurePasswordStore`).

## Requêtes

Toutes les requêtes HTTP/1.1 ; corps et réponses en JSON. Les autres routes
répondent 404.

| Méthode et chemin | Authentification | Rôle |
|---|---|---|
| `GET /v1/info` | non | `{name, schemaVersion}` |
| `POST /v1/pair` | non (le code fait foi) | voir ci-dessus |
| `GET /v1/notes` | `Authorization: Bearer <jeton>` | toutes les notes, supprimées comprises, au format `CloudNoteDTO` |
| `PUT /v1/notes/<uuid>` | Bearer | envoie une note ; réponse : la version qui fait autorité |

Le format d'une note est celui de la synchro Nextcloud (`schemaVersion` 1, dates
ISO 8601). Un jeton absent ou inconnu donne 401 ; un code faux, 403.

## Fusion

Les deux côtés appliquent la même règle que la synchro Nextcloud
(`SyncEngine.resolveConflict` côté Mac, `SyncMergePolicy` côté Android) :
la version la plus récente gagne ; à égalité, l'identifiant d'appareil le plus
petit ; une suppression l'emporte sur une note active.

Une passe côté téléphone :
1. `GET /v1/notes` ;
2. fusion avec les notes locales, application des versions qui gagnent ;
3. `PUT` des notes locales qui doivent partir (même test que Nextcloud :
   `shouldUploadLocal`), puis application de la réponse si elle diffère.

Déclenchement : 3 s après une modification, au retour de l'app au premier plan,
à l'ouverture, et toutes les 2 minutes tant que c'est activé.

## Limites connues (0.3.0)

- **HTTP, pas HTTPS.** Le trafic est lisible par qui écoute le Wi-Fi. Le jeton
  protège l'accès, pas le contenu. À n'utiliser que sur un réseau de confiance.
  Piste : TLS avec certificat auto-signé épinglé à l'appairage.
- **Un seul Mac par téléphone** : l'appairage garde le nom du dernier Mac.
- **Les images ne sont pas encore synchronisées** (voir la release 0.2.12).
- **Pas de synchro Mac → téléphone à l'initiative du Mac** : le téléphone tire
  et pousse. Si le téléphone est éteint, rien ne part.
- **macOS seul** : l'iOS n'a pas de serveur.
