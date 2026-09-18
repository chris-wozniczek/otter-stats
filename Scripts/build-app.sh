#!/usr/bin/env bash
# Build OtterStats.app from the SwiftPM executable.
#   Scripts/build-app.sh            -> dist/OtterStats.app (release)
#   Scripts/build-app.sh --zip      -> also dist/OtterStats.zip
#   CODESIGN_ID="Developer ID Application: ..." Scripts/build-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(git describe --tags --always 2>/dev/null || echo 0.1.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:-arm64 x86_64}"
DIST="$ROOT/dist"
APP="$DIST/OtterStats.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BINS=()
for arch in $ARCHS; do
  echo "==> swift build -c release --arch $arch"
  swift build -c release --arch "$arch" --product OtterStats >/dev/null
  BINS+=(".build/${arch}-apple-macosx/release/OtterStats")
done

if [ "${#BINS[@]}" -gt 1 ]; then
  lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/OtterStats"
else
  cp "${BINS[0]}" "$APP/Contents/MacOS/OtterStats"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>OtterStats</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>dev.otterswarm.otter-stats</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Otter Stats</string>
  <key>CFBundleDisplayName</key><string>Otter Stats</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION#v}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
elif [ -f "$ROOT/Resources/AppIcon.png" ] && command -v iconutil >/dev/null; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> codesign (${CODESIGN_ID:-ad-hoc})"
codesign --force --deep --options runtime \
  --sign "${CODESIGN_ID:--}" "$APP"

if [ "${1:-}" = "--zip" ]; then
  (cd "$DIST" && rm -f OtterStats.zip && ditto -c -k --keepParent OtterStats.app OtterStats.zip)
  echo "==> $DIST/OtterStats.zip"
fi

echo "==> $APP  (version ${VERSION#v}, build $BUILD_NUMBER)"
