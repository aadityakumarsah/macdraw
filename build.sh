#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build + sign in a temp dir outside the iCloud-synced folder (Desktop stamps
# com.apple.FinderInfo xattrs which make codesign fail), then copy back.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/macdraw.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Single source of truth for the version: Sources/UpdateChecker.swift.
VERSION=$(grep '^let appVersion' Sources/UpdateChecker.swift | sed -E 's/.*"([^"]+)".*/\1/')
echo "== version: $VERSION =="

echo "== compiling =="
swiftc -O -module-cache-path "$WORK/module-cache" Sources/*.swift -o "$APP/Contents/MacOS/macdraw" \
  -framework AppKit -framework Carbon -framework SwiftUI

echo "== copying resources =="
# Stage icons with solid stroke color (they use stroke="currentColor")
rsync -a Resources/ "$APP/Contents/Resources/"
find "$APP/Contents/Resources/Icons" -name '*.svg' \
  -exec sed -i '' 's/stroke="currentColor"/stroke="#000000"/g' {} +

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>macdraw</string>
	<key>CFBundleIdentifier</key>
	<string>com.local.macdraw</string>
	<key>CFBundleName</key>
	<string>macdraw</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleIconFile</key>
	<string>icon.icns</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "== signing =="
codesign --force --sign - "$APP"
codesign --verify "$APP" && echo "signature OK"

echo "== installing to build/ =="
mkdir -p build
rm -rf build/macdraw.app
rsync -a "$APP" build/
# Desktop/iCloud can attach Finder metadata while the app is copied out of
# the temporary build directory. Remove it and sign the exact app users run.
xattr -cr build/macdraw.app 2>/dev/null || true
codesign --force --sign - build/macdraw.app
codesign --verify --deep --strict build/macdraw.app && echo "installed app signature OK"

echo "== release zip =="
# The app auto-updates by downloading this zip from the GitHub release
# (tag v$VERSION). It must keep the macdraw- prefix and .zip suffix.
ZIP="build/macdraw-v$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/macdraw.app "$ZIP"

echo ""
echo "Built:   $(pwd)/build/macdraw.app"
echo "Release: $(pwd)/$ZIP  (attach to a GitHub release tagged v$VERSION)"
echo "Run:     open $(pwd)/build/macdraw.app"
