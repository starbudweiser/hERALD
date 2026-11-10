#!/bin/zsh
# Publie une version de hERALD (compilation, signature Developer ID, notarisation, release GitHub) via l'outil commun.
# Usage : ./release.sh [--notes "texte"] [--replace]   — la version vient de Resources/Info.plist.
exec "$(cd "$(dirname "$0")/.." && pwd)/_tools/release_app.sh" hERALD "$@"
