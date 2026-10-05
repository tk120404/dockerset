#!/bin/bash
# Builds Dockerset.app into ./build. Usage: scripts/build-app.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Dockerset.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Dockerset "$APP/Contents/MacOS/Dockerset"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signatures are identified by a hash of each build, so macOS would forget Accessibility and other
# permissions on every rebuild. A designated requirement on the bundle ID keeps them across rebuilds.
codesign --force --sign - --identifier local.dockerset.Dockerset \
  --requirements '=designated => identifier "local.dockerset.Dockerset"' "$APP"

echo "Built $APP"
if [[ "${1:-}" == "--run" ]]; then
  pkill -x Dockerset || true
  open "$APP"
fi
