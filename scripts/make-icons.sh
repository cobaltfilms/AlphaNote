#!/usr/bin/env bash
#
# Génère les icônes depuis design/AlphaNoteIcon.svg (motif corail #ef7b5f) :
#   · macOS : AppIcon.appiconset + AppIconDock.png (icône du bundle, corail) ;
#   · Android : icône de l'app (corail) + une icône de lancement par thème
#     de couleur (mipmap*/ic_launcher_<thème>*, alias dans le manifeste) ;
#   · iOS : AppIcon (corail, plein cadre : iOS arrondit lui-même) + une icône
#     alternative par thème (AppIcon-<thème>, choisie avec le thème).
# `ONLY=ios scripts/make-icons.sh` ne régénère que les icônes iOS.
# Requiert rsvg-convert (brew install librsvg).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/design/AlphaNoteIcon.svg"
RES="$ROOT/Android/app/src/main/res"
AS="$ROOT/Sources/AlphaNote/Resources/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Accent de nuit de chaque thème (ColorTheme, macOS et Android).
THEMES=(or:d9a441 corail:ef7b5f sauge:7fbfa8 lavande:a78bfa framboise:e86a8e bleu:5b9cf0)
DENSITIES=(mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4)

# Variantes : tuile complète, marque seule (avant-plan adaptatif), rond.
variants() { # $1 = svg source, $2 = préfixe de sortie
    python3 -I - "$1" "$2" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
inner = src.split(">", 1)[1].rsplit("</svg>", 1)[0]
mark = re.sub(r'\s*<rect width="1024"[^>]*/>\s*<rect x="44"[^>]*/>', "", inner)
def wrap(scale, bg=""):
    return ('<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">'
            f'{bg}<g transform="translate(512 512) scale({scale}) translate(-512 -494)">{mark}</g></svg>')
open(sys.argv[2] + "-fg.svg", "w").write(wrap(0.70))  # tient dans la zone sûre de 66 dp
open(sys.argv[2] + "-round.svg", "w").write(wrap(0.78, '<circle cx="512" cy="512" r="512" fill="#22272e"/>'))
PY
}

android_set() { # $1 = svg, $2 = suffixe ("" ou "_<thème>")
    variants "$1" "$TMP/v"
    for d in "${DENSITIES[@]}"; do
        local n=${d%%:*} k=${d#*:}
        local L F
        L=$(python3 -c "print(int(48*$k))"); F=$(python3 -c "print(int(108*$k))")
        rsvg-convert -w "$L" -h "$L" "$1" -o "$RES/mipmap-$n/ic_launcher$2.png"
        rsvg-convert -w "$L" -h "$L" "$TMP/v-round.svg" -o "$RES/mipmap-$n/ic_launcher$2_round.png"
        rsvg-convert -w "$F" -h "$F" "$TMP/v-fg.svg" -o "$RES/mipmap-$n/ic_launcher$2_foreground.png"
    done
    for kind in "" _round; do
        cat > "$RES/mipmap-anydpi-v26/ic_launcher$2$kind.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher$2_foreground"/>
</adaptive-icon>
XML
    done
}

ios_set() { # $1 = svg, $2 = nom du jeu d'icônes
    local dir="$ROOT/iOS/App/Assets.xcassets/$2.appiconset"
    mkdir -p "$dir"
    sed 's/rx="220"/rx="0"/' "$1" > "$TMP/ios.svg"
    rsvg-convert -w 1024 -h 1024 -b "#22272e" "$TMP/ios.svg" -o "$dir/icon.png"
    cat > "$dir/Contents.json" <<JSON
{
  "images" : [ { "filename" : "icon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
}

echo "› iOS"
ios_set "$SVG" AppIcon
for t in "${THEMES[@]}"; do
    name=${t%%:*}; accent=${t#*:}
    [[ $name == corail ]] && continue
    sed "s/#ef7b5f/#$accent/g" "$SVG" > "$TMP/$name.svg"
    ios_set "$TMP/$name.svg" "AppIcon-$name"
done
[[ "${ONLY:-}" == ios ]] && { echo "✓ icônes iOS générées"; exit 0; }

echo "› macOS"
for f in 16 32 128 256 512; do
    rsvg-convert -w $f -h $f "$SVG" -o "$AS/icon_${f}x${f}.png"
    if [[ $f -lt 512 ]]; then rsvg-convert -w $((f * 2)) -h $((f * 2)) "$SVG" -o "$AS/icon_${f}x${f}@2x.png"; fi
done
rsvg-convert -w 1024 -h 1024 "$SVG" -o "$AS/icon_1024x1024.png"
cp "$AS/icon_1024x1024.png" "$ROOT/Sources/AlphaNote/Resources/AppIconDock.png"

echo "› Android"
android_set "$SVG" ""
for t in "${THEMES[@]}"; do
    name=${t%%:*}; accent=${t#*:}
    sed "s/#ef7b5f/#$accent/g" "$SVG" > "$TMP/$name.svg"
    android_set "$TMP/$name.svg" "_$name"
done
echo "✓ icônes générées"
