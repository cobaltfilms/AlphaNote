#!/usr/bin/env bash
#
# Livraison Android : APK release signé -> release GitHub v<version> (créée si
# besoin, voir publish-github.sh) -> appcast-android.json publié sur GitHub.
#
# Usage :
#   scripts/release-android.sh 0.2.1 "Notes de version…"
# Requiert `gh` connecté au compte cobaltfilms.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="${1:?version requise (ex. 0.2.1)}"
NOTES="${2:-AlphaNote Android $VERSION}"
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
source scripts/publish-github.sh

echo "› tag v$VERSION (Gitea)"
git rev-parse "v$VERSION" >/dev/null 2>&1 || git tag -a "v$VERSION" -m "AlphaNote $VERSION"
git push origin "v$VERSION" 2>/dev/null || true

echo "› release GitHub v$VERSION + APK"
DL_URL="$(gh_release_asset "$VERSION" "$APK" "$NOTES")"
echo "  $DL_URL"

cat > appcast-android.json <<APPCAST
{
  "version": "$VERSION",
  "versionCode": $VERSION_CODE,
  "notes": $(json_escape "$NOTES"),
  "url": "$DL_URL",
  "minimumSdk": 26
}
APPCAST
echo "› appcast-android.json publié"
gh_publish_file appcast-android.json
echo "✓ v$VERSION livrée — committe appcast-android.json sur Gitea."
