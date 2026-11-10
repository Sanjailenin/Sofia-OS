#!/bin/zsh
set -e -o pipefail
cd "$(dirname "$0")/.."
ARCHS=(${=SOFIA_ARCHS:-arm64 x86_64})
SLICES=()
for arch in $ARCHS; do
  swift build -c release --build-system native --triple "$arch-apple-macosx13.0" 2>&1 | { grep -v "ld: warning" || true; } | tail -1
  SLICES+=("$(swift build -c release --build-system native --triple "$arch-apple-macosx13.0" --show-bin-path 2>/dev/null)/Sofia")
done
APP=build/Sofia.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
lipo -create -output "$APP/Contents/MacOS/Sofia" "${SLICES[@]}"
lipo -info "$APP/Contents/MacOS/Sofia"
ICONSET=build/Sofia.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET" "$APP/Contents/Resources"
for size in 16 32 128 256 512; do
  sips -z $size $size docs/logo.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) docs/logo.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Sofia.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.sofia.app</string>
  <key>CFBundleName</key><string>Sofia</string>
  <key>CFBundleExecutable</key><string>Sofia</string>
  <key>CFBundleIconFile</key><string>Sofia</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-0.1.0}</string>
  <key>CFBundleVersion</key><string>${BUILD:-1}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSSpeechRecognitionUsageDescription</key><string>Speech is recognised on this Mac to hear the wake phrase and what you say. Nothing is sent anywhere.</string>
  <key>NSAppleEventsUsageDescription</key><string>Sofia can control music, dark mode and type text for you, only from a fixed list of actions and only when you ask.</string>
  <key>NSCalendarsUsageDescription</key><string>Sofia reads today's events so she stays quiet during meetings and warns about battery before one. Nothing leaves the Mac.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Sofia reads today's events so she stays quiet during meetings and warns about battery before one. Nothing leaves the Mac.</string>
  <key>NSMicrophoneUsageDescription</key><string>Sofia listens for the wake phrase and records what you say after it. Audio stays on this Mac.</string>
</dict></plist>
PLIST
if [ -n "${SOFIA_SIGN_IDENTITY:-}" ]; then
  IDENTITY="$SOFIA_SIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"Sofia Release"'; then
  IDENTITY="Sofia Release"
else
  IDENTITY="-"
fi
ENT=build/Sofia.entitlements
cat > "$ENT" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
  <key>com.apple.security.device.audio-input</key><true/>
  <key>com.apple.security.automation.apple-events</key><true/>
  <key>com.apple.security.personal-information.calendars</key><true/>
</dict></plist>
XML
codesign --force --deep --options runtime --entitlements "$ENT" --sign "$IDENTITY" "$APP" 2>&1 | grep -v "replacing existing signature" || true
echo "Built $APP (signed with: $IDENTITY)"
