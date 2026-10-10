#!/usr/bin/env bash
#
# Emballe le binaire SPM d'AlphaNote en AlphaNote.app (Info.plist + signature
# ad-hoc), seul format sur lequel le système de mise à jour peut remplacer
# l'app elle-même.
#
# Usage:
#   scripts/build-app.sh                 # version 0.1.0
#   scripts/build-app.sh 1.2.0           # version explicite
#   scripts/build-app.sh 1.2.0 --zip     # + AlphaNote-1.2.0.zip pour l'appcast
#
set -euo pipefail

VERSION="${1:-0.1.0}"
MAKE_ZIP="${2:-}"

APP_NAME="AlphaNote"
BUNDLE_ID="be.cobaltfilms.alphanote"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "› swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

if [[ ! -x "$BIN/$APP_NAME" ]]; then
    echo "✗ binaire introuvable dans $BIN" >&2
    exit 1
fi

echo "› assemblage de $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Bundle de ressources SPM (docs d'aide, etc.) — BundleModule le cherche à
# côté de l'exécutable.
for bundle in "$BIN"/*_"$APP_NAME".bundle; do
    [[ -e "$bundle" ]] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>  <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
    <key>NSMicrophoneUsageDescription</key> <string>AlphaNote utilise le microphone pour la dictée vocale.</string>
    <key>NSSpeechRecognitionUsageDescription</key> <string>AlphaNote transcrit votre voix pour transformer vos demandes en notes.</string>
</dict>
</plist>
PLIST

echo "› signature ad-hoc"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "  signature OK"

echo "✓ $APP (v$VERSION)"

if [[ "$MAKE_ZIP" == "--zip" ]]; then
    ZIP="$DIST/$APP_NAME-$VERSION.zip"
    echo "› zip de release : $ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    cat <<APPCAST
Copie ce contenu dans ton appcast.json :
{
  "version": "$VERSION",
  "notes": "Notes de version…",
  "url": "https://…/AlphaNote-$VERSION.zip",
  "minimumSystemVersion": "$MIN_MACOS"
}
APPCAST
fi
