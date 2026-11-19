#!/bin/bash
set -euo pipefail
ATLAS_ROOT="$(cd "$(dirname "$0")" && pwd)"
ATLAS_APP="$ATLAS_ROOT/dist/Contributor Atlas.app"
swift build --package-path "$ATLAS_ROOT" -c release
ATLAS_BIN="$(swift build --package-path "$ATLAS_ROOT" -c release --show-bin-path)"
mkdir -p "$ATLAS_APP/Contents/MacOS" "$ATLAS_APP/Contents/Resources"
cp "$ATLAS_BIN/ContributorAtlas" "$ATLAS_APP/Contents/MacOS/ContributorAtlas"
cat > "$ATLAS_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ContributorAtlas</string>
<key>CFBundleIdentifier</key><string>co.cosign.contributor-atlas</string>
<key>CFBundleName</key><string>Contributor Atlas</string>
<key>CFBundleDisplayName</key><string>Contributor Atlas</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
swift "$ATLAS_ROOT/make-icon.swift" "$ATLAS_ROOT/dist"
cp "$ATLAS_ROOT/dist/AppIcon.icns" "$ATLAS_APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$ATLAS_APP"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  ditto "$ATLAS_APP" "$HOME/Applications/Contributor Atlas.app"
  echo "$HOME/Applications/Contributor Atlas.app"
else
  echo "$ATLAS_APP"
fi
