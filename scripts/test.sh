#!/bin/sh
# Runs the core package tests and the app tests in the simulator.
# Usage: scripts/test.sh [core|app]   (default: both)
set -eu
cd "$(dirname "$0")/.."
# Optional wrapper for long commands (e.g. a resource limiter); empty by default.
SPARSAM="${CARBSTOCK_WRAPPER:-}"
DEST="${CARBSTOCK_DEST:-platform=iOS Simulator,name=CarbStock iPhone}"
what="${1:-all}"
if [ "$what" = all ] || [ "$what" = core ]; then
  (cd Packages/CarbStockCore && $SPARSAM swift test)
fi
if [ "$what" = all ] || [ "$what" = app ]; then
  xcodegen generate --quiet
  $SPARSAM xcodebuild test -project CarbStock.xcodeproj -scheme CarbStock \
    -destination "$DEST" -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO CARBSTOCK_CLOUDKIT=NO -quiet
  python3 -I scripts/pruefe-app-icon.py build/DerivedData/Build/Products/Debug-iphonesimulator/CarbStock.app
fi
