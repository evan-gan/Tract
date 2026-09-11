#!/usr/bin/env bash
# Runs the unit test suite on an iPad simulator. Pass a simulator name to
# override the default, e.g. ./scripts/test.sh "iPad Air 11-inch (M3)".
#
# Two environment knobs, both about run time rather than coverage:
#   TEST_WORKERS=N        simulator clones to run test classes across (default 4)
#   TEST_SNAPSHOTS=1      also run CanvasSnapshotUITests, normally skipped
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

SIMULATOR_NAME="${1:-iPad Pro 11-inch (M5)}"

# XCTest relaunches the app for every test method, so the 39 UI tests spend
# roughly 250s of their 530s just launching. Cloning the simulator and running
# test classes side by side is the only win available without deleting tests.
# Kept low on purpose: at four workers the clones contend hard enough that each
# test's own duration roughly doubles, cancelling most of the parallel win.
TEST_WORKERS="${TEST_WORKERS:-2}"

# CanvasSnapshotUITests only navigates and calls attachScreenshot — it asserts
# nothing a real test doesn't, and cost 101s of a 577s suite. screenshot.sh runs
# it on demand, which is the only time the pictures are actually wanted.
# The target name matters: xcodebuild silently ignores an identifier it cannot
# match, so this must stay in sync with the target name in project.yml.
SKIP_ARGS=(-skip-testing:TractUITests/CanvasSnapshotUITests)
if [ -n "${TEST_SNAPSHOTS:-}" ]; then
  SKIP_ARGS=()
fi

require_xcodegen
regenerate_project

step "Testing $SCHEME on $SIMULATOR_NAME ($TEST_WORKERS workers)"
set -o pipefail
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
  -derivedDataPath "$BUILD_DIR/tests" \
  -parallel-testing-enabled YES \
  -parallel-testing-worker-count "$TEST_WORKERS" \
  "${SKIP_ARGS[@]}" \
  -quiet 2>&1 | build_log_filter

succeed "Tests passed."
