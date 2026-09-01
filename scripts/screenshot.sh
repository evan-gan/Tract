#!/usr/bin/env bash
# scripts/screenshot.sh — captures a screen on an iPad simulator in light and/or
# dark appearance. This is how a UI change gets checked without opening Xcode.
#
#   ./scripts/screenshot.sh                          # canvas, both appearances
#   ./scripts/screenshot.sh dark                     # canvas, just dark
#   ./scripts/screenshot.sh both "" library          # document library
#   ./scripts/screenshot.sh light "" exportmenu      # Export dropdown, open
#   ./scripts/screenshot.sh light "" problempicker   # problem wheel, with a tree in it
#   ./scripts/screenshot.sh both "iPad Air 13-inch (M3)"
#
# PNGs land in build/screenshots/<screen>-<appearance>.png. The captures live in
# UITests/CanvasSnapshotUITests.swift; this script only sets the appearance, runs
# the right one, and digs the attachment out of the result bundle.
#
# Leaves the simulator in the last appearance it captured.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

case "${1:-both}" in
  light) APPEARANCES=(light) ;;
  dark)  APPEARANCES=(dark) ;;
  both)  APPEARANCES=(light dark) ;;
  *)     fail "Unknown appearance '${1}' — use light, dark, or both." ;;
esac

SIMULATOR_NAME="${2:-}"
[ -z "$SIMULATOR_NAME" ] && SIMULATOR_NAME="iPad Pro 11-inch (M5)"

# Each screen is one test method that ends by attaching a screenshot under the
# screen's own name — that name is how the attachment is found again below.
SCREEN="${3:-canvas}"
case "$SCREEN" in
  canvas)  TEST_METHOD=testCaptureCanvas ;;
  library) TEST_METHOD=testCaptureLibrary ;;
  exportmenu) TEST_METHOD=testCaptureExportMenu ;;
  problempicker) TEST_METHOD=testCaptureProblemPicker ;;
  *)       fail "Unknown screen '${SCREEN}' — use canvas, library, exportmenu or problempicker." ;;
esac

SNAPSHOT_TEST="TractUITests/CanvasSnapshotUITests/$TEST_METHOD"
OUTPUT_DIR="$BUILD_DIR/screenshots"

require_xcodegen
regenerate_project

UDID="$(simulator_udid "$SIMULATOR_NAME")"
boot_simulator "$UDID"
mkdir -p "$OUTPUT_DIR"

# Runs the capture test once and leaves the PNG at $OUTPUT_DIR/$SCREEN-<appearance>.png.
capture_appearance() {
  local appearance="$1"
  local result_bundle="$OUTPUT_DIR/$SCREEN-$appearance.xcresult"
  local attachment_dir="$OUTPUT_DIR/$SCREEN-$appearance-attachments"

  step "Capturing $appearance appearance on $SIMULATOR_NAME"
  xcrun simctl ui "$UDID" appearance "$appearance"
  rm -rf "$result_bundle" "$attachment_dir"

  set -o pipefail
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "id=$UDID" \
    -derivedDataPath "$BUILD_DIR/screenshots-build" \
    -only-testing:"$SNAPSHOT_TEST" \
    -resultBundlePath "$result_bundle" \
    -quiet 2>&1 | build_log_filter

  xcrun xcresulttool export attachments \
    --path "$result_bundle" --output-path "$attachment_dir" >/dev/null
  extract_screenshot "$attachment_dir" "$OUTPUT_DIR/$SCREEN-$appearance.png"
}

# Attachments are exported under UUID filenames; the manifest is what maps them
# back to the name the test gave them.
extract_screenshot() {
  local attachment_dir="$1" destination="$2"
  python3 - "$attachment_dir" "$destination" "$SCREEN" <<'PY'
import json, shutil, sys
from pathlib import Path

attachment_dir, destination, screen = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
manifest = json.loads((attachment_dir / "manifest.json").read_text())
for test in manifest:
    for attachment in test["attachments"]:
        # Xcode appends an index and a UUID to the name the test gave it.
        if attachment["suggestedHumanReadableName"].startswith(screen):
            shutil.copyfile(attachment_dir / attachment["exportedFileName"], destination)
            sys.exit(0)
sys.exit(f"No '{screen}' screenshot in {attachment_dir} — did the capture test run?")
PY
}

for appearance in "${APPEARANCES[@]}"; do
  capture_appearance "$appearance"
done

succeed "Screenshots written to $OUTPUT_DIR/"
for appearance in "${APPEARANCES[@]}"; do
  printf '  %s\n' "$OUTPUT_DIR/$SCREEN-$appearance.png"
done
