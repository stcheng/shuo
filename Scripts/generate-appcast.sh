#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${SHUO_APP_NAME:-Shuo}"
PACKAGE_DIR="${SHUO_PACKAGE_DIR:-$ROOT_DIR/dist}"
APPCAST_OUTPUT="${SHUO_APPCAST_OUTPUT:-$ROOT_DIR/web/appcast.xml}"
EXPECTED_RELEASE_REPOSITORY="stcheng/shuo"
REPOSITORY="${SHUO_RELEASE_REPOSITORY:-$EXPECTED_RELEASE_REPOSITORY}"
RELEASE_NOTES="${SHUO_RELEASE_NOTES:-}"
SPARKLE_ACCOUNT="${SHUO_SPARKLE_ACCOUNT:-ed25519}"
EXPECTED_SPARKLE_PUBLIC_KEY="i0Hw/eZpvDeme6HTBGedmDhGfLECOXuTZ1q6urwyZyg="
EXPECTED_SPARKLE_REPOSITORY="https://github.com/sparkle-project/Sparkle"
EXPECTED_SPARKLE_VERSION="2.9.4"
EXPECTED_SPARKLE_REVISION="b6496a74a087257ef5e6da1c5b29a447a60f5bd7"
PACKAGE_RESOLVED="$ROOT_DIR/Shuo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
DERIVED_DATA="${SHUO_DERIVED_DATA:-$ROOT_DIR/DerivedData/Package}"
ARCHIVE="${1:-}"

fail() {
  echo "Appcast generation failed: $*" >&2
  exit 1
}

find_sparkle_bin() {
  local candidate workspace_state resolved_repository resolved_revision resolved_version
  local built_repository built_revision built_version requested_candidate

  # Xcode records the package artifact under the exact DerivedData directory
  # used for the resolved build. Do not accept an arbitrary tool path or search
  # ~/Library/Developer/Xcode: either can silently select a stale Sparkle tool.
  candidate="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"
  workspace_state="$DERIVED_DATA/SourcePackages/workspace-state.json"

  [[ -f "$PACKAGE_RESOLVED" ]] \
    || fail "Swift package resolution is missing: $PACKAGE_RESOLVED"
  [[ -f "$workspace_state" ]] \
    || fail "Sparkle has not been resolved in $DERIVED_DATA. Build ShuoDirect with that DerivedData path first."

  [[ "$(jq '.pins | length' "$PACKAGE_RESOLVED")" == "1" ]] \
    || fail "Package.resolved must contain only the reviewed Sparkle dependency."
  resolved_repository="$(jq -er \
    '.pins[] | select(.identity == "sparkle") | .location' \
    "$PACKAGE_RESOLVED" 2>/dev/null || true)"
  resolved_revision="$(jq -er \
    '.pins[] | select(.identity == "sparkle") | .state.revision' \
    "$PACKAGE_RESOLVED" 2>/dev/null || true)"
  resolved_version="$(jq -er \
    '.pins[] | select(.identity == "sparkle") | .state.version' \
    "$PACKAGE_RESOLVED" 2>/dev/null || true)"
  built_repository="$(jq -er \
    '.object.dependencies[] | select(.packageRef.identity == "sparkle") | .packageRef.location' \
    "$workspace_state" 2>/dev/null || true)"
  built_revision="$(jq -er \
    '.object.dependencies[] | select(.packageRef.identity == "sparkle") | .state.checkoutState.revision' \
    "$workspace_state" 2>/dev/null || true)"
  built_version="$(jq -er \
    '.object.dependencies[] | select(.packageRef.identity == "sparkle") | .state.checkoutState.version' \
    "$workspace_state" 2>/dev/null || true)"

  [[ "$resolved_repository" == "$EXPECTED_SPARKLE_REPOSITORY" \
      && "$resolved_revision" == "$EXPECTED_SPARKLE_REVISION" \
      && "$resolved_version" == "$EXPECTED_SPARKLE_VERSION" ]] \
    || fail "Package.resolved does not contain the reviewed Sparkle $EXPECTED_SPARKLE_VERSION pin."
  [[ -n "$resolved_revision" && -n "$resolved_version" ]] \
    || fail "Package.resolved does not contain a complete Sparkle pin."
  [[ "$built_repository" == "$EXPECTED_SPARKLE_REPOSITORY" \
      && "$built_revision" == "$EXPECTED_SPARKLE_REVISION" \
      && "$built_version" == "$EXPECTED_SPARKLE_VERSION" ]] \
    || fail "Sparkle tools in $DERIVED_DATA do not match the reviewed $EXPECTED_SPARKLE_VERSION dependency. Rebuild ShuoDirect first."

  requested_candidate="$candidate"
  candidate="$(cd "$requested_candidate" 2>/dev/null && pwd -P)" \
    || fail "Sparkle tool directory does not exist: $requested_candidate"
  for tool in generate_appcast generate_keys sign_update; do
    [[ -x "$candidate/$tool" ]] \
      || fail "Sparkle $tool was not found in $candidate."
  done
  echo "$candidate"
}

verify_sparkle_signing_key() {
  local generate_keys="$1"
  local actual_public_key

  [[ -n "$SPARKLE_ACCOUNT" ]] || fail "SHUO_SPARKLE_ACCOUNT must not be empty."
  actual_public_key="$("$generate_keys" --account "$SPARKLE_ACCOUNT" -p)" \
    || fail "Unable to read Sparkle signing key account '$SPARKLE_ACCOUNT' from Keychain."
  actual_public_key="$(printf '%s' "$actual_public_key" | tr -d '[:space:]')"
  [[ "$actual_public_key" == "$EXPECTED_SPARKLE_PUBLIC_KEY" ]] \
    || fail "Sparkle Keychain account '$SPARKLE_ACCOUNT' does not match the production SUPublicEDKey."
}

if [[ -z "$ARCHIVE" ]]; then
  if [[ -d "$PACKAGE_DIR" ]]; then
    ARCHIVE="$(find "$PACKAGE_DIR" -maxdepth 1 -type f -name "$APP_NAME-[0-9]*-macOS.zip" -print | sort -V | tail -1)"
  fi
fi

if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  echo "A versioned Shuo ZIP archive is required." >&2
  exit 1
fi

ARCHIVE_BASENAME="$(basename "$ARCHIVE")"
ARCHIVE_STEM="${ARCHIVE%.zip}"
CHECKSUM="${SHUO_RELEASE_CHECKSUM:-$ARCHIVE_STEM.sha256}"
MANIFEST="${SHUO_RELEASE_MANIFEST:-$ARCHIVE_STEM.manifest.json}"
if [[ ! -f "$CHECKSUM" ]]; then
  echo "The matching RC checksum manifest is required: $CHECKSUM" >&2
  exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
  echo "The matching RC release manifest is required: $MANIFEST" >&2
  exit 1
fi

# Fail closed before touching the existing feed. This verifies the notarized
# ZIP, exact Developer ID team, bundle metadata, RC checksum, and manifest hash
# without requiring the DMG or private dSYM to be present on the feed machine.
"$ROOT_DIR/Scripts/verify-release-artifacts.sh" \
  --update-archive \
  "$ARCHIVE" \
  "$CHECKSUM" \
  "$MANIFEST"

VERSION="$(jq -r '.version' "$MANIFEST")"
BUILD_NUMBER="$(jq -r '.build' "$MANIFEST")"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] \
  || fail "RC build number must contain decimal digits only."
EXPECTED_RELEASE_TAG="v$VERSION"
RELEASE_TAG="${SHUO_RELEASE_TAG:-$EXPECTED_RELEASE_TAG}"
if [[ "$RELEASE_TAG" != "$EXPECTED_RELEASE_TAG" ]]; then
  echo "Release tag must be $EXPECTED_RELEASE_TAG for RC version $VERSION." >&2
  exit 1
fi
[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
  || fail "SHUO_RELEASE_REPOSITORY must be a GitHub owner/repository pair."
[[ "$REPOSITORY" == "$EXPECTED_RELEASE_REPOSITORY" ]] \
  || fail "Release repository must be the canonical $EXPECTED_RELEASE_REPOSITORY repository."
DOWNLOAD_PREFIX="https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG/"
PRODUCT_LINK="https://github.com/$REPOSITORY/releases/tag/$RELEASE_TAG"
EXPECTED_ARCHIVE_URL="$DOWNLOAD_PREFIX$ARCHIVE_BASENAME"
SPARKLE_BIN="$(find_sparkle_bin)"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
GENERATE_KEYS="$SPARKLE_BIN/generate_keys"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
verify_sparkle_signing_key "$GENERATE_KEYS"
WORK_DIR="$(mktemp -d /tmp/shuo-appcast.XXXXXX)"
TEMPORARY_OUTPUT=""

cleanup() {
  rm -rf "$WORK_DIR"
  [[ -z "$TEMPORARY_OUTPUT" ]] || rm -f "$TEMPORARY_OUTPUT"
}
trap cleanup EXIT

cp "$ARCHIVE" "$WORK_DIR/$ARCHIVE_BASENAME"
if [[ -f "$APPCAST_OUTPUT" ]]; then
  cp "$APPCAST_OUTPUT" "$WORK_DIR/appcast.xml"
fi
if [[ -n "$RELEASE_NOTES" ]]; then
  cp "$RELEASE_NOTES" "$WORK_DIR/${ARCHIVE_BASENAME%.zip}.md"
fi

"$GENERATE_APPCAST" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "$PRODUCT_LINK" \
  --maximum-versions 3 \
  --maximum-deltas 0 \
  -o "$WORK_DIR/appcast.xml" \
  "$WORK_DIR"

xmllint --noout "$WORK_DIR/appcast.xml"
CANONICAL_URL_COUNT="$(xmllint --xpath \
  "count(//*[local-name()='enclosure' and @url='$EXPECTED_ARCHIVE_URL'])" \
  "$WORK_DIR/appcast.xml")"
[[ "$CANONICAL_URL_COUNT" == "1" ]] \
  || fail "Generated appcast must contain exactly one enclosure with canonical URL $EXPECTED_ARCHIVE_URL (found $CANONICAL_URL_COUNT)."
MATCHING_ITEM_COUNT="$(xmllint --xpath \
  "count(//*[local-name()='enclosure' and @url='$EXPECTED_ARCHIVE_URL' and @*[local-name()='version']='$BUILD_NUMBER' and @*[local-name()='shortVersionString']='$VERSION'])" \
  "$WORK_DIR/appcast.xml")"
[[ "$MATCHING_ITEM_COUNT" == "1" ]] \
  || fail "Canonical appcast enclosure does not bind version $VERSION build $BUILD_NUMBER exactly once."
CURRENT_VERSION_BUILD_COUNT="$(xmllint --xpath \
  "count(//*[local-name()='enclosure' and @*[local-name()='version']='$BUILD_NUMBER' and @*[local-name()='shortVersionString']='$VERSION'])" \
  "$WORK_DIR/appcast.xml")"
[[ "$CURRENT_VERSION_BUILD_COUNT" == "1" ]] \
  || fail "Appcast must contain version $VERSION build $BUILD_NUMBER exactly once across all enclosure URLs."
MATCHING_SIGNATURE="$(xmllint --xpath \
  "string((//*[local-name()='enclosure' and @url='$EXPECTED_ARCHIVE_URL' and @*[local-name()='version']='$BUILD_NUMBER' and @*[local-name()='shortVersionString']='$VERSION'])[1]/@*[local-name()='edSignature'])" \
  "$WORK_DIR/appcast.xml")"
MATCHING_LENGTH="$(xmllint --xpath \
  "string((//*[local-name()='enclosure' and @url='$EXPECTED_ARCHIVE_URL' and @*[local-name()='version']='$BUILD_NUMBER' and @*[local-name()='shortVersionString']='$VERSION'])[1]/@length)" \
  "$WORK_DIR/appcast.xml")"
ARCHIVE_LENGTH="$(stat -f '%z' "$ARCHIVE")"
if [[ -z "$MATCHING_SIGNATURE" || "$MATCHING_LENGTH" != "$ARCHIVE_LENGTH" ]]; then
  echo "Generated appcast enclosure does not match the exact RC ZIP bytes." >&2
  exit 1
fi
"$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" --verify "$ARCHIVE" "$MATCHING_SIGNATURE"

mkdir -p "$(dirname "$APPCAST_OUTPUT")"
TEMPORARY_OUTPUT="$(mktemp "$(dirname "$APPCAST_OUTPUT")/.appcast.xml.tmp.XXXXXX")"
cp "$WORK_DIR/appcast.xml" "$TEMPORARY_OUTPUT"
mv "$TEMPORARY_OUTPUT" "$APPCAST_OUTPUT"
TEMPORARY_OUTPUT=""

echo "Created signed appcast: $APPCAST_OUTPUT"
echo "Release archive URL: $DOWNLOAD_PREFIX$ARCHIVE_BASENAME"
echo "Bound RC manifest: $MANIFEST"
