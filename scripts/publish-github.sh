#!/usr/bin/env bash
#
# Canal public de releases : github.com/cobaltfilms/AlphaNote.
# git.cobaltfilms.be exige une connexion pour tout (même un dépôt public), donc
# les apps lisent l'appcast et téléchargent les binaires sur GitHub, comme
# AlphaSUB/AlphaDCP. Le code reste sur Gitea ; le dépôt GitHub ne porte que
# les releases et les appcasts.
#
# À sourcer depuis release.sh / release-android.sh. Requiert `gh` connecté au
# compte cobaltfilms.

GH_REPO="cobaltfilms/AlphaNote"

# gh_release_asset <version> <fichier> <notes> → affiche l'URL de téléchargement.
# Crée la release v<version> si besoin ; remplace un asset du même nom.
gh_release_asset() {
    local version="$1" file="$2" notes="$3"
    if ! gh release view "v$version" --repo "$GH_REPO" >/dev/null 2>&1; then
        gh release create "v$version" --repo "$GH_REPO" --title "AlphaNote $version" --notes "$notes" >/dev/null
    fi
    gh release upload "v$version" "$file" --repo "$GH_REPO" --clobber >/dev/null
    echo "https://github.com/$GH_REPO/releases/download/v$version/$(basename "$file")"
}

# gh_publish_file <fichier> : copie le fichier à la racine de main sur GitHub.
gh_publish_file() {
    local file="$1" path sha
    path="$(basename "$file")"
    sha="$(gh api "repos/$GH_REPO/contents/$path" --jq .sha 2>/dev/null || true)"
    gh api -X PUT "repos/$GH_REPO/contents/$path" \
        -f message="$path : $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$file")" \
        -f content="$(base64 < "$file" | tr -d '\n')" \
        ${sha:+-f sha="$sha"} >/dev/null
    echo "  https://raw.githubusercontent.com/$GH_REPO/main/$path"
}
