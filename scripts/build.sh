#!/usr/bin/env bash
# scripts/build.sh — fast headless type-check / compile of the Tract iPad app.
#
# Regenerates the Xcode project from project.yml, then compiles unsigned for a
# generic iOS device. This is the inner loop: no signing, no simulator, no GUI.
#
# Usage: ./scripts/build.sh [clean]

set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

DESTINATION="${TRACT_DESTINATION:-generic/platform=iOS}"

[ "${1:-}" = "clean" ] && { step "Cleaning $BUILD_DIR"; rm -rf "$BUILD_DIR"; }

require_xcodegen
regenerate_project

step "Building $SCHEME (Debug, unsigned) for $DESTINATION"
# CODE_SIGNING_ALLOWED=NO skips signing entirely: this build type-checks and
# links, but can't be installed anywhere — use deploy-device.sh for that.
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination "$DESTINATION" \
  -derivedDataPath "$BUILD_DIR/derived" \
  -quiet CODE_SIGNING_ALLOWED=NO build \
  | build_log_filter

succeed "Build succeeded."
