#!/bin/zsh
# Construit « hERALD.app » dans le dossier du projet. Si un script de signature ../_tools/sign_app.sh existe
# (certificat local stable), il signe l'appli ; sinon signature ad hoc.
set -euo pipefail
cd "$(dirname "$0")"
APP="hERALD.app"
rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/icon.iconset

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $arch-apple-macos14 -o build/Herald-$arch Sources/*.swift
done
lipo -create build/Herald-arm64 build/Herald-x86_64 -output "$APP/Contents/MacOS/Herald"

swift Resources/make_icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out build/icon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out build/icon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
rm -rf build
SIGN="$(cd .. && pwd)/_tools/sign_app.sh"
if [ -x "$SIGN" ]; then "$SIGN" "$APP"; else codesign --force --deep -s - "$APP"; fi
echo "OK : $APP"
[ -n "${NO_OPEN:-}" ] || open "$APP"
