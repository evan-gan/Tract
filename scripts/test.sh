#!/usr/bin/env bash
# Runs the unit test suite on an iPad simulator. Pass a simulator name to
# override the default, e.g. ./scripts/test.sh "iPad Air 11-inch (M3)".
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

SIMULATOR_NAME="${1:-iPad Pro 11-inch (M5)}"

require_xcodegen
regenerate_project

step "Testing $SCHEME on $SIMULATOR_NAME"
set -o pipefail
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
  -derivedDataPath "$BUILD_DIR/tests" \
  -quiet 2>&1 | build_log_filter

succeed "Tests passed."
