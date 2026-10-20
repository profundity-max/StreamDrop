#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
read -r APP_VERSION < VERSION
read -r APP_BUILD < BUILD_NUMBER
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$APP_BUILD" =~ ^[1-9][0-9]*$ ]]
mkdir -p output
swift build -c release --arch arm64 --arch x86_64 --product StreamDrop
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="$PWD/output/StreamDrop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/StreamDrop" "$APP/Contents/MacOS/StreamDrop"
cp README.md "$APP/Contents/Resources/README.md"
swift scripts/icon.swift output/AppIcon.iconset
iconutil -c icns output/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.streamdrop.app</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
<key>CFBundleName</key><string>StreamDrop</string>
<key>CFBundleDisplayName</key><string>StreamDrop</string>
<key>CFBundleExecutable</key><string>StreamDrop</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>0</string>
<key>CFBundleShortVersionString</key><string>0.0.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
<key>NSHumanReadableCopyright</key><string>StreamDrop</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" output/StreamDrop-macOS.zip
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/streamdrop-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/StreamDrop.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -ov -volname StreamDrop -srcfolder "$STAGING" -format UDZO output/StreamDrop.dmg
printf 'Built: %s\n' "$APP"
