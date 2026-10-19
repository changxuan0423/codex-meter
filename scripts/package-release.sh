#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CODEX_METER_ARCHS="arm64 x86_64" bash "$PROJECT_DIR/scripts/build.sh"
APP_DIR="$PROJECT_DIR/build/Codex Meter.app"
RELEASE_DIR="$PROJECT_DIR/build/release"
mkdir -p "$RELEASE_DIR"
codesign --verify --strict "$APP_DIR"
RELEASE_ARCHS=" $(xcrun lipo -archs "$APP_DIR/Contents/MacOS/CodexMeter") "
case "$RELEASE_ARCHS" in *' arm64 '*) ;; *) printf '%s\n' 'Missing arm64 release slice' >&2; exit 1 ;; esac
case "$RELEASE_ARCHS" in *' x86_64 '*) ;; *) printf '%s\n' 'Missing x86_64 release slice' >&2; exit 1 ;; esac
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$RELEASE_DIR/CodexMeter-macos-universal.zip"
(
  cd "$RELEASE_DIR"
  shasum -a 256 CodexMeter-macos-universal.zip > SHA256SUMS
)
printf '%s\n' "$RELEASE_DIR/CodexMeter-macos-universal.zip" "$RELEASE_DIR/SHA256SUMS"
