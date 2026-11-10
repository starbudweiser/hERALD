#!/bin/zsh
# Construit « hERALD.app » dans le dossier du projet. Si un script de signature ../_tools/sign_app.sh existe
# (certificat local stable), il signe l'appli ; sinon signature ad hoc.
set -euo pipefail
cd "$(dirname "$0")"
APP="hERALD.app"
rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $arch-apple-macos14 -o build/Herald-$arch Sources/*.swift
done
lipo -create build/Herald-arm64 build/Herald-x86_64 -output "$APP/Contents/MacOS/Herald"

cp assets/hERALD.icns "$APP/Contents/Resources/AppIcon.icns"   # sources : assets/ (make_icon.sh)
cp Resources/Info.plist "$APP/Contents/Info.plist"
for l in Resources/*.lproj; do cp -R "$l" "$APP/Contents/Resources/"; done
rm -rf build
SIGN="$(cd .. && pwd)/_tools/sign_app.sh"
if [ -x "$SIGN" ]; then "$SIGN" "$APP"; else codesign --force --deep -s - "$APP"; fi
echo "OK : $APP"
[ -n "${NO_OPEN:-}" ] || open "$APP"
