#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Builds a shareable release: ad-hoc signed .app, then packages it as a
# drag-to-Applications DMG and a plain zip (for GitHub Releases etc).

VERSION="1.0"

echo "== building app =="
./build.sh

echo "== packaging =="
rm -rf dist build/staging
mkdir -p dist build/staging

rsync -a build/macdraw.app build/staging/
ln -s /Applications build/staging/Applications

echo "-- DMG --"
hdiutil create -volname "macdraw $VERSION" \
  -srcfolder build/staging -ov -format UDZO \
  "dist/macdraw-$VERSION.dmg"

echo "-- ZIP --"
(cd build && zip -ryq ../dist/macdraw-$VERSION.zip macdraw.app)

echo ""
echo "Release files:"
ls -lh dist/
echo ""
echo "End users on macOS 15+ can drag the app to Applications and"
echo "right-click -> Open the first time (free, no Developer ID)."
