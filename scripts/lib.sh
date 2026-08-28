#!/usr/bin/env bash
# scripts/lib.sh — shared configuration and helpers for the build scripts.
# Sourced, never executed directly.

PROJECT="Tract.xcodeproj"
SCHEME="Tract"
APP_NAME="Tract"
BUILD_DIR="build"

step()    { printf "\n\033[1;36m▸ %s\033[0m\n" "$*"; }
fail()    { printf "\n\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }
succeed() { printf "\n\033[1;32m✓ %s\033[0m\n" "$*"; }

require_xcodegen() {
  command -v xcodegen >/dev/null || fail "xcodegen not installed — run: brew install xcodegen"
}

# The .xcodeproj is gitignored and rebuilt from project.yml, so every build
# regenerates it rather than trusting whatever is on disk.
regenerate_project() {
  [ -f Local.xcconfig ] || fail "Local.xcconfig missing — copy Local.xcconfig.example and set BUNDLE_PREFIX and DEVELOPMENT_TEAM."
  step "Regenerating $PROJECT from project.yml"
  xcodegen generate --quiet
}

# xcodebuild is verbose even with -quiet; keep only diagnostics and the result
# line. Preserves xcodebuild's exit status because callers run under pipefail.
build_log_filter() {
  if command -v xcbeautify >/dev/null; then
    xcbeautify
  else
    grep -E "(error|warning):|^\*\* [A-Z]" || true
  fi
}

# Bundle id is derived, not hardcoded, so it stays in sync with Local.xcconfig.
bundle_identifier() {
  local bundle_prefix
  bundle_prefix="$(sed -n 's/^[[:space:]]*BUNDLE_PREFIX[[:space:]]*=[[:space:]]*//p' Local.xcconfig | tr -d '[:space:]')"
  [ -n "$bundle_prefix" ] || fail "BUNDLE_PREFIX not set in Local.xcconfig."
  printf '%s.app' "$bundle_prefix"
}

# UDID of the first connected (not merely paired) device, empty if none.
first_connected_device_udid() {
  local device_json="$BUILD_DIR/devices.json"
  mkdir -p "$BUILD_DIR"
  xcrun devicectl list devices --json-output "$device_json" >/dev/null 2>&1 || return 0
  python3 - "$device_json" <<'PY'
import json, sys
with open(sys.argv[1]) as device_file:
    devices = json.load(device_file)["result"]["devices"]
for device in devices:
    if device.get("connectionProperties", {}).get("tunnelState") != "unavailable":
        print(device["hardwareProperties"]["udid"])
        break
PY
}
