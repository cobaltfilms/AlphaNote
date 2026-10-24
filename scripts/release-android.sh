#!/usr/bin/env bash
#
# Livraison Android : APK release signé -> pièce jointe de la release Gitea
# v<version> (créée si besoin) -> appcast-android.json à la racine du dépôt.
#
# Usage :
#   scripts/release-android.sh 0.2.1 "Notes de version…"
# Identifiants Gitea : GITEA_TOKEN, sinon le mot de passe stocké par git
# (credential helper) pour git.cobaltfilms.be.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="${1:?version requise (ex. 0.2.1)}"
NOTES="${2:-AlphaNote Android $VERSION}"
REPO="paul/AlphaNote"
INSTANCE="https://git.cobaltfilms.be"
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"

GRADLE_VERSION="$(grep -E '^ *versionName = "' Android/app/build.gradle.kts | sed -E 's/.*"([^"]+)".*/\1/')"
if [[ "$GRADLE_VERSION" != "$VERSION" ]]; then
    echo "✗ build.gradle.kts dit $GRADLE_VERSION, pas $VERSION — mets versionName/versionCode à jour." >&2
    exit 1
fi
VERSION_CODE="$(grep -E '^ *versionCode = [0-9]' Android/app/build.gradle.kts | sed -E 's/.*= *([0-9]+).*/\1/')"

echo "› tests unitaires + APK release"
(cd Android && ./gradlew --no-daemon -q :app:testDebugUnitTest :app:assembleRelease)
APK_SRC="Android/app/build/outputs/apk/release/app-release.apk"
[[ -f "$APK_SRC" ]] || APK_SRC="Android/app/build/outputs/apk/release/app-release-unsigned.apk"
mkdir -p dist
APK="dist/AlphaNote-$VERSION.apk"
cp "$APK_SRC" "$APK"
echo "  $APK ($(du -h "$APK" | cut -f1))"

json_escape() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

AUTH=()
if [[ -n "${GITEA_TOKEN:-}" ]]; then
    AUTH=(-H "Authorization: token $GITEA_TOKEN")
else
    CRED="$(printf 'protocol=https\nhost=git.cobaltfilms.be\n' | git credential fill 2>/dev/null || true)"
    U="$(printf '%s' "$CRED" | sed -n 's/^username=//p')"; P="$(printf '%s' "$CRED" | sed -n 's/^password=//p')"
    [[ -n "$U" && -n "$P" ]] && AUTH=(-u "$U:$P")
fi

DL_URL="REMPLACEZ_PAR_URL_DE_L_APK"
if [[ ${#AUTH[@]} -gt 0 ]]; then
    RELEASE_ID="$(curl -fsS "${AUTH[@]}" "$INSTANCE/api/v1/repos/$REPO/releases/tags/v$VERSION" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])' 2>/dev/null || true)"
    if [[ -z "$RELEASE_ID" ]]; then
        echo "› release Gitea v$VERSION"
        git rev-parse "v$VERSION" >/dev/null 2>&1 || { git tag -a "v$VERSION" -m "AlphaNote $VERSION"; git push origin "v$VERSION"; }
        RELEASE_ID="$(curl -fsS "${AUTH[@]}" -X POST "$INSTANCE/api/v1/repos/$REPO/releases" -H "Content-Type: application/json" \
            -d "{\"tag_name\":\"v$VERSION\",\"name\":\"AlphaNote $VERSION\",\"body\":$(json_escape "$NOTES")}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')"
    fi
    echo "› pièce jointe APK (release $RELEASE_ID)"
    DL_URL="$(curl -fsS "${AUTH[@]}" -X POST "$INSTANCE/api/v1/repos/$REPO/releases/$RELEASE_ID/assets" -F "attachment=@$APK" | python3 -c 'import json,sys;print(json.load(sys.stdin)["browser_download_url"])')"
    echo "  $DL_URL"
else
    echo "  Aucun identifiant Gitea : attache $APK à la release v$VERSION et complète appcast-android.json."
fi

cat > appcast-android.json <<APPCAST
{
  "version": "$VERSION",
  "versionCode": $VERSION_CODE,
  "notes": $(json_escape "$NOTES"),
  "url": "$DL_URL",
  "minimumSdk": 26
}
APPCAST
echo "✓ appcast-android.json écrit — committe-le."
