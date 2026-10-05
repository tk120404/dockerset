#!/bin/bash
# Builds a universal (Apple silicon + Intel) Dockerset.app and zips it for a GitHub Release.
# Usage: scripts/package-release.sh   →  build/Dockerset-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

# One build per architecture, merged with lipo (multi-arch in one build needs full Xcode).
swift build -c release --triple arm64-apple-macosx15.0
swift build -c release --triple x86_64-apple-macosx15.0

APP=build/Dockerset.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/Dockerset" \
  .build/arm64-apple-macosx/release/Dockerset .build/x86_64-apple-macosx/release/Dockerset
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Same stable designated requirement as build-app.sh, so permissions survive updates.
codesign --force --sign - --identifier local.dockerset.Dockerset \
  --requirements '=designated => identifier "local.dockerset.Dockerset"' "$APP"
codesign --verify --strict "$APP"

ZIP="build/Dockerset-$VERSION.zip"
rm -f "$ZIP"
# ditto keeps the bundle's metadata and signature intact.
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/Dockerset")"
echo "Built $ZIP"
shasum -a 256 "$ZIP"
