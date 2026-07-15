#!/usr/bin/env bash
set -euo pipefail

# Build the official FunAudioLLM SenseVoice llama.cpp runtime as a deterministic,
# universal macOS executable. The ASR model itself is deliberately not bundled:
# Shuo downloads it into the user's local model store on demand.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_VERSION="${SHUO_SENSEVOICE_RUNTIME_VERSION:-0.1.4}"
# v0.1.4's runtime tree is identical at this follow-up commit, which supplies
# the canonical MIT license text absent from the release-tag archive.
SOURCE_COMMIT="${SHUO_SENSEVOICE_RUNTIME_COMMIT:-7e41210ed16d97de8a21b5fec764e0cc287c1d40}"
SOURCE_SHA256="${SHUO_SENSEVOICE_RUNTIME_SOURCE_SHA256:-9c67454515426253a0fb9bbe4f1bd1b836066b3396e2ea8ea1a4a1b3c0d506af}"
LLAMA_CPP_COMMIT="${SHUO_SENSEVOICE_LLAMA_CPP_COMMIT:-8086439a4cea94c71a5dfb8fe4ad1546aebd640f}"
LLAMA_CPP_SOURCE_SHA256="${SHUO_SENSEVOICE_LLAMA_CPP_SOURCE_SHA256:-1984103666eb25bd45110a40cba22b9d4286116f26e51bbc76f6f41dc86bc7b5}"
SEGMENT_DELIMITER_PATCH="$ROOT_DIR/Scripts/patches/sensevoice-segment-delimiters.patch"
SEGMENT_DELIMITER_PATCH_SHA256="${SHUO_SENSEVOICE_SEGMENT_DELIMITER_PATCH_SHA256:-16b5a7420bfb79fe4d6a4564adf2bae8552735413f46fd80d2e2f234063e955a}"
CACHE_ROOT="${SHUO_SENSEVOICE_RUNTIME_CACHE:-$ROOT_DIR/DerivedData/SenseVoiceRuntime}"
SOURCE_DIR="$CACHE_ROOT/source-$SOURCE_COMMIT"
LLAMA_SOURCE_DIR="$CACHE_ROOT/llama.cpp-$LLAMA_CPP_COMMIT"
BUILD_DIR="$CACHE_ROOT/build-$SOURCE_COMMIT"
SOURCE_ARCHIVE="$CACHE_ROOT/SenseVoice-$SOURCE_COMMIT.tar.gz"
LLAMA_SOURCE_ARCHIVE="$CACHE_ROOT/llama.cpp-$LLAMA_CPP_COMMIT.tar.gz"
OUTPUT_PATH="$CACHE_ROOT/sensevoice-cli"
ARCHITECTURES="${SHUO_SENSEVOICE_ARCHITECTURES:-arm64;x86_64}"

for command in cmake curl grep patch shasum tar; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing build dependency: $command" >&2
    echo "Install CMake on the release Mac before preparing the bundled SenseVoice runtime." >&2
    exit 2
  fi
done

[[ -f "$SEGMENT_DELIMITER_PATCH" ]] || {
  echo "Missing required SenseVoice segment-delimiter patch: $SEGMENT_DELIMITER_PATCH" >&2
  exit 2
}
ACTUAL_SEGMENT_DELIMITER_PATCH_SHA256="$(shasum -a 256 "$SEGMENT_DELIMITER_PATCH" | awk '{print $1}')"
if [[ "$ACTUAL_SEGMENT_DELIMITER_PATCH_SHA256" != "$SEGMENT_DELIMITER_PATCH_SHA256" ]]; then
  echo "SenseVoice segment-delimiter patch checksum mismatch." >&2
  exit 3
fi

SCRIPT_SHA256="$(shasum -a 256 "$0" | awk '{print $1}')"
CMAKE_IDENTITY="$(cmake --version | sed -n '1p')"
CACHE_FINGERPRINT="$RUNTIME_VERSION:$SOURCE_COMMIT:$SOURCE_SHA256:$LLAMA_CPP_COMMIT:$LLAMA_CPP_SOURCE_SHA256:$ARCHITECTURES:$SEGMENT_DELIMITER_PATCH_SHA256:$SCRIPT_SHA256:$CMAKE_IDENTITY"

if [[ -x "$OUTPUT_PATH" ]] && [[ -f "$CACHE_ROOT/version.txt" ]] \
  && [[ "$(cat "$CACHE_ROOT/version.txt")" == "$CACHE_FINGERPRINT" ]]; then
  echo "$OUTPUT_PATH"
  exit 0
fi

mkdir -p "$CACHE_ROOT"

download_and_verify() {
  local url="$1"
  local archive="$2"
  local expected_sha256="$3"
  local label="$4"
  local actual_sha256

  if [[ ! -f "$archive" ]]; then
    echo "Downloading $label source..." >&2
    curl --location --fail --silent --show-error "$url" --output "$archive"
  fi

  actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "$label source checksum mismatch." >&2
    rm -f "$archive"
    exit 3
  fi
}

download_and_verify \
  "https://github.com/FunAudioLLM/SenseVoice/archive/$SOURCE_COMMIT.tar.gz" \
  "$SOURCE_ARCHIVE" \
  "$SOURCE_SHA256" \
  "SenseVoice"
download_and_verify \
  "https://github.com/ggml-org/llama.cpp/archive/$LLAMA_CPP_COMMIT.tar.gz" \
  "$LLAMA_SOURCE_ARCHIVE" \
  "$LLAMA_CPP_SOURCE_SHA256" \
  "llama.cpp"

rm -rf "$SOURCE_DIR" "$LLAMA_SOURCE_DIR" "$BUILD_DIR"
mkdir -p "$SOURCE_DIR" "$LLAMA_SOURCE_DIR"
tar -xzf "$SOURCE_ARCHIVE" -C "$SOURCE_DIR" --strip-components=1
tar -xzf "$LLAMA_SOURCE_ARCHIVE" -C "$LLAMA_SOURCE_DIR" --strip-components=1

if ! patch --batch --forward -p1 -d "$SOURCE_DIR" < "$SEGMENT_DELIMITER_PATCH" >/dev/null; then
  echo "Could not apply the reviewed SenseVoice segment-delimiter patch." >&2
  exit 4
fi

RUNTIME_CMAKE="$SOURCE_DIR/runtime/llama.cpp/CMakeLists.txt"
if [[ ! -f "$RUNTIME_CMAKE" ]]; then
  echo "Pinned SenseVoice source does not contain runtime/llama.cpp." >&2
  exit 4
fi
if ! grep -Fq "$LLAMA_CPP_COMMIT" "$RUNTIME_CMAKE"; then
  echo "Pinned SenseVoice runtime does not declare the expected llama.cpp revision." >&2
  exit 4
fi

echo "Building the bundled SenseVoice runtime for $ARCHITECTURES..." >&2
# stdout is a machine-readable contract consumed by embed-sensevoice-runtime.sh:
# it must contain only the final executable path, even on a fresh cache build.
{
  cmake \
    -S "$SOURCE_DIR/runtime/llama.cpp" \
    -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_OSX_ARCHITECTURES="$ARCHITECTURES" \
    -DFETCHCONTENT_SOURCE_DIR_LLAMA="$LLAMA_SOURCE_DIR" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_NATIVE=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON
  cmake --build "$BUILD_DIR" --config Release --target llama-funasr-sensevoice --parallel
} >&2

BUILT_EXECUTABLE="$BUILD_DIR/bin/llama-funasr-sensevoice"
if [[ ! -x "$BUILT_EXECUTABLE" ]]; then
  echo "The SenseVoice runtime build completed without producing llama-funasr-sensevoice." >&2
  exit 4
fi

cp "$BUILT_EXECUTABLE" "$OUTPUT_PATH"
chmod 755 "$OUTPUT_PATH"
printf '%s' "$CACHE_FINGERPRINT" > "$CACHE_ROOT/version.txt"

echo "$OUTPUT_PATH"
