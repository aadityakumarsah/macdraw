#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Builds a shareable release: ad-hoc signed .app, then packages it as a
# drag-to-Applications DMG and a plain zip (for GitHub Releases etc).

VERSION="1.5"

echo "== building app =="
./build.sh

echo "== signing with self-signed cert =="
# Ad-hoc signed apps downloaded from the internet get flagged "damaged" by
# Gatekeeper, and unsigned apps won't run at all on macOS 15+. A self-signed
# code-signing identity (created once via scripts/make_signing_identity.sh)
# gives a valid signature: Gatekeeper shows the standard "unidentified
# developer" prompt, which right-click -> Open accepts.
codesign --force --deep --sign "macdraw-local-signing" build/macdraw.app || codesign --force --deep --sign - build/macdraw.app
codesign --verify --deep --strict build/macdraw.app && echo "signature OK"

echo "== packaging =="
rm -rf dist build/staging
mkdir -p dist build/staging

rsync -a build/macdraw.app build/staging/
ln -s /Applications build/staging/Applications
cp "Resources/How to open macdraw.rtf" build/staging/

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
