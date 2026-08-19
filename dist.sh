#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Builds a shareable release: ad-hoc signed .app, then packages it as a
# drag-to-Applications DMG and a plain zip (for GitHub Releases etc).
# Everything runs in a temp dir — the Desktop copy of the app picks up
# com.apple.provenance xattrs from iCloud sync, which break codesign.
# The final DMG/zip are copied to dist/ when done.

VERSION=$(grep '^let appVersion' Sources/UpdateChecker.swift | sed -E 's/.*"([^"]+)".*/\1/')

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/macdraw.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "== building app =="
swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/macdraw" \
  -framework AppKit -framework Carbon -framework SwiftUI

echo "== copying resources =="
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

echo "== signing with self-signed cert =="
# Ad-hoc signed apps downloaded from the internet get flagged "damaged" by
# Gatekeeper, and unsigned apps won't run at all on macOS 15+. A self-signed
# code-signing identity (created once via scripts/make_signing_identity.sh)
# gives a valid signature: Gatekeeper shows the standard "unidentified
# developer" prompt, which right-click -> Open accepts.
codesign --force --deep --sign "macdraw-local-signing" "$APP" || codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "signature OK"

echo "== packaging =="
rm -rf dist build/staging
mkdir -p dist build/staging

rsync -a "$APP" build/staging/
ln -s /Applications build/staging/Applications
cp "Resources/How to open macdraw.rtf" build/staging/

echo "-- DMG --"
hdiutil create -volname "macdraw $VERSION" \
  -srcfolder build/staging -ov -format UDZO \
  "dist/macdraw-$VERSION.dmg"

echo "-- ZIP --"
(cd "$WORK" && zip -ryq dist-macdraw.zip macdraw.app)
mv "$WORK/dist-macdraw.zip" "dist/macdraw-$VERSION.zip"

echo ""
echo "Release files:"
ls -lh dist/