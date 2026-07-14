#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${SHUO_WHISPER_CPP_VERSION:-1.8.6}"
ARCHIVE_SHA256="${SHUO_WHISPER_CPP_SHA256:-f8e632016ceae556f3132a16c7f704be1e7715595041f474fa81a2b64c1abf7c}"
CACHE_ROOT="${SHUO_WHISPER_RUNTIME_CACHE:-$ROOT_DIR/DerivedData/WhisperRuntime}"
SOURCE_DIR="$CACHE_ROOT/source-$VERSION"
BUILD_DIR="$CACHE_ROOT/build-$VERSION"
ARCHIVE_PATH="$CACHE_ROOT/whisper.cpp-$VERSION.tar.gz"
OUTPUT_PATH="$CACHE_ROOT/whisper-cli"
ARCHITECTURES="${SHUO_WHISPER_ARCHITECTURES:-arm64;x86_64}"

for command in cmake curl shasum tar; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing build dependency: $command" >&2
    echo "Install CMake on the release Mac before preparing the bundled whisper.cpp runtime." >&2
    exit 2
  fi
done

SCRIPT_SHA256="$(shasum -a 256 "$0" | awk '{print $1}')"
CMAKE_IDENTITY="$(cmake --version | sed -n '1p')"
CACHE_FINGERPRINT="$VERSION:$ARCHIVE_SHA256:$ARCHITECTURES:$SCRIPT_SHA256:$CMAKE_IDENTITY"

if [[ -x "$OUTPUT_PATH" ]] && [[ -f "$CACHE_ROOT/version.txt" ]] \
  && [[ "$(cat "$CACHE_ROOT/version.txt")" == "$CACHE_FINGERPRINT" ]]; then
  echo "$OUTPUT_PATH"
  exit 0
fi

mkdir -p "$CACHE_ROOT"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "Downloading whisper.cpp v$VERSION source..." >&2
  curl --location --fail --silent --show-error \
    "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v$VERSION.tar.gz" \
    --output "$ARCHIVE_PATH"
fi

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$ARCHIVE_SHA256" ]]; then
  echo "whisper.cpp source checksum mismatch." >&2
  rm -f "$ARCHIVE_PATH"
  exit 3
fi

rm -rf "$SOURCE_DIR" "$BUILD_DIR"
mkdir -p "$SOURCE_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$SOURCE_DIR" --strip-components=1

echo "Building the bundled whisper.cpp runtime for $ARCHITECTURES..." >&2
# stdout is a machine-readable contract consumed by embed-whisper-runtime.sh:
# it must contain only the final executable path, even on a fresh cache build.
{
  cmake \
    -S "$SOURCE_DIR" \
    -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_OSX_ARCHITECTURES="$ARCHITECTURES" \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DWHISPER_SDL2=OFF \
    -DGGML_NATIVE=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON
  cmake --build "$BUILD_DIR" --config Release --target whisper-cli --parallel
} >&2

BUILT_EXECUTABLE="$BUILD_DIR/bin/whisper-cli"
if [[ ! -x "$BUILT_EXECUTABLE" ]]; then
  echo "The whisper.cpp build completed without producing whisper-cli." >&2
  exit 4
fi

cp "$BUILT_EXECUTABLE" "$OUTPUT_PATH"
chmod 755 "$OUTPUT_PATH"
printf '%s' "$CACHE_FINGERPRINT" > "$CACHE_ROOT/version.txt"
cp "$SOURCE_DIR/LICENSE" "$CACHE_ROOT/whisper.cpp-LICENSE"

echo "$OUTPUT_PATH"
