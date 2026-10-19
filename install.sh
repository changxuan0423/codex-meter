#!/bin/bash
# Installs the published Codex Meter binary; no compiler, sudo or API key needed.
set -euo pipefail

fail() { printf 'Codex Meter: %s\n' "$*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail 'This app requires macOS 13 or later.'
MACOS_MAJOR="$(sw_vers -productVersion | cut -d . -f 1)"
[ "$MACOS_MAJOR" -ge 13 ] || fail 'This app requires macOS 13 or later.'
case "$(uname -m)" in arm64|x86_64) ;; *) fail 'Unsupported Mac architecture.' ;; esac

REPOSITORY='changxuan0423/codex-meter'
VERSION="${CODEX_METER_VERSION:-latest}"
if [ "$VERSION" = latest ]; then
  BASE_URL="https://raw.githubusercontent.com/$REPOSITORY/main/dist"
else
  case "$VERSION" in v[0-9]*) ;; *) fail 'CODEX_METER_VERSION must be a tag such as v1.0.5.' ;; esac
  BASE_URL="https://raw.githubusercontent.com/$REPOSITORY/$VERSION/dist"
fi
ARCHIVE='CodexMeter-macos-universal.zip'
INSTALL_DIR="${CODEX_METER_INSTALL_DIR:-$HOME/Applications}"
APP_DIR="$INSTALL_DIR/Codex Meter.app"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-meter-install.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

printf 'Downloading Codex Meter (%s)…\n' "$VERSION"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  --retry 3 --connect-timeout 15 --max-time 180 "$BASE_URL/$ARCHIVE" -o "$WORK_DIR/$ARCHIVE"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  --retry 3 --connect-timeout 15 --max-time 60 "$BASE_URL/SHA256SUMS" -o "$WORK_DIR/SHA256SUMS"
EXPECTED="$(awk -v filename="$ARCHIVE" '$2 == filename { print $1 }' "$WORK_DIR/SHA256SUMS")"
[[ "$EXPECTED" =~ ^[[:xdigit:]]{64}$ ]] || fail 'Release checksum is missing or invalid.'
ACTUAL="$(shasum -a 256 "$WORK_DIR/$ARCHIVE" | awk '{ print $1 }')"
[ "$ACTUAL" = "$EXPECTED" ] || fail 'Checksum mismatch. Installation stopped.'

ditto -x -k "$WORK_DIR/$ARCHIVE" "$WORK_DIR/unpacked"
SOURCE_APP="$WORK_DIR/unpacked/Codex Meter.app"
[ -x "$SOURCE_APP/Contents/MacOS/CodexMeter" ] || fail 'The downloaded application is incomplete.'
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")"
[ "$IDENTIFIER" = local.xavier.CodexMeter ] || fail 'Unexpected application identifier.'
codesign --verify --strict "$SOURCE_APP" || fail 'The application signature is invalid.'

mkdir -p "$INSTALL_DIR"
if [ -e "$APP_DIR" ]; then
  PREVIOUS_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist" 2>/dev/null || true)"
  [ "$PREVIOUS_ID" = "$IDENTIFIER" ] || fail "Another application already occupies $APP_DIR."
  if [ "${CODEX_METER_SKIP_LAUNCH:-0}" != 1 ]; then
    if pgrep -x CodexMeter >/dev/null; then killall CodexMeter; fi
  fi
fi
ditto "$SOURCE_APP" "$APP_DIR"
codesign --verify --strict "$APP_DIR" || fail 'Installed application verification failed.'
printf 'Installed: %s\n' "$APP_DIR"
if [ "${CODEX_METER_SKIP_LAUNCH:-0}" != 1 ]; then
  open "$APP_DIR"
  printf 'Codex Meter is now in your menu bar.\n'
fi
