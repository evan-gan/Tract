#!/usr/bin/env bash
# scripts/screenshot.sh — captures the canvas on an iPad simulator in light and/or
# dark appearance. This is how a UI change gets checked without opening Xcode.
#
#   ./scripts/screenshot.sh                 # both appearances
#   ./scripts/screenshot.sh dark            # just dark
#   ./scripts/screenshot.sh both "iPad Air 13-inch (M3)"
#
# PNGs land in build/screenshots/canvas-<appearance>.png. The capture itself lives
# in UITests/CanvasSnapshotUITests.swift; this script only sets the appearance,
# runs it, and digs the attachment out of the result bundle.
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

SIMULATOR_NAME="${2:-iPad Pro 11-inch (M5)}"
SNAPSHOT_TEST="TractUITests/CanvasSnapshotUITests"
OUTPUT_DIR="$BUILD_DIR/screenshots"

require_xcodegen
regenerate_project

UDID="$(simulator_udid "$SIMULATOR_NAME")"
boot_simulator "$UDID"
mkdir -p "$OUTPUT_DIR"

# Runs the capture test once and leaves the PNG at $OUTPUT_DIR/canvas-<appearance>.png.
capture_appearance() {
  local appearance="$1"
  local result_bundle="$OUTPUT_DIR/$appearance.xcresult"
  local attachment_dir="$OUTPUT_DIR/$appearance-attachments"

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
  extract_screenshot "$attachment_dir" "$OUTPUT_DIR/canvas-$appearance.png"
}

# Attachments are exported under UUID filenames; the manifest is what maps them
# back to the name the test gave them.
extract_screenshot() {
  local attachment_dir="$1" destination="$2"
  python3 - "$attachment_dir" "$destination" <<'PY'
import json, shutil, sys
from pathlib import Path

attachment_dir, destination = Path(sys.argv[1]), Path(sys.argv[2])
manifest = json.loads((attachment_dir / "manifest.json").read_text())
for test in manifest:
    for attachment in test["attachments"]:
        if attachment["suggestedHumanReadableName"].startswith("canvas"):
            shutil.copyfile(attachment_dir / attachment["exportedFileName"], destination)
            sys.exit(0)
sys.exit(f"No canvas screenshot in {attachment_dir} — did the capture test run?")
PY
}

for appearance in "${APPEARANCES[@]}"; do
  capture_appearance "$appearance"
done

succeed "Screenshots written to $OUTPUT_DIR/"
for appearance in "${APPEARANCES[@]}"; do
  printf '  %s\n' "$OUTPUT_DIR/canvas-$appearance.png"
done
