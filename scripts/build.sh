#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/Codex Meter.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$PROJECT_DIR/build/module-cache" "$PROJECT_DIR/build/bin"
ARCHITECTURES="${CODEX_METER_ARCHS:-$(uname -m)}"
BINARIES=()
for architecture in $ARCHITECTURES; do
  case "$architecture" in
    arm64|x86_64) ;;
    *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 1 ;;
  esac
  binary="$PROJECT_DIR/build/bin/CodexMeter-$architecture"
  xcrun swiftc -swift-version 5 -O -whole-module-optimization \
    -module-cache-path "$PROJECT_DIR/build/module-cache" \
    -target "$architecture-apple-macosx13.0" \
    -framework AppKit -framework SwiftUI -framework ServiceManagement \
    "$PROJECT_DIR/Sources/Quota.swift" "$PROJECT_DIR/Sources/PanelPlacement.swift" "$PROJECT_DIR/Sources/CodexClient.swift" "$PROJECT_DIR/Sources/StatusAppearance.swift" "$PROJECT_DIR/Sources/main.swift" \
    -o "$binary"
  BINARIES+=("$binary")
done
if [ "${#BINARIES[@]}" -eq 1 ]; then
  cp "${BINARIES[0]}" "$APP_DIR/Contents/MacOS/CodexMeter"
else
  xcrun lipo -create "${BINARIES[@]}" -output "$APP_DIR/Contents/MacOS/CodexMeter"
fi
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - --identifier local.xavier.CodexMeter "$APP_DIR"
printf '%s\n' "$APP_DIR"
