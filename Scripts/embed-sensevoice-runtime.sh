#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH/Contents" ]]; then
  echo "Usage: Scripts/embed-sensevoice-runtime.sh /path/to/Shuo.app" >&2
  exit 2
fi

RUNTIME_PATH="$("$ROOT_DIR/Scripts/prepare-sensevoice-runtime.sh")"
RUNTIME_DIRECTORY="$APP_PATH/Contents/Resources/Runtime"

mkdir -p "$RUNTIME_DIRECTORY"
cp "$RUNTIME_PATH" "$RUNTIME_DIRECTORY/sensevoice-cli"
chmod 755 "$RUNTIME_DIRECTORY/sensevoice-cli"
cp "$(dirname "$RUNTIME_PATH")/version.txt" \
  "$RUNTIME_DIRECTORY/sensevoice-runtime-provenance.txt"

echo "Embedded SenseVoice runtime: $RUNTIME_DIRECTORY/sensevoice-cli"
