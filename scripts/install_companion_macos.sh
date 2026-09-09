#!/bin/zsh
set -euo pipefail

PLUGIN_SOURCE="${0:A:h:h}"
DEFAULT_DATA_DIR="$(python3 -c 'from pathlib import Path; d=Path.home()/".codex"/"plugins"/"data"; p=d/"donebara-personal"; old=d/"doneguard-personal"; print(p if p.exists() else old if old.exists() else Path.home()/".codex"/"doneguard-data")')"
DATA_DIR="${PLUGIN_DATA:-${DONEBARA_DATA:-${DONEGUARD_DATA:-$DEFAULT_DATA_DIR}}}"

if [[ "${1:-}" == "--data-dir" ]]; then
  if [[ -z "${2:-}" ]]; then
    print -u2 "--data-dir requires a path"
    exit 2
  fi
  DATA_DIR="$2"
fi

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_NAME="Donebara Companion.app"
APP_PATH="$STAGING_DIR/$APP_NAME"
TARGET_PATH="$DATA_DIR/$APP_NAME"

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$DATA_DIR"
swiftc -parse-as-library \
  "$PLUGIN_SOURCE/companion/Sources/DonebaraCompanion.swift" \
  -framework AppKit -framework SwiftUI \
  -o "$APP_PATH/Contents/MacOS/DonebaraCompanion"
cp "$PLUGIN_SOURCE/companion/Support/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PLUGIN_SOURCE/companion/Assets/mascot-success.png" "$APP_PATH/Contents/Resources/mascot-success.png"
cp "$PLUGIN_SOURCE/companion/Assets/mascot-issue.png" "$APP_PATH/Contents/Resources/mascot-issue.png"
cp "$PLUGIN_SOURCE/scripts/donebara_followup.py" "$APP_PATH/Contents/Resources/donebara_followup.py"

pkill -x DonebaraCompanion 2>/dev/null || true

if [[ -e "$TARGET_PATH" ]]; then
  BACKUP_DIR="$(mktemp -d "$DATA_DIR/companion-backup.XXXXXX")"
  mv "$TARGET_PATH" "$BACKUP_DIR/$APP_NAME"
fi
mv "$APP_PATH" "$TARGET_PATH"
print "$TARGET_PATH"
