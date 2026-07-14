#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH/Contents" ]]; then
  echo "Usage: Scripts/embed-whisper-runtime.sh /path/to/Shuo.app" >&2
  exit 2
fi

RUNTIME_PATH="$("$ROOT_DIR/Scripts/prepare-whisper-runtime.sh")"
RUNTIME_DIRECTORY="$APP_PATH/Contents/Resources/Runtime"
LICENSE_DIRECTORY="$APP_PATH/Contents/Resources/ThirdParty"

mkdir -p "$RUNTIME_DIRECTORY" "$LICENSE_DIRECTORY"
cp "$RUNTIME_PATH" "$RUNTIME_DIRECTORY/whisper-cli"
chmod 755 "$RUNTIME_DIRECTORY/whisper-cli"
cp "$(dirname "$RUNTIME_PATH")/whisper.cpp-LICENSE" \
  "$LICENSE_DIRECTORY/whisper.cpp-LICENSE"
cp "$(dirname "$RUNTIME_PATH")/version.txt" \
  "$RUNTIME_DIRECTORY/whisper-runtime-provenance.txt"

echo "Embedded whisper.cpp runtime: $RUNTIME_DIRECTORY/whisper-cli"
