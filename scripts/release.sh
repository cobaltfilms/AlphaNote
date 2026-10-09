#!/usr/bin/env bash
#
# Livraison d'une version :
#   validation -> AlphaNote.app + zip -> tag git -> release Gitea (zip en pièce
#   jointe) -> appcast.json pointant sur l'URL de téléchargement du zip.
#
# L'updater d'AlphaNote lit cet appcast (Réglages > Updates) et propose la mise
# à jour. Le zip est hébergé en pièce jointe de la release Gitea, comme pour
# AlphaSUB/AlphaDCP.
#
# Usage :
#   GITEA_TOKEN=<jeton> scripts/release.sh 1.0.0 "Notes de version…"
# Sans GITEA_TOKEN : construit .app + zip + tag, écrit un appcast.json à
# compléter à la main.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="${1:?version requise (ex. 1.0.0)}"
NOTES="${2:-AlphaNote $VERSION}"
REPO="paul/AlphaNote"
INSTANCE="https://git.cobaltfilms.be"
ZIP="dist/AlphaNote-$VERSION.zip"

json_escape() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

echo "› validation"
bash scripts/validate.sh "$VERSION"

echo "› tag v$VERSION"
git tag -a "v$VERSION" -m "AlphaNote $VERSION"
git push origin "v$VERSION" 2>/dev/null || echo "  (tag non poussé — pouss-le à la main)"

echo "› zip : $ZIP"

DL_URL="REMPLACEZ_PAR_URL_DU_ZIP"
if [[ -n "${GITEA_TOKEN:-}" ]]; then
    echo "› release Gitea + upload du zip"
    RELEASE_JSON=$(curl -fsS -X POST "$INSTANCE/api/v1/repos/$REPO/releases" \
        -H "Authorization: token $GITEA_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"tag_name\":\"v$VERSION\",\"name\":\"AlphaNote $VERSION\",\"body\":$(json_escape "$NOTES")}")
    RELEASE_ID=$(printf '%s' "$RELEASE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')

    ASSET_JSON=$(curl -fsS -X POST "$INSTANCE/api/v1/repos/$REPO/releases/$RELEASE_ID/assets" \
        -H "Authorization: token $GITEA_TOKEN" \
        -F "attachment=@$ZIP")
    DL_URL=$(printf '%s' "$ASSET_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["browser_download_url"])')
    echo "  pièce jointe : $DL_URL"
else
    echo "  GITEA_TOKEN absent : crée la release v$VERSION à la main, attache $ZIP,"
    echo "  puis remplace REMPLACEZ_PAR_URL_DU_ZIP dans appcast.json."
fi

echo "› appcast.json"
cat > appcast.json <<APPCAST
{
  "version": "$VERSION",
  "notes": $(json_escape "$NOTES"),
  "url": "$DL_URL",
  "minimumSystemVersion": "14.0"
}
APPCAST

echo "✓ livré v$VERSION"
echo "  1. Committe appcast.json (il vit à la racine du dépôt)."
echo "  2. Dans Réglages > Updates, mets l'URL brute de l'appcast :"
echo "     $INSTANCE/$REPO/raw/branch/main/appcast.json"
