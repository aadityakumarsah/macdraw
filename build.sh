#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build + sign in a temp dir outside the iCloud-synced folder (Desktop stamps
# com.apple.FinderInfo xattrs which make codesign fail), then copy back.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/macdraw.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "== compiling =="
swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/macdraw" \
  -framework AppKit -framework Carbon -framework SwiftUI

echo "== copying resources =="
# Stage icons with solid stroke color (they use stroke="currentColor")
rsync -a Resources/ "$APP/Contents/Resources/"
find "$APP/Contents/Resources/Icons" -name '*.svg' \
  -exec sed -i '' 's/stroke="currentColor"/stroke="#000000"/g' {} +

cat > "$APP/Contents/Info.plist" <<'PLIST'
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
	<string>1</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
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

echo ""
echo "Built: $(pwd)/build/macdraw.app"
echo "Run:   open $(pwd)/build/macdraw.app"
