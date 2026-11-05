#!/bin/zsh
# Régénère les fichiers de l'icône depuis son dessin (make_icon.swift) : hERALD_1024.png et hERALD.icns.
# À relancer après toute retouche de make_icon.swift ; build_app.sh se sert de hERALD.icns.
set -euo pipefail
cd "$(dirname "$0")"
T=$(mktemp -d)
swift make_icon.swift hERALD_1024.png
mkdir "$T/icon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s hERALD_1024.png --out "$T/icon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) hERALD_1024.png --out "$T/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$T/icon.iconset" -o hERALD.icns
rm -rf "$T"
echo "OK : assets/hERALD_1024.png, assets/hERALD.icns"
