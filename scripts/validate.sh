#!/usr/bin/env bash
#
# Validation pré-fusion : le cœur (build + tests, comme la CI) + un build release
# avec emballage .app + zip + un garde-fou sur les secrets. À lancer avant un
# push ou une merge.
#
# Usage : scripts/validate.sh [version-de-test]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "== 1/3  build + tests (comme la CI) =="
bash scripts/test.sh

echo "== 2/3  build release + emballage .app + zip =="
bash scripts/build-app.sh "${1:-0.0.0-validation}" --zip >/dev/null
test -x dist/AlphaNote.app/Contents/MacOS/AlphaNote && echo "  AlphaNote.app + zip OK"

echo "== 3/3  garde-fou secrets =="
if git ls-files --cached --others --exclude-standard | grep -E '(^|/)\.secret\.md$'; then
    echo "✗ un fichier .secret.md est tracké — ne pas committer" >&2
    exit 1
fi

echo "✓ validation OK"
