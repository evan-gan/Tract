#!/usr/bin/env bash
# scripts/deploy-device.sh — build a signed Tract build and install it on a
# connected iPad, entirely from the shell.
#
# iOS apps aren't notarized (that's a Mac-distribution step); device installs
# need the Apple Development identity plus a provisioning profile, which
# -allowProvisioningUpdates fetches automatically.
#
# Requires (one-time): Xcode signed into your Apple ID with a paid Developer
# Program membership, and the iPad paired and unlocked.
#
# Usage: ./scripts/deploy-device.sh [DEVICE-UDID]

set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

ARCHIVE_PATH="$BUILD_DIR/$APP_NAME-iOS.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

require_xcodegen

step "Locating device"
DEVICE_UDID="${1:-${TRACT_DEVICE_UDID:-$(first_connected_device_udid)}}"
[ -n "$DEVICE_UDID" ] || fail "No connected device found. Plug in an iPad, unlock it, and check 'xcrun devicectl list devices'."
printf "  using device %s\n" "$DEVICE_UDID"

regenerate_project

step "Archiving (Release, signed for device)"
rm -rf "$ARCHIVE_PATH"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIR/derived-ios" \
  -archivePath "$ARCHIVE_PATH" \
  -quiet -allowProvisioningUpdates archive \
  | build_log_filter

[ -d "$APP_PATH" ] || fail "Archived app not found at $APP_PATH."

step "Verifying signature"
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|Identifier" || true

step "Installing on device"
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"

succeed "$APP_NAME installed on $DEVICE_UDID."
