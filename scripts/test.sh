#!/usr/bin/env bash
#
# Cœur partagé : build + tests. C'est exactement ce que lance la CI
# (.gitea/workflows/ci.yml). Le faire tourner en local avant de pousser évite
# une CI rouge.
#
# Usage : scripts/test.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "› swift build"
swift build

echo "› swift test"
swift test

echo "✓ build + tests OK"
