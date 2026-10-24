#!/usr/bin/env bash
#
# Livraison d'une version :
#   validation -> AlphaNote.app + zip -> tag git -> release GitHub (zip en
#   asset, voir publish-github.sh) -> appcast.json publié sur GitHub.
#
# L'updater d'AlphaNote lit cet appcast (Réglages > Updates) et propose la mise
# à jour. Le zip est hébergé sur GitHub, comme pour AlphaSUB/AlphaDCP (Gitea
# exige une connexion, même pour un dépôt public).
#
# Usage :
#   scripts/release.sh 1.0.0 "Notes de version…"   (requiert `gh` connecté)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="${1:?version requise (ex. 1.0.0)}"
NOTES="${2:-AlphaNote $VERSION}"
ZIP="dist/AlphaNote-$VERSION.zip"

source scripts/publish-github.sh
json_escape() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

echo "› validation"
bash scripts/validate.sh "$VERSION"

echo "› tag v$VERSION"
git tag -a "v$VERSION" -m "AlphaNote $VERSION"
git push origin "v$VERSION" 2>/dev/null || echo "  (tag non poussé — pouss-le à la main)"

echo "› zip : $ZIP"

echo "› release GitHub v$VERSION + zip"
DL_URL="$(gh_release_asset "$VERSION" "$ZIP" "$NOTES")"
echo "  $DL_URL"

echo "› appcast.json"
cat > appcast.json <<APPCAST
{
  "version": "$VERSION",
  "notes": $(json_escape "$NOTES"),
  "url": "$DL_URL",
  "minimumSystemVersion": "14.0"
}
APPCAST

gh_publish_file appcast.json
echo "✓ livré v$VERSION — committe appcast.json sur Gitea."
