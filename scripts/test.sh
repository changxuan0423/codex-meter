#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/build/module-cache"
xcrun swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/build/module-cache" \
  "$PROJECT_DIR/Sources/Quota.swift" "$PROJECT_DIR/Sources/PanelPlacement.swift" "$PROJECT_DIR/Tests/main.swift" \
  -o "$PROJECT_DIR/build/QuotaTests"
"$PROJECT_DIR/build/QuotaTests"
