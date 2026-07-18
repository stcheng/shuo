#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"
ZIP_PATH="${2:-}"
DMG_PATH="${3:-}"
CHECKSUM_PATH="${4:-}"
MANIFEST_PATH="${5:-}"
SYMBOLS_PATH="${6:-}"
EXPECTED_TEAM_ID="4GQ47468NJ"
EXPECTED_BUNDLE_ID="dev.shuotian.Shuo"
EXPECTED_FEED_URL="https://stcheng.github.io/shuo/appcast.xml"
EXPECTED_SPARKLE_PUBLIC_KEY="i0Hw/eZpvDeme6HTBGedmDhGfLECOXuTZ1q6urwyZyg="
EXPECTED_SOURCE_REPOSITORY="https://github.com/stcheng/shuo.git"
EXPECTED_SOURCE_WEB="https://github.com/stcheng/shuo"
EXPECTED_SPARKLE_REPOSITORY="https://github.com/sparkle-project/Sparkle"
EXPECTED_SPARKLE_VERSION="2.9.4"
EXPECTED_SPARKLE_REVISION="b6496a74a087257ef5e6da1c5b29a447a60f5bd7"
EXPECTED_WHISPER_CPP_VERSION="1.8.6"
EXPECTED_WHISPER_CPP_SHA256="f8e632016ceae556f3132a16c7f704be1e7715595041f474fa81a2b64c1abf7c"
EXPECTED_SENSEVOICE_RUNTIME_VERSION="0.1.4"
EXPECTED_SENSEVOICE_RUNTIME_COMMIT="7e41210ed16d97de8a21b5fec764e0cc287c1d40"
EXPECTED_SENSEVOICE_RUNTIME_SOURCE_SHA256="9c67454515426253a0fb9bbe4f1bd1b836066b3396e2ea8ea1a4a1b3c0d506af"
EXPECTED_SENSEVOICE_LLAMA_CPP_COMMIT="8086439a4cea94c71a5dfb8fe4ad1546aebd640f"
EXPECTED_SENSEVOICE_LLAMA_CPP_SOURCE_SHA256="1984103666eb25bd45110a40cba22b9d4286116f26e51bbc76f6f41dc86bc7b5"
EXPECTED_SENSEVOICE_SEGMENT_DELIMITER_PATCH_SHA256="16b5a7420bfb79fe4d6a4564adf2bae8552735413f46fd80d2e2f234063e955a"

usage() {
  cat <<'EOF'
Usage: Scripts/verify-release-artifacts.sh APP_PATH ZIP_PATH DMG_PATH CHECKSUM_PATH MANIFEST_PATH SYMBOLS_PATH
       Scripts/verify-release-artifacts.sh --update-archive ZIP_PATH CHECKSUM_PATH MANIFEST_PATH

Verifies the final Developer ID-signed and notarized release artifacts. This
script intentionally has no switch for skipping notarization or Gatekeeper
checks; it is the final fail-closed gate used by the RC packaging command. The
update-archive mode binds an appcast ZIP to the exact verified RC manifest and
checksum without requiring the DMG or private dSYM to be present.
EOF
}

fail() {
  echo "Release verification failed: $*" >&2
  exit 1
}

verify_corresponding_source() {
  local app_path="$1"
  local manifest_path="$2"
  local version="$3"
  local resources="$app_path/Contents/Resources"
  local notice="$resources/CORRESPONDING_SOURCE.txt"
  local source_sha source_tag source_repository manifest_tag

  source_sha="$(jq -r '.source.git_sha // empty' "$manifest_path")"
  [[ "$source_sha" =~ ^[0-9a-fA-F]{40,64}$ ]] \
    || fail "release manifest is missing a valid source Git SHA"
  source_tag="v$version"
  source_repository="$(jq -r '.source.repository // empty' "$manifest_path")"
  manifest_tag="$(jq -r '.source.tag // empty' "$manifest_path")"

  [[ -s "$notice" ]] || fail "app is missing CORRESPONDING_SOURCE.txt"
  cmp -s "$ROOT_DIR/LICENSE" "$resources/LICENSE" \
    || fail "bundled GPL license differs from the repository LICENSE"
  grep -Fxq "Release tag: $source_tag" "$notice" \
    || fail "corresponding-source notice does not name release tag $source_tag"
  [[ "$source_repository" == "$EXPECTED_SOURCE_REPOSITORY" ]] \
    || fail "release manifest has the wrong source repository"
  [[ "$manifest_tag" == "$source_tag" ]] \
    || fail "release manifest source tag does not match $source_tag"
  grep -Fxq "Tagged source: $EXPECTED_SOURCE_WEB/tree/$source_tag" "$notice" \
    || fail "corresponding-source notice has the wrong tag URL"
  grep -Fxq "Source archive: $EXPECTED_SOURCE_WEB/archive/refs/tags/$source_tag.tar.gz" "$notice" \
    || fail "corresponding-source notice has the wrong source archive URL"
  grep -Fxq "Source commit: $source_sha" "$notice" \
    || fail "corresponding-source notice does not match the manifest commit"
  grep -Fxq "Exact source: $EXPECTED_SOURCE_WEB/tree/$source_sha" "$notice" \
    || fail "corresponding-source notice has the wrong commit URL"
}

verify_runtime_provenance() {
  local app_path="$1"
  local manifest_path="$2"
  local provenance="$app_path/Contents/Resources/Runtime/whisper-runtime-provenance.txt"

  [[ -s "$provenance" ]] || fail "app is missing whisper runtime provenance"
  grep -Fq \
    "$EXPECTED_WHISPER_CPP_VERSION:$EXPECTED_WHISPER_CPP_SHA256:arm64;x86_64:" \
    "$provenance" \
    || fail "whisper runtime provenance does not match the pinned universal source build"
  [[ "$(jq -r '.dependencies.whisper_cpp.version // empty' "$manifest_path")" \
      == "$EXPECTED_WHISPER_CPP_VERSION" ]] \
    || fail "release manifest has the wrong whisper.cpp version"
  [[ "$(jq -r '.dependencies.whisper_cpp.source_sha256 // empty' "$manifest_path")" \
      == "$EXPECTED_WHISPER_CPP_SHA256" ]] \
    || fail "release manifest has the wrong whisper.cpp source hash"
}

verify_sensevoice_runtime_provenance() {
  local app_path="$1"
  local manifest_path="$2"
  local provenance="$app_path/Contents/Resources/Runtime/sensevoice-runtime-provenance.txt"

  [[ -s "$provenance" ]] || fail "app is missing SenseVoice runtime provenance"
  grep -Fq \
    "$EXPECTED_SENSEVOICE_RUNTIME_VERSION:$EXPECTED_SENSEVOICE_RUNTIME_COMMIT:$EXPECTED_SENSEVOICE_RUNTIME_SOURCE_SHA256:$EXPECTED_SENSEVOICE_LLAMA_CPP_COMMIT:$EXPECTED_SENSEVOICE_LLAMA_CPP_SOURCE_SHA256:arm64;x86_64:$EXPECTED_SENSEVOICE_SEGMENT_DELIMITER_PATCH_SHA256:" \
    "$provenance" \
    || fail "SenseVoice runtime provenance does not match the pinned universal source build"
  [[ "$(jq -r '.dependencies.sensevoice_runtime.version // empty' "$manifest_path")" \
      == "$EXPECTED_SENSEVOICE_RUNTIME_VERSION" ]] \
    || fail "release manifest has the wrong SenseVoice runtime version"
  [[ "$(jq -r '.dependencies.sensevoice_runtime.source_revision // empty' "$manifest_path")" \
      == "$EXPECTED_SENSEVOICE_RUNTIME_COMMIT" ]] \
    || fail "release manifest has the wrong SenseVoice runtime source revision"
  [[ "$(jq -r '.dependencies.sensevoice_runtime.source_sha256 // empty' "$manifest_path")" \
      == "$EXPECTED_SENSEVOICE_RUNTIME_SOURCE_SHA256" ]] \
    || fail "release manifest has the wrong SenseVoice runtime source hash"
  [[ "$(jq -r '.dependencies.sensevoice_runtime.llama_cpp_revision // empty' "$manifest_path")" \
      == "$EXPECTED_SENSEVOICE_LLAMA_CPP_COMMIT" ]] \
    || fail "release manifest has the wrong SenseVoice llama.cpp revision"
  [[ "$(jq -r '.dependencies.sensevoice_runtime.llama_cpp_source_sha256 // empty' "$manifest_path")" \
      == "$EXPECTED_SENSEVOICE_LLAMA_CPP_SOURCE_SHA256" ]] \
    || fail "release manifest has the wrong SenseVoice llama.cpp source hash"
  [[ "$(jq -r '.dependencies.sensevoice_runtime.segment_delimiter_patch_sha256 // empty' "$manifest_path")" \
      == "$EXPECTED_SENSEVOICE_SEGMENT_DELIMITER_PATCH_SHA256" ]] \
    || fail "release manifest has the wrong SenseVoice segment-delimiter patch hash"
}

verify_sparkle_provenance() {
  local app_path="$1"
  local manifest_path="$2"
  local sparkle_info="$app_path/Contents/Frameworks/Sparkle.framework/Versions/B/Resources/Info.plist"
  local bundled_version

  [[ -f "$sparkle_info" ]] || fail "app is missing Sparkle framework version metadata"
  bundled_version="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' "$sparkle_info" 2>/dev/null || true)"
  [[ "$bundled_version" == "$EXPECTED_SPARKLE_VERSION" ]] \
    || fail "bundled Sparkle version must be $EXPECTED_SPARKLE_VERSION (found: ${bundled_version:-empty})"
  [[ "$(jq -r '.dependencies.sparkle.repository // empty' "$manifest_path")" \
      == "$EXPECTED_SPARKLE_REPOSITORY" ]] \
    || fail "release manifest has the wrong Sparkle repository"
  [[ "$(jq -r '.dependencies.sparkle.version // empty' "$manifest_path")" \
      == "$EXPECTED_SPARKLE_VERSION" ]] \
    || fail "release manifest has the wrong Sparkle version"
  [[ "$(jq -r '.dependencies.sparkle.revision // empty' "$manifest_path")" \
      == "$EXPECTED_SPARKLE_REVISION" ]] \
    || fail "release manifest has the wrong Sparkle revision"
}

verify_update_archive() (
  local zip_path="$1"
  local checksum_path="$2"
  local manifest_path="$3"
  local work_dir extract_dir app_path info_plist app_name version build_number bundle_id
  local expected_basename zip_sha checksum_zip_sha checksum_dmg_sha signature_details checksum_line_count
  local expected_dmg_name zip_directory checksum_directory manifest_directory

  for command_name in codesign ditto jq shasum xcrun; do
    command -v "$command_name" >/dev/null 2>&1 \
      || fail "required tool is unavailable: $command_name"
  done

  [[ -f "$zip_path" ]] || fail "ZIP archive does not exist: $zip_path"
  [[ -f "$checksum_path" ]] || fail "checksum manifest does not exist: $checksum_path"
  [[ -f "$manifest_path" ]] || fail "release manifest does not exist: $manifest_path"
  zip_directory="$(cd "$(dirname "$zip_path")" && pwd)"
  checksum_directory="$(cd "$(dirname "$checksum_path")" && pwd)"
  manifest_directory="$(cd "$(dirname "$manifest_path")" && pwd)"
  [[ "$zip_directory" == "$checksum_directory" \
      && "$zip_directory" == "$manifest_directory" ]] \
    || fail "appcast ZIP, checksum, and release manifest must share one directory"

  work_dir="$(mktemp -d /tmp/shuo-update-verify.XXXXXX)"
  trap 'rm -rf "$work_dir"' EXIT
  extract_dir="$work_dir/zip"
  mkdir -p "$extract_dir"
  ditto -x -k "$zip_path" "$extract_dir"
  app_path="$extract_dir/Shuo.app"
  [[ -d "$app_path" ]] || fail "update ZIP does not contain top-level Shuo.app"
  [[ "$(find "$extract_dir" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" == "1" ]] \
    || fail "update ZIP contains unexpected top-level items"

  info_plist="$app_path/Contents/Info.plist"
  [[ -f "$info_plist" ]] || fail "update app is missing Contents/Info.plist"
  app_name="$(basename "$app_path" .app)"
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || true)"
  build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist" 2>/dev/null || true)"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)"
  [[ "$app_name" == "Shuo" ]] || fail "update app bundle must be named Shuo.app"
  [[ -n "$version" && -n "$build_number" ]] || fail "update app version/build is empty"
  [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] \
    || fail "update app bundle ID must be $EXPECTED_BUNDLE_ID (found: ${bundle_id:-empty})"
  [[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]] \
    || fail "version '$version' is unsafe for release filenames"
  [[ "$build_number" =~ ^[0-9]+$ ]] \
    || fail "update app build '$build_number' must contain decimal digits only"

  expected_basename="$app_name-$version-macOS"
  expected_dmg_name="$expected_basename.dmg"
  [[ "$(basename "$zip_path")" == "$expected_basename.zip" ]] \
    || fail "update ZIP filename must be $expected_basename.zip"
  [[ "$(basename "$checksum_path")" == "$expected_basename.sha256" ]] \
    || fail "update checksum filename must be $expected_basename.sha256"
  [[ "$(basename "$manifest_path")" == "$expected_basename.manifest.json" ]] \
    || fail "update manifest filename must be $expected_basename.manifest.json"

  codesign --verify --deep --strict --all-architectures --verbose=2 "$app_path"
  signature_details="$(codesign --display --verbose=4 "$app_path" 2>&1)"
  grep -Fq 'Authority=Developer ID Application:' <<<"$signature_details" \
    || fail "update app is not signed with Developer ID Application"
  grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID" <<<"$signature_details" \
    || fail "update app is not signed by team $EXPECTED_TEAM_ID"
  grep -Eq '^Timestamp=' <<<"$signature_details" \
    || fail "update app has no secure signing timestamp"
  grep -Eq '^CodeDirectory .*flags=.*\(runtime\)' <<<"$signature_details" \
    || fail "update app is missing Hardened Runtime"
  xcrun stapler validate "$app_path"

  jq -e . "$manifest_path" >/dev/null \
    || fail "update release manifest is not valid JSON"
  [[ "$(jq -r '.schema_version // empty' "$manifest_path")" == "1" ]] \
    || fail "update release manifest schema_version must be 1"
  [[ "$(jq -r '.product // empty' "$manifest_path")" == "$app_name" ]] \
    || fail "update release manifest product does not match $app_name"
  [[ "$(jq -r '.bundle_id // empty' "$manifest_path")" == "$EXPECTED_BUNDLE_ID" ]] \
    || fail "update release manifest bundle_id does not match $EXPECTED_BUNDLE_ID"
  [[ "$(jq -r '.version // empty' "$manifest_path")" == "$version" ]] \
    || fail "update release manifest version does not match $version"
  [[ "$(jq -r '.build // empty' "$manifest_path")" == "$build_number" ]] \
    || fail "update release manifest build does not match $build_number"
  [[ "$(jq -r '.source.git_sha // empty' "$manifest_path")" =~ ^[0-9a-fA-F]{40,64}$ ]] \
    || fail "update release manifest is missing a valid source Git SHA"
  verify_corresponding_source "$app_path" "$manifest_path" "$version"
  verify_sparkle_provenance "$app_path" "$manifest_path"
  verify_runtime_provenance "$app_path" "$manifest_path"
  verify_sensevoice_runtime_provenance "$app_path" "$manifest_path"
  [[ "$(jq -r '.artifacts.zip.filename // empty' "$manifest_path")" == "$(basename "$zip_path")" ]] \
    || fail "update release manifest ZIP filename does not match"
  [[ "$(jq -r '.artifacts.dmg.filename // empty' "$manifest_path")" == "$expected_dmg_name" ]] \
    || fail "update release manifest DMG filename does not match the same RC version"
  [[ "$(jq -r '.artifacts.dmg.sha256 // empty' "$manifest_path")" =~ ^[0-9a-fA-F]{64}$ ]] \
    || fail "update release manifest is missing the RC DMG hash"
  [[ "$(jq -r '.artifacts.symbols.visibility // empty' "$manifest_path")" == "private" ]] \
    || fail "update release manifest must mark symbols as private"
  [[ "$(jq -r '.artifacts.symbols.filename // empty' "$manifest_path")" == "$expected_basename-symbols.zip" ]] \
    || fail "update release manifest private symbols filename does not match the same RC version"
  [[ "$(jq -r '.artifacts.symbols.path // empty' "$manifest_path")" == "private/$expected_basename-symbols.zip" ]] \
    || fail "update release manifest private symbols path does not match the same RC version"
  [[ "$(jq -r '.artifacts.symbols.sha256 // empty' "$manifest_path")" =~ ^[0-9a-fA-F]{64}$ ]] \
    || fail "update release manifest is missing the private symbols hash"

  zip_sha="$(shasum -a 256 "$zip_path" | awk '{ print $1 }')"
  [[ "$(jq -r '.artifacts.zip.sha256 // empty' "$manifest_path")" == "$zip_sha" ]] \
    || fail "update ZIP hash does not match the release manifest"

  checksum_line_count="$(awk 'NF { count += 1 } END { print count + 0 }' "$checksum_path")"
  [[ "$checksum_line_count" == "2" ]] \
    || fail "update checksum manifest must contain exactly the RC ZIP and DMG"
  checksum_zip_sha="$(awk -v expected="$(basename "$zip_path")" \
    '$1 ~ /^[0-9a-fA-F]{64}$/ && $2 == expected { print $1 }' "$checksum_path")"
  [[ "$checksum_zip_sha" == "$zip_sha" ]] \
    || fail "update ZIP hash does not match the RC checksum manifest"
  checksum_dmg_sha="$(awk -v expected="$expected_dmg_name" \
    '$1 ~ /^[0-9a-fA-F]{64}$/ && $2 == expected { print $1 }' "$checksum_path")"
  [[ -n "$checksum_dmg_sha" ]] \
    || fail "update checksum manifest is missing the same-version RC DMG"
  [[ "$checksum_dmg_sha" == "$(jq -r '.artifacts.dmg.sha256 // empty' "$manifest_path")" ]] \
    || fail "RC DMG hash differs between the checksum and release manifest"

  echo "Update archive verification passed: $app_name $version ($build_number), team $EXPECTED_TEAM_ID"
)

if [[ "$APP_PATH" == "--help" || "$APP_PATH" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "$APP_PATH" == "--update-archive" ]]; then
  if [[ -z "$ZIP_PATH" || -z "$DMG_PATH" || -z "$CHECKSUM_PATH" || -n "$MANIFEST_PATH" ]]; then
    usage >&2
    exit 2
  fi
  verify_update_archive "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
  exit 0
fi

if [[ -z "$APP_PATH" || -z "$ZIP_PATH" || -z "$DMG_PATH" || -z "$CHECKSUM_PATH" || -z "$MANIFEST_PATH" || -z "$SYMBOLS_PATH" ]]; then
  usage >&2
  exit 2
fi

for command_name in cmp codesign ditto dwarfdump file hdiutil jq lipo otool shasum spctl xcrun; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "required tool is unavailable: $command_name"
done

[[ -d "$APP_PATH" ]] || fail "app bundle does not exist: $APP_PATH"
[[ -f "$ZIP_PATH" ]] || fail "ZIP archive does not exist: $ZIP_PATH"
[[ -f "$DMG_PATH" ]] || fail "disk image does not exist: $DMG_PATH"
[[ -f "$CHECKSUM_PATH" ]] || fail "checksum manifest does not exist: $CHECKSUM_PATH"
[[ -f "$MANIFEST_PATH" ]] || fail "release manifest does not exist: $MANIFEST_PATH"
[[ -f "$SYMBOLS_PATH" ]] || fail "private symbols archive does not exist: $SYMBOLS_PATH"

APP_NAME="$(basename "$APP_PATH" .app)"
[[ "$APP_NAME" == "Shuo" ]] || fail "release app bundle must be named Shuo.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]] || fail "app is missing Contents/Info.plist"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || true)"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || true)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)"

[[ -n "$VERSION" ]] || fail "CFBundleShortVersionString is empty"
[[ -n "$BUILD_NUMBER" ]] || fail "CFBundleVersion is empty"
[[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] \
  || fail "CFBundleIdentifier must be $EXPECTED_BUNDLE_ID (found: ${BUNDLE_ID:-empty})"
[[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]] \
  || fail "version '$VERSION' is unsafe for release filenames"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] \
  || fail "build '$BUILD_NUMBER' must contain decimal digits only"

EXPECTED_BASENAME="$APP_NAME-$VERSION-macOS"
[[ "$(basename "$ZIP_PATH")" == "$EXPECTED_BASENAME.zip" ]] \
  || fail "ZIP filename must be $EXPECTED_BASENAME.zip"
[[ "$(basename "$DMG_PATH")" == "$EXPECTED_BASENAME.dmg" ]] \
  || fail "DMG filename must be $EXPECTED_BASENAME.dmg"
[[ "$(basename "$CHECKSUM_PATH")" == "$EXPECTED_BASENAME.sha256" ]] \
  || fail "checksum filename must be $EXPECTED_BASENAME.sha256"
[[ "$(basename "$MANIFEST_PATH")" == "$EXPECTED_BASENAME.manifest.json" ]] \
  || fail "manifest filename must be $EXPECTED_BASENAME.manifest.json"
[[ "$(basename "$SYMBOLS_PATH")" == "$EXPECTED_BASENAME-symbols.zip" ]] \
  || fail "symbols filename must be $EXPECTED_BASENAME-symbols.zip"

ZIP_DIRECTORY="$(cd "$(dirname "$ZIP_PATH")" && pwd)"
DMG_DIRECTORY="$(cd "$(dirname "$DMG_PATH")" && pwd)"
CHECKSUM_DIRECTORY="$(cd "$(dirname "$CHECKSUM_PATH")" && pwd)"
MANIFEST_DIRECTORY="$(cd "$(dirname "$MANIFEST_PATH")" && pwd)"
SYMBOLS_DIRECTORY="$(cd "$(dirname "$SYMBOLS_PATH")" && pwd)"
[[ "$ZIP_DIRECTORY" == "$DMG_DIRECTORY" \
    && "$ZIP_DIRECTORY" == "$CHECKSUM_DIRECTORY" \
    && "$ZIP_DIRECTORY" == "$MANIFEST_DIRECTORY" ]] \
  || fail "public release artifacts, checksum manifest, and release manifest must share one directory"
[[ "$SYMBOLS_DIRECTORY" != "$ZIP_DIRECTORY" ]] \
  || fail "private symbols archive must not share the public release directory"

WORK_DIR="$(mktemp -d /tmp/shuo-release-verify.XXXXXX)"
MOUNT_DIR="$WORK_DIR/dmg"
DMG_IS_MOUNTED=0

cleanup() {
  if [[ "$DMG_IS_MOUNTED" == "1" ]]; then
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

signature_details() {
  codesign --display --verbose=4 "$1" 2>&1
}

verify_developer_id_signature() {
  local path="$1"
  local kind="$2"
  local details

  if [[ "$kind" == "app" ]]; then
    codesign --verify --deep --strict --all-architectures --verbose=2 "$path"
  else
    codesign --verify --strict --verbose=2 "$path"
  fi

  details="$(signature_details "$path")"
  grep -Fq 'Authority=Developer ID Application:' <<<"$details" \
    || fail "$(basename "$path") is not signed with Developer ID Application"
  grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID" <<<"$details" \
    || fail "$(basename "$path") is not signed by team $EXPECTED_TEAM_ID"
  grep -Eq '^Timestamp=' <<<"$details" \
    || fail "$(basename "$path") has no secure signing timestamp"

  if [[ "$kind" == "app" ]]; then
    grep -Eq '^CodeDirectory .*flags=.*\(runtime\)' <<<"$details" \
      || fail "$(basename "$path") is missing Hardened Runtime"
  fi
}

verify_universal_app() {
  local app_path="$1"
  local executable="$app_path/Contents/MacOS/$APP_NAME"
  local macho_count=0
  local binary archs arch_count relative_path dependency

  [[ -x "$executable" ]] || fail "app is missing its main executable"

  while IFS= read -r -d '' binary; do
    if ! file -b "$binary" | grep -q 'Mach-O'; then
      continue
    fi

    macho_count=$((macho_count + 1))
    archs="$(lipo -archs "$binary" 2>/dev/null || true)"
    relative_path="${binary#"$app_path"/}"
    [[ " $archs " == *" arm64 "* ]] \
      || fail "$relative_path is missing arm64"
    [[ " $archs " == *" x86_64 "* ]] \
      || fail "$relative_path is missing x86_64"
    arch_count="$(wc -w <<<"$archs" | tr -d ' ')"
    [[ "$arch_count" == "2" ]] \
      || fail "$relative_path contains unexpected architectures: $archs"

    # A valid signature does not prove that a binary can launch on a clean Mac.
    # Reject accidental Homebrew, build-directory, or other host-only dylib
    # references. Sparkle is the only non-system dynamic dependency in Shuo.
    while IFS= read -r dependency; do
      [[ -n "$dependency" ]] || continue
      case "$dependency" in
        /System/Library/* | /usr/lib/* | @rpath/Sparkle.framework/Versions/B/Sparkle)
          ;;
        *)
          fail "$relative_path links an unapproved dynamic dependency: $dependency"
          ;;
      esac
    done < <(otool -L "$binary" | awk '/^\t/ { print $1 }' | LC_ALL=C sort -u)
  done < <(find "$app_path" -type f -print0)

  ((macho_count > 0)) || fail "app contains no Mach-O executables"
}

verify_bundle_metadata() {
  local app_path="$1"
  local plist="$app_path/Contents/Info.plist"
  local actual_version actual_build actual_bundle_id

  [[ -f "$plist" ]] || fail "packaged app is missing Info.plist"
  actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)"
  actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || true)"
  actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"

  [[ "$actual_version" == "$VERSION" ]] \
    || fail "packaged app version '$actual_version' does not match '$VERSION'"
  [[ "$actual_build" == "$BUILD_NUMBER" ]] \
    || fail "packaged app build '$actual_build' does not match '$BUILD_NUMBER'"
  [[ "$actual_bundle_id" == "$EXPECTED_BUNDLE_ID" ]] \
    || fail "packaged app bundle ID '$actual_bundle_id' does not match '$EXPECTED_BUNDLE_ID'"
}

verify_required_bundle_contents() {
  local app_path="$1"
  local plist="$app_path/Contents/Info.plist"
  local resources="$app_path/Contents/Resources"
  local feed_url public_key development_build
  local required_path

  [[ -d "$app_path/Contents/Frameworks/Sparkle.framework" ]] \
    || fail "app is missing Sparkle.framework"
  [[ -x "$resources/Runtime/whisper-cli" ]] \
    || fail "app is missing executable Runtime/whisper-cli"
  [[ -x "$resources/Runtime/sensevoice-cli" ]] \
    || fail "app is missing executable Runtime/sensevoice-cli"
  for required_path in \
	"$resources/LICENSE" \
	"$resources/CORRESPONDING_SOURCE.txt" \
	"$resources/THIRD_PARTY_NOTICES.md" \
    "$resources/ThirdParty/whisper.cpp-LICENSE" \
    "$resources/ThirdParty/SenseVoice-LICENSE.txt" \
    "$resources/ThirdParty/SenseVoiceSmall-GGUF-LICENSE.txt" \
    "$resources/ThirdParty/llama.cpp-LICENSE.txt" \
    "$resources/ThirdParty/OpenAI-Whisper-LICENSE.txt" \
    "$resources/ThirdParty/Sparkle-LICENSE.txt" \
    "$resources/ThirdParty/Unicode-CLDR-LICENSE.txt"; do
    [[ -s "$required_path" ]] \
      || fail "app is missing required notice/license: ${required_path#"$resources"/}"
  done

  feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist" 2>/dev/null || true)"
  public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" 2>/dev/null || true)"
  development_build="$(/usr/libexec/PlistBuddy -c 'Print :ShuoDevelopmentBuild' "$plist" 2>/dev/null || true)"
  [[ "$feed_url" == "$EXPECTED_FEED_URL" ]] \
    || fail "SUFeedURL must be $EXPECTED_FEED_URL (found: ${feed_url:-empty})"
  [[ "$public_key" == "$EXPECTED_SPARKLE_PUBLIC_KEY" ]] \
    || fail "SUPublicEDKey does not match the production update key"
  [[ -z "$development_build" ]] \
    || fail "production app must not contain ShuoDevelopmentBuild"
  verify_corresponding_source "$app_path" "$MANIFEST_PATH" "$VERSION"
  verify_sparkle_provenance "$app_path" "$MANIFEST_PATH"
  verify_runtime_provenance "$app_path" "$MANIFEST_PATH"
  verify_sensevoice_runtime_provenance "$app_path" "$MANIFEST_PATH"
}

verify_production_entitlements() {
  local app_path="$1"
  local extracted_entitlements
  extracted_entitlements="$WORK_DIR/entitlements-$RANDOM.plist"
  if ! codesign -d --entitlements - --xml "$app_path" \
    >"$extracted_entitlements" 2>/dev/null; then
    fail "could not extract production entitlements from $(basename "$app_path")"
  fi

  plutil -convert json -o - "$extracted_entitlements" \
    | jq -e '
        keys == ["com.apple.security.device.audio-input"]
        and .["com.apple.security.device.audio-input"] == true
      ' >/dev/null \
    || fail "production app entitlements must contain only audio-input=true"
}

code_directory_hash() {
  local details

  # Do not pipe codesign directly into an early-exiting reader. Under
  # `set -o pipefail`, awk's `exit` can close the pipe before codesign has
  # finished writing, turning an otherwise valid release into SIGPIPE (141).
  details="$(codesign --display --verbose=4 "$1" 2>&1)"
  awk -F= '$1 == "CDHash" { print $2; found = 1 } END { exit !found }' \
    <<<"$details"
}

verify_notarized_app() {
  local app_path="$1"
  verify_bundle_metadata "$app_path"
  verify_required_bundle_contents "$app_path"
  verify_developer_id_signature "$app_path" app
  verify_production_entitlements "$app_path"
  verify_universal_app "$app_path"
  xcrun stapler validate "$app_path"
  spctl \
    --assess \
    --type execute \
    --ignore-cache \
    --no-cache \
    --verbose=4 \
    "$app_path"
}

echo "Verifying signed and stapled build product..."
verify_notarized_app "$APP_PATH"
APP_CDHASH="$(code_directory_hash "$APP_PATH")"
[[ -n "$APP_CDHASH" ]] || fail "could not read build-product code directory hash"

echo "Verifying final ZIP payload..."
ZIP_EXTRACT_DIR="$WORK_DIR/zip"
mkdir -p "$ZIP_EXTRACT_DIR"
ditto -x -k "$ZIP_PATH" "$ZIP_EXTRACT_DIR"
ZIP_APP="$ZIP_EXTRACT_DIR/$APP_NAME.app"
[[ -d "$ZIP_APP" ]] || fail "ZIP does not contain top-level $APP_NAME.app"
[[ "$(find "$ZIP_EXTRACT_DIR" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" == "1" ]] \
  || fail "ZIP contains unexpected top-level items"
verify_notarized_app "$ZIP_APP"
[[ "$(code_directory_hash "$ZIP_APP")" == "$APP_CDHASH" ]] \
  || fail "ZIP app does not match the verified build product"
cmp -s "$APP_PATH/Contents/MacOS/$APP_NAME" "$ZIP_APP/Contents/MacOS/$APP_NAME" \
  || fail "ZIP executable differs from the verified build product"

echo "Verifying signed and stapled DMG..."
hdiutil verify "$DMG_PATH" >/dev/null
verify_developer_id_signature "$DMG_PATH" dmg
xcrun stapler validate "$DMG_PATH"
spctl \
  --assess \
  --type open \
  --context context:primary-signature \
  --ignore-cache \
  --no-cache \
  --verbose=4 \
  "$DMG_PATH"

mkdir -p "$MOUNT_DIR"
hdiutil attach \
  -readonly \
  -noverify \
  -noautoopen \
  -nobrowse \
  -mountpoint "$MOUNT_DIR" \
  "$DMG_PATH" >/dev/null
DMG_IS_MOUNTED=1
DMG_APP="$MOUNT_DIR/$APP_NAME.app"
[[ -d "$DMG_APP" ]] || fail "DMG does not contain top-level $APP_NAME.app"
[[ -L "$MOUNT_DIR/Applications" ]] \
  || fail "DMG Applications item is not a symbolic link"
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]] \
  || fail "DMG Applications link does not target /Applications"
DMG_TOP_LEVEL="$(find "$MOUNT_DIR" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)"
EXPECTED_DMG_TOP_LEVEL="$(printf '%s\n' '.DS_Store' '.VolumeIcon.icns' '.background' 'Applications' "$APP_NAME.app" | LC_ALL=C sort)"
[[ "$DMG_TOP_LEVEL" == "$EXPECTED_DMG_TOP_LEVEL" ]] \
  || fail "DMG contains unexpected or missing top-level items"
verify_notarized_app "$DMG_APP"
[[ "$(code_directory_hash "$DMG_APP")" == "$APP_CDHASH" ]] \
  || fail "DMG app does not match the verified build product"
cmp -s "$APP_PATH/Contents/MacOS/$APP_NAME" "$DMG_APP/Contents/MacOS/$APP_NAME" \
  || fail "DMG executable differs from the verified build product"
hdiutil detach "$MOUNT_DIR" >/dev/null
DMG_IS_MOUNTED=0

echo "Verifying private release symbols..."
SYMBOLS_EXTRACT_DIR="$WORK_DIR/symbols"
mkdir -p "$SYMBOLS_EXTRACT_DIR"
ditto -x -k "$SYMBOLS_PATH" "$SYMBOLS_EXTRACT_DIR"
DSYM_PATH="$SYMBOLS_EXTRACT_DIR/$APP_NAME.app.dSYM"
DSYM_DWARF="$DSYM_PATH/Contents/Resources/DWARF/$APP_NAME"
[[ -f "$DSYM_DWARF" ]] || fail "symbols archive is missing $APP_NAME DWARF data"
APP_UUIDS="$(dwarfdump --uuid "$APP_PATH/Contents/MacOS/$APP_NAME" | awk '{print $2 ":" $3}' | sort)"
DSYM_UUIDS="$(dwarfdump --uuid "$DSYM_DWARF" | awk '{print $2 ":" $3}' | sort)"
[[ -n "$APP_UUIDS" && "$APP_UUIDS" == "$DSYM_UUIDS" ]] \
  || fail "dSYM UUIDs do not match the release executable"

LATEST_ZIP="$ZIP_DIRECTORY/$APP_NAME-latest-macOS.zip"
LATEST_DMG="$ZIP_DIRECTORY/$APP_NAME-latest-macOS.dmg"
[[ -f "$LATEST_ZIP" ]] || fail "latest ZIP alias is missing"
[[ -f "$LATEST_DMG" ]] || fail "latest DMG alias is missing"
cmp -s "$ZIP_PATH" "$LATEST_ZIP" || fail "latest ZIP differs from versioned ZIP"
cmp -s "$DMG_PATH" "$LATEST_DMG" || fail "latest DMG differs from versioned DMG"

CHECKSUM_LINE_COUNT="$(awk 'NF { count += 1 } END { print count + 0 }' "$CHECKSUM_PATH")"
[[ "$CHECKSUM_LINE_COUNT" == "2" ]] \
  || fail "checksum manifest must contain exactly two entries"
awk -v expected="$(basename "$ZIP_PATH")" \
  '$1 ~ /^[0-9a-fA-F]{64}$/ && $2 == expected { found = 1 } END { exit !found }' \
  "$CHECKSUM_PATH" \
  || fail "checksum manifest is missing the versioned ZIP"
awk -v expected="$(basename "$DMG_PATH")" \
  '$1 ~ /^[0-9a-fA-F]{64}$/ && $2 == expected { found = 1 } END { exit !found }' \
  "$CHECKSUM_PATH" \
  || fail "checksum manifest is missing the versioned DMG"
(
  cd "$CHECKSUM_DIRECTORY"
  shasum -a 256 --check "$(basename "$CHECKSUM_PATH")"
)

echo "Verifying traceable release manifest..."
jq -e . "$MANIFEST_PATH" >/dev/null \
  || fail "release manifest is not valid JSON"
[[ "$(jq -r '.schema_version // empty' "$MANIFEST_PATH")" == "1" ]] \
  || fail "release manifest schema_version must be 1"
[[ "$(jq -r '.product // empty' "$MANIFEST_PATH")" == "$APP_NAME" ]] \
  || fail "release manifest product does not match $APP_NAME"
[[ "$(jq -r '.bundle_id // empty' "$MANIFEST_PATH")" == "$EXPECTED_BUNDLE_ID" ]] \
  || fail "release manifest bundle_id does not match $EXPECTED_BUNDLE_ID"
[[ "$(jq -r '.version // empty' "$MANIFEST_PATH")" == "$VERSION" ]] \
  || fail "release manifest version does not match $VERSION"
[[ "$(jq -r '.build // empty' "$MANIFEST_PATH")" == "$BUILD_NUMBER" ]] \
  || fail "release manifest build does not match $BUILD_NUMBER"
MANIFEST_GIT_SHA="$(jq -r '.source.git_sha // empty' "$MANIFEST_PATH")"
[[ "$MANIFEST_GIT_SHA" =~ ^[0-9a-fA-F]{40,64}$ ]] \
  || fail "release manifest is missing a valid source Git SHA"
[[ "$(jq -r '.artifacts.zip.filename // empty' "$MANIFEST_PATH")" == "$(basename "$ZIP_PATH")" ]] \
  || fail "release manifest ZIP filename does not match"
[[ "$(jq -r '.artifacts.dmg.filename // empty' "$MANIFEST_PATH")" == "$(basename "$DMG_PATH")" ]] \
  || fail "release manifest DMG filename does not match"
[[ "$(jq -r '.artifacts.symbols.filename // empty' "$MANIFEST_PATH")" == "$(basename "$SYMBOLS_PATH")" ]] \
  || fail "release manifest symbols filename does not match"
[[ "$(jq -r '.artifacts.symbols.path // empty' "$MANIFEST_PATH")" == "private/$(basename "$SYMBOLS_PATH")" ]] \
  || fail "release manifest private symbols path does not match"
[[ "$(jq -r '.artifacts.symbols.visibility // empty' "$MANIFEST_PATH")" == "private" ]] \
  || fail "release manifest must mark symbols as private"
ZIP_SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{ print $1 }')"
DMG_SHA="$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')"
SYMBOLS_SHA="$(shasum -a 256 "$SYMBOLS_PATH" | awk '{ print $1 }')"
[[ "$(jq -r '.artifacts.zip.sha256 // empty' "$MANIFEST_PATH")" == "$ZIP_SHA" ]] \
  || fail "release manifest ZIP hash does not match"
[[ "$(jq -r '.artifacts.dmg.sha256 // empty' "$MANIFEST_PATH")" == "$DMG_SHA" ]] \
  || fail "release manifest DMG hash does not match"
[[ "$(jq -r '.artifacts.symbols.sha256 // empty' "$MANIFEST_PATH")" == "$SYMBOLS_SHA" ]] \
  || fail "release manifest symbols hash does not match"

echo "Release verification passed:"
echo "  App: $APP_NAME $VERSION ($BUILD_NUMBER), $BUNDLE_ID"
echo "  Architectures: arm64 + x86_64"
echo "  Team: $EXPECTED_TEAM_ID"
echo "  Checksums: $CHECKSUM_PATH"
echo "  Source: $MANIFEST_GIT_SHA"
echo "  Manifest: $MANIFEST_PATH"
