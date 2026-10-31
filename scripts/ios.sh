#!/usr/bin/env bash
#
# AlphaNote iOS dans le simulateur.
#
#   scripts/ios.sh build   # génère le projet (XcodeGen) et compile
#   scripts/ios.sh test    # tests partagés macOS/iOS dans le simulateur
#   scripts/ios.sh run     # compile, installe et lance dans le simulateur
#   scripts/ios.sh demo    # visite guidée filmée (iOS/build/demo.mp4)
#
# Variables : IOS_SIMULATOR (défaut « iPhone 18 Pro »).
# Requiert : xcodegen (brew install xcodegen), un runtime iOS
# (xcodebuild -downloadPlatform iOS).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS="$ROOT/iOS"
SIM="${IOS_SIMULATOR:-iPhone 18 Pro}"
DERIVED="$IOS/build/dd"
ACTION="${1:-build}"

# Sonneries de notification : iOS refuse le .m4a pour une notification et la
# joue une seule fois ; on boucle chaque sonnerie (~2 s) jusqu'à ~28 s (limite
# 30 s) en .caf IMA4. Régénérées seulement si la source a changé.
make_sounds() {
    local out="$IOS/App/Sounds" tmp
    mkdir -p "$out"
    tmp="$(mktemp -d)"
    for src in "$ROOT"/Sources/AlphaNote/Resources/Sounds/*.m4a; do
        local name dst
        name="$(basename "$src" .m4a)"
        dst="$out/alarm-$name.caf"
        [[ -f "$dst" && "$dst" -nt "$src" ]] && continue
        afconvert -f WAVE -d LEI16@44100 -c 1 "$src" "$tmp/$name.wav"
        python3 -I - "$tmp/$name.wav" "$tmp/$name-loop.wav" <<'PY'
import sys, wave
src, dst = sys.argv[1], sys.argv[2]
with wave.open(src) as w:
    params, frames = w.getparams(), w.readframes(w.getnframes())
seconds = len(frames) / (params.sampwidth * params.nchannels * params.framerate)
gap = b"\0" * int(0.4 * params.framerate) * params.sampwidth * params.nchannels
repeat = max(1, int(28 // (seconds + 0.4)))
with wave.open(dst, "wb") as w:
    w.setparams(params)
    w.writeframes((frames + gap) * repeat)
PY
        afconvert -f caff -d ima4 "$tmp/$name-loop.wav" "$dst"
    done
    rm -rf "$tmp"
}

generate() {
    make_sounds
    (cd "$IOS" && xcodegen generate --quiet)
}

xcb() {
    xcodebuild -project "$IOS/AlphaNote.xcodeproj" -scheme AlphaNote \
        -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$DERIVED" "$@"
}

case "$ACTION" in
    build)
        generate
        xcb build | grep -E 'error:|warning: .*AlphaNote|BUILD (SUCCEEDED|FAILED)' || true
        ;;
    test)
        generate
        xcb test | grep -E 'error:|failed|Executed .* tests|TEST (SUCCEEDED|FAILED)' || true
        ;;
    run)
        generate
        xcb build | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
        APP="$DERIVED/Build/Products/Debug-iphonesimulator/AlphaNote.app"
        xcrun simctl boot "$SIM" 2>/dev/null || true
        xcrun simctl install "$SIM" "$APP"
        xcrun simctl launch "$SIM" be.cobaltfilms.alphanote
        # Xcode 27 : Simulator.app est remplacé par Device Hub ; le lien
        # devices:// amène le simulateur au premier plan dans sa fenêtre.
        UDID="$(xcrun simctl list devices | grep -F "($SIM)" | head -1 | grep -oE '[0-9A-F-]{36}')"
        if [[ -n "$UDID" ]]; then
            open "devices://device/open?id=$UDID" 2>/dev/null \
                || open -a DeviceHub 2>/dev/null || true
        fi
        ;;
    demo)
        generate
        xcrun simctl boot "$SIM" 2>/dev/null || true
        open "$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || true
        xcb build-for-testing | grep -E 'error:|TEST BUILD (SUCCEEDED|FAILED)' || true
        # Apparence de départ : système, Encre & or (la démo passe en Sauge sombre).
        xcrun simctl terminate "$SIM" be.cobaltfilms.alphanote 2>/dev/null || true
        PREFS="$(xcrun simctl get_app_container "$SIM" be.cobaltfilms.alphanote data 2>/dev/null)/Library/Preferences/be.cobaltfilms.alphanote.plist"
        for key in theme colorTheme; do
            plutil -remove "$key" "$PREFS" 2>/dev/null || true
        done
        rm -f "$IOS/build/demo.mp4"
        xcrun simctl io "$SIM" recordVideo --codec h264 --force "$IOS/build/demo.mp4" &
        REC=$!
        sleep 2
        TEST_RUNNER_ALPHANOTE_DEMO=1 xcb test-without-building -only-testing:AlphaNoteUITests/DemoTour \
            | grep -E 'DEMO|error:|passed|failed \(' || true
        kill -INT "$REC"; wait "$REC" 2>/dev/null || true
        echo "vidéo : $IOS/build/demo.mp4"
        ;;
    *)
        echo "usage: $0 build|test|run|demo" >&2
        exit 2
        ;;
esac
