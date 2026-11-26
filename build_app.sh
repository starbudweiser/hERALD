#!/bin/zsh
# Construit « hERALD.app » dans le dossier du projet. Si un script de signature ../_tools/sign_app.sh existe
# (certificat local stable), il signe l'appli ; sinon signature ad hoc.
#   ./build_app.sh          version locale : hERALD.app (fr.stephan.herald), universelle (arm64 + x86_64)
#   DEV=1 ./build_app.sh    version de développement : « hERALD Dev.app » (fr.stephan.herald.dev), arm64 seul,
#                           dans le dossier du projet, sans installation ; données à part
#                           (~/Library/Application Support/hERALD Dev, copiées une fois depuis hERALD), pas de mise à jour auto.
# NO_OPEN=1 : ne pas lancer (lancement toujours en arrière-plan, sans prendre le focus).
set -euo pipefail
cd "$(dirname "$0")"
if [ -n "${DEV:-}" ]; then APP="hERALD Dev.app"; ARCHS=(arm64); else APP="hERALD.app"; ARCHS=(arm64 x86_64); fi
rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build

for arch in $ARCHS; do
  swiftc -O -swift-version 5 -parse-as-library -target $arch-apple-macos14 -o build/Herald-$arch Sources/*.swift
done
lipo -create build/Herald-*(.) -output "$APP/Contents/MacOS/Herald"

cp assets/hERALD.icns "$APP/Contents/Resources/AppIcon.icns"   # sources : assets/ (make_icon.sh)
cp Resources/Info.plist "$APP/Contents/Info.plist"
for l in Resources/*.lproj; do cp -R "$l" "$APP/Contents/Resources/"; done
rm -rf build
if [ -n "${DEV:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier fr.stephan.herald.dev" -c "Set :CFBundleName hERALD Dev" \
    -c "Set :CFBundleDisplayName hERALD Dev" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier fr.stephan.herald.dev" -c "Set :CFBundleName hERALD Dev" \
         -c "Add :CFBundleDisplayName string hERALD Dev" "$APP/Contents/Info.plist"
  # Données d'essai : copie unique du vrai plan, la version de dev n'écrit jamais dans celui de la version locale.
  SUP="$HOME/Library/Application Support"
  [ -d "$SUP/hERALD Dev" ] || { [ -d "$SUP/hERALD" ] && cp -R "$SUP/hERALD" "$SUP/hERALD Dev" || mkdir -p "$SUP/hERALD Dev"; }
fi
SIGN="$(cd .. && pwd)/_tools/sign_app.sh"
if [ -x "$SIGN" ]; then "$SIGN" "$APP"; else codesign --force --deep -s - "$APP"; fi
echo "OK : $APP"
[ -n "${NO_OPEN:-}" ] || open -g "$APP"
