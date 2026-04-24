#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Soul DJ"
EXECUTABLE_NAME="MiniMaxTTSStudio"
APP_DIR="$ROOT_DIR/macos/$APP_NAME.app"
OLD_APP_DIR="$ROOT_DIR/macos/MiniMax TTS Studio.app"
OLD_VELVET_APP_DIR="$ROOT_DIR/macos/Velvet Ai FM.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/icon.png"
ICON_NAME="AppIcon"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
rm -rf "$OLD_APP_DIR"
rm -rf "$OLD_VELVET_APP_DIR"

swiftc $(find "$ROOT_DIR/native/macos-app" -name '*.swift' | sort) \
  -framework AppKit \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework Network \
  -framework CoreImage \
  -o "$MACOS_DIR/$EXECUTABLE_NAME"

if [[ -f "$ICON_SOURCE" ]]; then
  ICONSET_DIR="$ROOT_DIR/macos/.${ICON_NAME}.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$ICON_NAME.icns"
  rm -rf "$ICONSET_DIR"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>fm.soul.dj</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <key>NSAllowsArbitraryLoadsForMedia</key>
    <true/>
  </dict>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || {
  echo "Warning: ad-hoc codesign failed; app was built but may show extra Gatekeeper warnings." >&2
}

echo "Built: $APP_DIR"
