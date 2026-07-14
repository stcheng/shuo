#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${SHUO_APP_NAME:-Shuo}"
SCHEME="${SHUO_SCHEME:-ShuoDirect}"
CONFIGURATION="${SHUO_CONFIGURATION:-Release}"
SIGN_IDENTITY="${SHUO_CODESIGN_IDENTITY:-Shuo Local Development}"
SIGN_MODE="${SHUO_SIGN_MODE:-adhoc}"
KEYCHAIN="${SHUO_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
DERIVED_DATA="${SHUO_DERIVED_DATA:-$ROOT_DIR/DerivedData/Package}"
PACKAGE_DIR="${SHUO_PACKAGE_DIR:-$ROOT_DIR/dist}"
PRIVATE_ARTIFACT_DIR="${SHUO_PRIVATE_ARTIFACT_DIR:-$PACKAGE_DIR/private}"
PKCS12_PASSWORD="${SHUO_PKCS12_PASSWORD:-shuo-local-development}"
ENTITLEMENTS="${SHUO_ENTITLEMENTS:-$ROOT_DIR/App/ShuoDirect.entitlements}"
NOTARIZE="${SHUO_NOTARIZE:-0}"
NOTARY_PROFILE="${SHUO_NOTARY_PROFILE-Shuo-Notary}"
RELEASE_MODE="${SHUO_RELEASE:-0}"
EXPECTED_TEAM_ID="4GQ47468NJ"
CANONICAL_SOURCE_REPOSITORY="https://github.com/stcheng/shuo.git"
CANONICAL_SOURCE_WEB="https://github.com/stcheng/shuo"
PINNED_SPARKLE_REPOSITORY="https://github.com/sparkle-project/Sparkle"
PINNED_SPARKLE_VERSION="2.9.4"
PINNED_SPARKLE_REVISION="b6496a74a087257ef5e6da1c5b29a447a60f5bd7"
PINNED_WHISPER_CPP_VERSION="1.8.6"
PINNED_WHISPER_CPP_SHA256="f8e632016ceae556f3132a16c7f704be1e7715595041f474fa81a2b64c1abf7c"
PINNED_RELEASE_ENTITLEMENTS="$ROOT_DIR/App/ShuoDirect.entitlements"
PINNED_RELEASE_ENTITLEMENTS_SHA256="289696af9834a7ee41aca4c1cd3aa95fc38f9ae2e83655b1d4b86c1ccab771ee"
SOURCE_GIT_SHA=""
SOURCE_GIT_REF=""
SOURCE_GIT_TAG=""
RELEASE_STAGING_DIR=""
RELEASE_TEMP_DERIVED_DATA=""

FORMAT="${1:-${SHUO_PACKAGE_FORMAT:-zip}}"
APP_SOURCE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

usage() {
  cat <<EOF
Usage: Scripts/package-app.sh [zip|dmg|all]

Environment:
  SHUO_APP_NAME            Built app and artifact name. Default: Shuo
  SHUO_SCHEME              Xcode scheme. Default: ShuoDirect
  SHUO_CONFIGURATION       Build configuration. Default: Release
  SHUO_SIGN_MODE           adhoc, local, or identity. Default: adhoc
  SHUO_CODESIGN_IDENTITY   Signing identity for local/identity modes.
                            Default: Shuo Local Development
  SHUO_PACKAGE_DIR         Output directory. Default: ./dist
  SHUO_PRIVATE_ARTIFACT_DIR
                            Private release output. Default: <package-dir>/private
  SHUO_DERIVED_DATA        DerivedData directory. Default: ./DerivedData/Package
                            Ignored for SHUO_RELEASE=1; RC builds always use a
                            fresh temporary DerivedData directory.
  SHUO_NOTARIZE            Set to 1 to submit and staple. Requires identity signing.
  SHUO_NOTARY_PROFILE      notarytool Keychain profile. Default: Shuo-Notary
  SHUO_RELEASE             Set to 1 only through the fail-closed release-rc target.

Examples:
  Scripts/package-app.sh zip
  Scripts/package-app.sh dmg
  SHUO_SIGN_MODE=local Scripts/package-app.sh all
  SHUO_SIGN_MODE=identity SHUO_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/package-app.sh dmg
EOF
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing release dependency: $command_name" >&2
    exit 2
  fi
}

capture_release_source_state() {
  [[ "$RELEASE_MODE" == "1" ]] || return 0

  require_command git
  if [[ "$(git -C "$ROOT_DIR" rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]]; then
    echo "Release candidates must be built from a Git working tree." >&2
    exit 2
  fi

  local source_status
  source_status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)"
  if [[ -n "$source_status" ]]; then
    echo "Release candidates require a clean Git working tree." >&2
    printf '%s\n' "$source_status" >&2
    exit 2
  fi

  SOURCE_GIT_SHA="$(git -C "$ROOT_DIR" rev-parse --verify HEAD)"
  if [[ ! "$SOURCE_GIT_SHA" =~ ^[0-9a-fA-F]{40,64}$ ]]; then
    echo "Could not resolve a valid source Git commit." >&2
    exit 2
  fi
  SOURCE_GIT_REF="$(git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "$SOURCE_GIT_REF" ]]; then
    SOURCE_GIT_REF="detached"
  fi
}

verify_canonical_source_tag() {
  [[ "$RELEASE_MODE" == "1" ]] || return 0

  local version local_tag_commit remote_tag_commit
  version="$(xcodebuild \
    -project "$ROOT_DIR/Shuo.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -onlyUsePackageVersionsFromResolvedFile \
    -disableAutomaticPackageResolution \
    -skipPackageUpdates \
    -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '$1 ~ /^[[:space:]]*MARKETING_VERSION$/ { print $2; exit }')"
  if [[ ! "$version" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]]; then
    echo "Could not resolve a safe release version from ShuoDirect build settings." >&2
    exit 2
  fi

  SOURCE_GIT_TAG="v$version"
  local_tag_commit="$(git -C "$ROOT_DIR" rev-parse --verify \
    "refs/tags/$SOURCE_GIT_TAG^{commit}" 2>/dev/null || true)"
  if [[ "$local_tag_commit" != "$SOURCE_GIT_SHA" ]]; then
    echo "Official release tag $SOURCE_GIT_TAG must point to source commit $SOURCE_GIT_SHA." >&2
    exit 2
  fi

  remote_tag_commit="$(git ls-remote "$CANONICAL_SOURCE_REPOSITORY" \
    "refs/tags/$SOURCE_GIT_TAG" \
    "refs/tags/$SOURCE_GIT_TAG^{}" 2>/dev/null \
    | awk -v tag="$SOURCE_GIT_TAG" '
        $2 == "refs/tags/" tag { direct = $1 }
        $2 == "refs/tags/" tag "^{}" { peeled = $1 }
        END {
          if (peeled != "") print peeled
          else print direct
        }
      ')"
  if [[ "$remote_tag_commit" != "$SOURCE_GIT_SHA" ]]; then
    echo "Canonical public tag $SOURCE_GIT_TAG is missing or does not resolve to $SOURCE_GIT_SHA." >&2
    echo "Push the reviewed source commit and tag to $CANONICAL_SOURCE_REPOSITORY before building an official RC." >&2
    exit 2
  fi

  if ! curl --fail --location --silent --show-error --head \
    "$CANONICAL_SOURCE_WEB/archive/refs/tags/$SOURCE_GIT_TAG.tar.gz" \
    >/dev/null; then
    echo "Canonical source archive is not anonymously reachable for $SOURCE_GIT_TAG." >&2
    exit 2
  fi
}

verify_resolved_sparkle_pin() {
  [[ "$RELEASE_MODE" == "1" ]] || return 0

  local package_file="$ROOT_DIR/Shuo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  [[ -f "$package_file" ]] || {
    echo "Official RCs require the committed Swift package resolution." >&2
    exit 2
  }

  if [[ "$(jq '.pins | length' "$package_file")" != "1" ]] \
      || [[ "$(jq -r '.pins[0].identity // empty' "$package_file")" != "sparkle" ]] \
      || [[ "$(jq -r '.pins[0].location // empty' "$package_file")" != "$PINNED_SPARKLE_REPOSITORY" ]] \
      || [[ "$(jq -r '.pins[0].state.version // empty' "$package_file")" != "$PINNED_SPARKLE_VERSION" ]] \
      || [[ "$(jq -r '.pins[0].state.revision // empty' "$package_file")" != "$PINNED_SPARKLE_REVISION" ]]; then
    echo "Official RCs require the reviewed Sparkle $PINNED_SPARKLE_VERSION package pin." >&2
    exit 2
  fi
}

verify_release_source_unchanged() {
  [[ "$RELEASE_MODE" == "1" ]] || return 0

  local current_sha source_status
  current_sha="$(git -C "$ROOT_DIR" rev-parse --verify HEAD)"
  source_status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)"
  if [[ "$current_sha" != "$SOURCE_GIT_SHA" || -n "$source_status" ]]; then
    echo "The source tree changed while the release candidate was being built; discarding staged artifacts." >&2
    exit 2
  fi
}

validate_release_output_directory() {
  local destination="$1"
  local private_destination="$2"
  [[ "$RELEASE_MODE" == "1" ]] || return 0

  local existing_artifact destination_path private_destination_path
  destination_path="$(cd "$destination" && pwd -P)"
  private_destination_path="$(cd "$private_destination" && pwd -P)"
  if [[ "$destination_path" == "$private_destination_path" ]]; then
    echo "SHUO_PRIVATE_ARTIFACT_DIR must be separate from the public release directory." >&2
    exit 2
  fi

  existing_artifact="$(find "$destination" \
    -mindepth 1 \
    -maxdepth 1 \
    -type f \
    \( \
      -name "$APP_NAME-*-macOS.zip" \
      -o -name "$APP_NAME-*-macOS.dmg" \
      -o -name "$APP_NAME-*-macOS.sha256" \
      -o -name "$APP_NAME-*-macOS.manifest.json" \
    \) \
    -print \
    -quit)"
  if [[ -n "$existing_artifact" ]]; then
    echo "Release output directory already contains a versioned artifact: $existing_artifact" >&2
    echo "Archive or remove earlier development/RC artifacts before creating a new release candidate." >&2
    exit 2
  fi

  existing_artifact="$(find "$destination" \
    -mindepth 1 \
    -maxdepth 1 \
    -type f \
    -name "$APP_NAME-*-macOS-symbols.zip" \
    -print \
    -quit)"
  if [[ -n "$existing_artifact" ]]; then
    echo "Private dSYM archives must not be stored in the public release directory: $existing_artifact" >&2
    exit 2
  fi

  existing_artifact="$(find "$private_destination" \
    -mindepth 1 \
    -maxdepth 1 \
    -type f \
    -name "$APP_NAME-*-macOS-symbols.zip" \
    -print \
    -quit)"
  if [[ -n "$existing_artifact" ]]; then
    echo "Private release output already contains a versioned symbols archive: $existing_artifact" >&2
    echo "Archive or remove the earlier private RC artifact before creating a new release candidate." >&2
    exit 2
  fi
}

prepare_release_derived_data() {
  [[ "$RELEASE_MODE" == "1" ]] || return 0

  if [[ -z "$RELEASE_STAGING_DIR" || ! -d "$RELEASE_STAGING_DIR" ]]; then
    echo "Release runtime isolation requires a fresh staging directory." >&2
    exit 2
  fi

  local temporary_root existing_entry
  temporary_root="${TMPDIR:-/tmp}"
  RELEASE_TEMP_DERIVED_DATA="$(mktemp -d "${temporary_root%/}/shuo-release-derived.XXXXXX")"
  existing_entry="$(find "$RELEASE_TEMP_DERIVED_DATA" -mindepth 1 -print -quit)"
  if [[ -n "$existing_entry" ]]; then
    echo "Fresh release DerivedData unexpectedly contained stale build output: $existing_entry" >&2
    exit 2
  fi

  DERIVED_DATA="$RELEASE_TEMP_DERIVED_DATA"
  APP_SOURCE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
  export SHUO_WHISPER_CPP_VERSION="$PINNED_WHISPER_CPP_VERSION"
  export SHUO_WHISPER_CPP_SHA256="$PINNED_WHISPER_CPP_SHA256"
  export SHUO_WHISPER_ARCHITECTURES='arm64;x86_64'
  export SHUO_WHISPER_RUNTIME_CACHE="$RELEASE_STAGING_DIR/whisper-runtime"
}

cleanup_release_workspaces() {
  [[ -z "$RELEASE_STAGING_DIR" ]] || rm -rf "$RELEASE_STAGING_DIR"
  [[ -z "$RELEASE_TEMP_DERIVED_DATA" ]] || rm -rf "$RELEASE_TEMP_DERIVED_DATA"
}

validate_release_configuration() {
  [[ "$RELEASE_MODE" == "1" ]] || return 0

  capture_release_source_state

  if [[ "$FORMAT" != "all" ]]; then
    echo "SHUO_RELEASE=1 requires packaging both ZIP and DMG (format: all)." >&2
    exit 2
  fi
  if [[ "$CONFIGURATION" != "Release" ]]; then
    echo "SHUO_RELEASE=1 requires SHUO_CONFIGURATION=Release." >&2
    exit 2
  fi
  if [[ "$SCHEME" != "ShuoDirect" ]]; then
    echo "SHUO_RELEASE=1 requires SHUO_SCHEME=ShuoDirect." >&2
    exit 2
  fi
  if [[ "$APP_NAME" != "Shuo" ]]; then
    echo "SHUO_RELEASE=1 requires SHUO_APP_NAME=Shuo." >&2
    exit 2
  fi
  if [[ "$SIGN_MODE" != "identity" ]]; then
    echo "SHUO_RELEASE=1 requires SHUO_SIGN_MODE=identity." >&2
    exit 2
  fi
  if [[ "$NOTARIZE" != "1" ]]; then
    echo "SHUO_RELEASE=1 requires SHUO_NOTARIZE=1." >&2
    exit 2
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "SHUO_RELEASE=1 requires a non-empty SHUO_NOTARY_PROFILE." >&2
    exit 2
  fi
  if [[ "$SIGN_IDENTITY" != Developer\ ID\ Application:*"($EXPECTED_TEAM_ID)" ]]; then
    echo "Release identity must be a Developer ID Application certificate for team $EXPECTED_TEAM_ID." >&2
    exit 2
  fi
  if [[ "${SHUO_WHISPER_ARCHITECTURES:-arm64;x86_64}" != "arm64;x86_64" ]]; then
    echo "Release whisper runtime must use SHUO_WHISPER_ARCHITECTURES=arm64;x86_64." >&2
    exit 2
  fi
  if [[ "${SHUO_WHISPER_CPP_VERSION:-$PINNED_WHISPER_CPP_VERSION}" != "$PINNED_WHISPER_CPP_VERSION" ]]; then
    echo "Release whisper.cpp version must be $PINNED_WHISPER_CPP_VERSION." >&2
    exit 2
  fi
  if [[ "${SHUO_WHISPER_CPP_SHA256:-$PINNED_WHISPER_CPP_SHA256}" != "$PINNED_WHISPER_CPP_SHA256" ]]; then
    echo "Release whisper.cpp source hash must match the pinned 1.8.6 archive." >&2
    exit 2
  fi
  if [[ -n "${SHUO_WHISPER_RUNTIME_CACHE:-}" ]]; then
    echo "Official RCs do not accept a caller-provided whisper runtime cache." >&2
    exit 2
  fi
  if [[ "$ENTITLEMENTS" != "$PINNED_RELEASE_ENTITLEMENTS" ]] \
      || [[ "$(shasum -a 256 "$ENTITLEMENTS" 2>/dev/null | awk '{print $1}')" != "$PINNED_RELEASE_ENTITLEMENTS_SHA256" ]]; then
    echo "Official RCs require the pinned App/ShuoDirect.entitlements file." >&2
    exit 2
  fi

  local command_name
  for command_name in cmake cmp codesign curl ditto file hdiutil jq lipo security shasum spctl xcodebuild xcrun; do
    require_command "$command_name"
  done

  verify_resolved_sparkle_pin
  verify_canonical_source_tag

  local available_identities
  available_identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if ! grep -Fq "\"$SIGN_IDENTITY\"" <<<"$available_identities"; then
    echo "Developer ID signing identity is unavailable: $SIGN_IDENTITY" >&2
    exit 2
  fi

  local notary_check
  notary_check="$(mktemp /tmp/shuo-notary-profile.XXXXXX)"
  if ! xcrun notarytool history \
    --keychain-profile "$NOTARY_PROFILE" \
    --output-format json >"$notary_check" 2>&1; then
    echo "Notary profile '$NOTARY_PROFILE' is missing or cannot authenticate." >&2
    cat "$notary_check" >&2
    rm -f "$notary_check"
    exit 2
  fi
  rm -f "$notary_check"
}

submit_for_notarization() {
  local artifact_path="$1"
  local artifact_label="$2"
  local response_path status submission_id

  response_path="$(mktemp /tmp/shuo-notary-response.XXXXXX)"
  if ! xcrun notarytool submit "$artifact_path" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format json >"$response_path"; then
    cat "$response_path" >&2
    rm -f "$response_path"
    return 1
  fi

  if ! status="$(jq -r '.status // empty' "$response_path")" \
    || ! submission_id="$(jq -r '.id // empty' "$response_path")"; then
    echo "$artifact_label notarization returned an unreadable response." >&2
    cat "$response_path" >&2
    rm -f "$response_path"
    return 1
  fi
  if [[ "$status" != "Accepted" ]]; then
    echo "$artifact_label notarization was not accepted (status: ${status:-unknown})." >&2
    cat "$response_path" >&2
    if [[ -n "$submission_id" ]]; then
      xcrun notarytool log "$submission_id" \
        --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    rm -f "$response_path"
    return 1
  fi

  echo "$artifact_label notarization accepted: $submission_id"
  rm -f "$response_path"
}

notarize_app_bundle() {
  [[ "$NOTARIZE" == "1" ]] || return 0
  if [[ "$SIGN_MODE" != "identity" ]]; then
    echo "SHUO_NOTARIZE=1 requires SHUO_SIGN_MODE=identity." >&2
    exit 2
  fi

  local submission_dir submission_zip
  submission_dir="$(mktemp -d /tmp/shuo-notary.XXXXXX)"
  submission_zip="$submission_dir/$APP_NAME.zip"
  ditto -c -k --keepParent "$APP_SOURCE" "$submission_zip"
  if ! submit_for_notarization "$submission_zip" "$APP_NAME.app"; then
    rm -rf "$submission_dir"
    return 1
  fi
  rm -rf "$submission_dir"
  xcrun stapler staple "$APP_SOURCE"
  xcrun stapler validate "$APP_SOURCE"
}

notarize_disk_image() {
  local dmg_path="$1"
  [[ "$NOTARIZE" == "1" ]] || return 0

  submit_for_notarization "$dmg_path" "$(basename "$dmg_path")"
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
}

sign_disk_image() {
  local dmg_path="$1"
  [[ "$SIGN_MODE" == "identity" ]] || return 0

  codesign \
    --force \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$dmg_path"
  codesign --verify --strict --verbose=2 "$dmg_path"
}

sign_nested_sparkle_code() {
  local identity="$1"
  local timestamp_mode="$2"
  local sparkle="$APP_SOURCE/Contents/Frameworks/Sparkle.framework"

  [[ -d "$sparkle" ]] || return 0

  local timestamp_args=()
  if [[ "$timestamp_mode" == "timestamp" ]]; then
    timestamp_args+=(--timestamp)
  else
    timestamp_args+=(--timestamp=none)
  fi

  codesign --force --options runtime "${timestamp_args[@]}" --sign "$identity" \
    "$sparkle/Versions/B/XPCServices/Installer.xpc"
  codesign --force --options runtime --preserve-metadata=entitlements \
    "${timestamp_args[@]}" --sign "$identity" \
    "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --options runtime "${timestamp_args[@]}" --sign "$identity" \
    "$sparkle/Versions/B/Autoupdate"
  codesign --force --options runtime "${timestamp_args[@]}" --sign "$identity" \
    "$sparkle/Versions/B/Updater.app"
  codesign --force --options runtime "${timestamp_args[@]}" --sign "$identity" \
    "$sparkle"
}

sign_app_bundle() {
  local identity="$1"
  local timestamp_mode="$2"
  local timestamp_args=()
  local signing_entitlements="$ENTITLEMENTS"
  local temporary_entitlements=""

  if [[ "$timestamp_mode" == "timestamp" ]]; then
    timestamp_args+=(--timestamp)
  else
    timestamp_args+=(--timestamp=none)
  fi

  # Ad-hoc and self-signed builds have no common Apple Team ID. Hardened
  # Runtime would otherwise reject Sparkle at launch even though every nested
  # signature verifies successfully. Developer ID builds keep library
  # validation enabled and rely on their real shared Team ID.
  if [[ "$SIGN_MODE" != "identity" ]]; then
    temporary_entitlements="$(mktemp)"
    cp "$ENTITLEMENTS" "$temporary_entitlements"
    /usr/libexec/PlistBuddy \
      -c 'Delete :com.apple.security.cs.disable-library-validation' \
      "$temporary_entitlements" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy \
      -c 'Add :com.apple.security.cs.disable-library-validation bool true' \
      "$temporary_entitlements"
    signing_entitlements="$temporary_entitlements"
  fi

  sign_nested_sparkle_code "$identity" "$timestamp_mode"
  if [[ -x "$APP_SOURCE/Contents/Resources/Runtime/whisper-cli" ]]; then
    codesign --force --options runtime "${timestamp_args[@]}" --sign "$identity" \
      "$APP_SOURCE/Contents/Resources/Runtime/whisper-cli"
  fi
  if ! codesign \
    --force \
    --options runtime \
    --entitlements "$signing_entitlements" \
    "${timestamp_args[@]}" \
    --sign "$identity" \
    "$APP_SOURCE"; then
    rm -f "$temporary_entitlements"
    return 1
  fi

  rm -f "$temporary_entitlements"
}

verify_test_signing_entitlements() {
  [[ "$SIGN_MODE" != "identity" ]] || return 0

  local extracted_entitlements library_validation_disabled
  extracted_entitlements="$(mktemp)"
  codesign -d --entitlements - --xml "$APP_SOURCE" \
    > "$extracted_entitlements" 2>/dev/null
  library_validation_disabled="$(
    /usr/libexec/PlistBuddy \
      -c 'Print :com.apple.security.cs.disable-library-validation' \
      "$extracted_entitlements" 2>/dev/null || true
  )"
  rm -f "$extracted_entitlements"

  if [[ "$library_validation_disabled" != "true" ]]; then
    echo "Test package is missing the library-validation exception required by Sparkle." >&2
    exit 1
  fi
}

ensure_local_codesign_identity() {
  if security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
    return
  fi

  echo "Creating local code signing identity: $SIGN_IDENTITY"
  local work_dir
  work_dir="$(mktemp -d)"

  cat > "$work_dir/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no

[ dn ]
CN = $SIGN_IDENTITY

[ ext ]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

  openssl req \
    -new \
    -newkey rsa:2048 \
    -nodes \
    -x509 \
    -days 3650 \
    -sha256 \
    -config "$work_dir/openssl.cnf" \
    -keyout "$work_dir/key.pem" \
    -out "$work_dir/cert.pem" >/dev/null 2>&1

  openssl pkcs12 \
    -export \
    -inkey "$work_dir/key.pem" \
    -in "$work_dir/cert.pem" \
    -out "$work_dir/identity.p12" \
    -passout "pass:$PKCS12_PASSWORD" >/dev/null 2>&1

  security import "$work_dir/identity.p12" \
    -k "$KEYCHAIN" \
    -P "$PKCS12_PASSWORD" \
    -f pkcs12 \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null

  security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN" \
    "$work_dir/cert.pem" >/dev/null 2>&1 || true

  rm -rf "$work_dir"
}

build_app() {
  # Keep this array non-empty for macOS's Bash 3.2 under `set -u`; expanding an
  # empty local array otherwise raises "unbound variable" for test packages.
  local release_build_settings=('ONLY_ACTIVE_ARCH=NO')
  if [[ "$RELEASE_MODE" == "1" ]]; then
    release_build_settings+=(
      'ARCHS=arm64 x86_64'
    )
  fi

  xcodebuild \
    -quiet \
    -project "$ROOT_DIR/Shuo.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -onlyUsePackageVersionsFromResolvedFile \
    -disableAutomaticPackageResolution \
    -skipPackageUpdates \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    "${release_build_settings[@]}" \
    build
}

embed_distribution_notices() {
  local resources="$APP_SOURCE/Contents/Resources"
  local version source_tag source_url source_commit_url tagged_commit

  mkdir -p "$resources"
  cp "$ROOT_DIR/LICENSE" "$resources/LICENSE"

  if [[ "$RELEASE_MODE" != "1" ]]; then
    return 0
  fi

  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP_SOURCE/Contents/Info.plist")"
  source_tag="${SOURCE_GIT_TAG:-v$version}"
  source_url="$CANONICAL_SOURCE_WEB/tree/$source_tag"
  source_commit_url="$CANONICAL_SOURCE_WEB/tree/$SOURCE_GIT_SHA"
  tagged_commit="$(git -C "$ROOT_DIR" rev-parse --verify "refs/tags/$source_tag^{commit}" 2>/dev/null || true)"
  if [[ "$tagged_commit" != "$SOURCE_GIT_SHA" ]]; then
    echo "Official release tag $source_tag must point to source commit $SOURCE_GIT_SHA." >&2
    exit 2
  fi

  {
    printf 'Shuo Corresponding Source\n\n'
    printf 'License: GPL-3.0-only\n'
    printf 'Release tag: %s\n' "$source_tag"
    printf 'Tagged source: %s\n' "$source_url"
    printf 'Source archive: %s/archive/refs/tags/%s.tar.gz\n' \
      "$CANONICAL_SOURCE_WEB" "$source_tag"
    printf 'Source commit: %s\n' "$SOURCE_GIT_SHA"
    printf 'Exact source: %s\n' "$source_commit_url"
    printf '\nThe tagged source and this binary must resolve to the same commit.\n'
  } >"$resources/CORRESPONDING_SOURCE.txt"
}

sign_app() {
  case "$SIGN_MODE" in
    adhoc)
      sign_app_bundle - no-timestamp
      ;;
    local)
      ensure_local_codesign_identity
      sign_app_bundle "$SIGN_IDENTITY" no-timestamp
      ;;
    identity)
      sign_app_bundle "$SIGN_IDENTITY" timestamp
      ;;
    *)
      echo "Unknown SHUO_SIGN_MODE '$SIGN_MODE'. Use 'adhoc', 'local', or 'identity'." >&2
      exit 2
      ;;
  esac

  codesign --verify --deep --strict --verbose=2 "$APP_SOURCE"
  verify_test_signing_entitlements
}

package_basename() {
  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_SOURCE/Contents/Info.plist" 2>/dev/null || true)"
  if [[ -z "$version" ]]; then
    version="dev"
  fi

  echo "$APP_NAME-$version-macOS"
}

create_zip() {
  local basename zip_path latest_zip_path
  basename="$(package_basename)"
  zip_path="$PACKAGE_DIR/$basename.zip"
  latest_zip_path="$PACKAGE_DIR/$APP_NAME-latest-macOS.zip"

  rm -f "$zip_path" "$latest_zip_path"
  ditto -c -k --sequesterRsrc --keepParent "$APP_SOURCE" "$zip_path"
  cp "$zip_path" "$latest_zip_path"
  echo "Created: $zip_path"
  echo "Created: $latest_zip_path"
}

generate_dmg_background_assets() {
  if [[ "$RELEASE_MODE" == "1" ]]; then
    [[ -s "$ROOT_DIR/Packaging/DMG/background.png" \
        && -s "$ROOT_DIR/Packaging/DMG/background@2x.png" ]] || {
      echo "Formal releases require the committed DMG background assets." >&2
      exit 2
    }
    return 0
  fi

  swift \
    "$ROOT_DIR/Scripts/generate-dmg-background.swift" \
    "$ROOT_DIR/Packaging/DMG"
}

create_dmg() (
  local basename dmg_path latest_dmg_path work_dir rw_dmg mount_dir
  local app_size_kb image_size_mb
  basename="$(package_basename)"
  dmg_path="$PACKAGE_DIR/$basename.dmg"
  latest_dmg_path="$PACKAGE_DIR/$APP_NAME-latest-macOS.dmg"
  work_dir="$(mktemp -d /tmp/shuo-dmg.XXXXXX)"
  rw_dmg="$work_dir/$APP_NAME-rw.dmg"
  mount_dir="$work_dir/mount"
  mkdir -p "$mount_dir"

  generate_dmg_background_assets

  app_size_kb="$(du -sk "$APP_SOURCE" | awk '{ print $1 }')"
  image_size_mb="$((app_size_kb / 1024 + 32))"
  if ((image_size_mb < 48)); then
    image_size_mb=48
  fi

  rm -f "$dmg_path" "$latest_dmg_path"
  hdiutil create \
    -size "${image_size_mb}m" \
    -fs HFS+ \
    -volname "$APP_NAME" \
    -ov \
    -nospotlight \
    "$rw_dmg" >/dev/null

  local is_mounted=0
  cleanup_dmg_working_files() {
    if [[ "$is_mounted" == "1" ]]; then
      hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    fi
    rm -rf "$work_dir"
  }
  trap cleanup_dmg_working_files EXIT

  hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$mount_dir" \
    "$rw_dmg" >/dev/null
  is_mounted=1

  ditto "$APP_SOURCE" "$mount_dir/$APP_NAME.app"
  ln -s /Applications "$mount_dir/Applications"
  mkdir -p "$mount_dir/.background"
  ditto \
    "$ROOT_DIR/Packaging/DMG/background.png" \
    "$mount_dir/.background/background.png"
  ditto \
    "$ROOT_DIR/Packaging/DMG/background@2x.png" \
    "$mount_dir/.background/background@2x.png"
  /usr/bin/SetFile -a V "$mount_dir/.background"

  if [[ -f "$APP_SOURCE/Contents/Resources/AppIcon.icns" ]]; then
    ditto \
      "$APP_SOURCE/Contents/Resources/AppIcon.icns" \
      "$mount_dir/.VolumeIcon.icns"
    /usr/bin/SetFile -a V "$mount_dir/.VolumeIcon.icns"
    /usr/bin/SetFile -a C "$mount_dir"
  fi

  osascript - "$mount_dir" "$APP_NAME.app" <<'APPLESCRIPT'
on run arguments
  set mountPath to item 1 of arguments
  set appItemName to item 2 of arguments

  tell application "Finder"
    set mountedDisk to disk of (POSIX file mountPath as alias)
    tell mountedDisk
      open
      delay 0.5

      set installerWindow to container window
      set current view of installerWindow to icon view
      set toolbar visible of installerWindow to false
      set statusbar visible of installerWindow to false
      set pathbar visible of installerWindow to false
      set sidebar width of installerWindow to 0
      set bounds of installerWindow to {160, 120, 880, 560}

      set iconOptions to icon view options of installerWindow
      set arrangement of iconOptions to not arranged
      set icon size of iconOptions to 112
      set text size of iconOptions to 13
      set label position of iconOptions to bottom
      set shows icon preview of iconOptions to false
      set background picture of iconOptions to file ".background:background.png"

      set extension hidden of item appItemName to true
      set position of item appItemName to {185, 235}
      set position of item "Applications" to {535, 235}
      update without registering applications
      delay 2
      close installerWindow
    end tell
  end tell
end run
APPLESCRIPT

  sync
  if [[ ! -f "$mount_dir/.DS_Store" ]]; then
    echo "Finder did not create the DMG layout metadata." >&2
    exit 1
  fi

  rm -rf \
    "$mount_dir/.fseventsd" \
    "$mount_dir/.Spotlight-V100" \
    "$mount_dir/.Trashes"
  sync
  hdiutil detach "$mount_dir" >/dev/null
  is_mounted=0

  hdiutil convert \
    "$rw_dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$dmg_path" >/dev/null
  hdiutil verify "$dmg_path" >/dev/null

  sign_disk_image "$dmg_path"
  notarize_disk_image "$dmg_path"
  cp "$dmg_path" "$latest_dmg_path"
  trap - EXIT
  cleanup_dmg_working_files
  echo "Created: $dmg_path"
  echo "Created: $latest_dmg_path"
)

create_release_checksum_manifest() {
  local basename zip_name dmg_name checksum_path temporary_path
  basename="$(package_basename)"
  zip_name="$basename.zip"
  dmg_name="$basename.dmg"
  checksum_path="$PACKAGE_DIR/$basename.sha256"
  temporary_path="$checksum_path.tmp"

  rm -f "$checksum_path" "$temporary_path"
  (
    cd "$PACKAGE_DIR"
    shasum -a 256 "$zip_name" "$dmg_name"
  ) >"$temporary_path"
  mv "$temporary_path" "$checksum_path"
  echo "Created: $checksum_path"
}

create_release_symbols_archive() {
  local basename symbols_source symbols_path
  basename="$(package_basename)"
  symbols_source="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app.dSYM"
  symbols_path="$PRIVATE_ARTIFACT_DIR/$basename-symbols.zip"

  [[ -d "$symbols_source" ]] || {
    echo "Release build did not produce $APP_NAME.app.dSYM." >&2
    exit 2
  }
  rm -f "$symbols_path"
  ditto -c -k --keepParent "$symbols_source" "$symbols_path"
  echo "Created private symbols archive: $symbols_path"
}

create_release_manifest() {
  local basename zip_name dmg_name manifest_path temporary_path
  local info_plist version build_number bundle_id zip_sha dmg_sha symbols_name symbols_sha
  basename="$(package_basename)"
  zip_name="$basename.zip"
  dmg_name="$basename.dmg"
  symbols_name="$basename-symbols.zip"
  manifest_path="$PACKAGE_DIR/$basename.manifest.json"
  temporary_path="$manifest_path.tmp"
  info_plist="$APP_SOURCE/Contents/Info.plist"
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
  build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
  zip_sha="$(shasum -a 256 "$PACKAGE_DIR/$zip_name" | awk '{ print $1 }')"
  dmg_sha="$(shasum -a 256 "$PACKAGE_DIR/$dmg_name" | awk '{ print $1 }')"
  symbols_sha="$(shasum -a 256 "$PRIVATE_ARTIFACT_DIR/$symbols_name" | awk '{ print $1 }')"

  rm -f "$manifest_path" "$temporary_path"
  jq -n \
    --arg product "$APP_NAME" \
    --arg bundle_id "$bundle_id" \
    --arg version "$version" \
    --arg build "$build_number" \
    --arg git_sha "$SOURCE_GIT_SHA" \
    --arg git_ref "$SOURCE_GIT_REF" \
    --arg source_repository "$CANONICAL_SOURCE_REPOSITORY" \
    --arg source_tag "$SOURCE_GIT_TAG" \
    --arg sparkle_repository "$PINNED_SPARKLE_REPOSITORY" \
    --arg sparkle_version "$PINNED_SPARKLE_VERSION" \
    --arg sparkle_revision "$PINNED_SPARKLE_REVISION" \
    --arg whisper_version "$PINNED_WHISPER_CPP_VERSION" \
    --arg whisper_source_sha256 "$PINNED_WHISPER_CPP_SHA256" \
    --arg zip_filename "$zip_name" \
    --arg zip_sha256 "$zip_sha" \
    --arg dmg_filename "$dmg_name" \
    --arg dmg_sha256 "$dmg_sha" \
    --arg symbols_filename "$symbols_name" \
    --arg symbols_sha256 "$symbols_sha" \
    '{
      schema_version: 1,
      product: $product,
      bundle_id: $bundle_id,
      version: $version,
      build: $build,
      source: {
        repository: $source_repository,
        tag: $source_tag,
        git_sha: $git_sha,
        git_ref: $git_ref
      },
      dependencies: {
        sparkle: {
          repository: $sparkle_repository,
          version: $sparkle_version,
          revision: $sparkle_revision
        },
        whisper_cpp: {
          version: $whisper_version,
          source_sha256: $whisper_source_sha256
        }
      },
      artifacts: {
        zip: {filename: $zip_filename, sha256: $zip_sha256},
        dmg: {filename: $dmg_filename, sha256: $dmg_sha256},
        symbols: {
          filename: $symbols_filename,
          path: ("private/" + $symbols_filename),
          sha256: $symbols_sha256,
          visibility: "private"
        }
      }
    }' >"$temporary_path"
  mv "$temporary_path" "$manifest_path"
  echo "Created: $manifest_path"
}

verify_release_artifacts() {
  local basename
  basename="$(package_basename)"
  "$ROOT_DIR/Scripts/verify-release-artifacts.sh" \
    "$APP_SOURCE" \
    "$PACKAGE_DIR/$basename.zip" \
    "$PACKAGE_DIR/$basename.dmg" \
    "$PACKAGE_DIR/$basename.sha256" \
    "$PACKAGE_DIR/$basename.manifest.json" \
    "$PRIVATE_ARTIFACT_DIR/$basename-symbols.zip"
}

publish_staged_release_artifacts() {
  local destination="$1"
  local private_destination="$2"
  local basename temporary_suffix file target temporary_target cleanup_file
  basename="$(package_basename)"
  temporary_suffix=".shuo-publish.$$"
  # This is the complete public-release allowlist. Never replace it with a
  # wildcard: private symbols live in a separate directory by design.
  local public_files=(
    "$basename.zip"
    "$basename.dmg"
    "$basename.sha256"
    "$basename.manifest.json"
    "$APP_NAME-latest-macOS.zip"
    "$APP_NAME-latest-macOS.dmg"
  )
  local private_files=(
    "$basename-symbols.zip"
  )

  for file in "${public_files[@]:0:4}"; do
    target="$destination/$file"
    if [[ -e "$target" ]]; then
      echo "Refusing to overwrite existing versioned release artifact: $target" >&2
      exit 2
    fi
  done
  for file in "${private_files[@]}"; do
    target="$private_destination/$file"
    if [[ -e "$target" ]]; then
      echo "Refusing to overwrite existing private release artifact: $target" >&2
      exit 2
    fi
  done

  for file in "${public_files[@]}"; do
    temporary_target="$destination/.$file$temporary_suffix"
    rm -f "$temporary_target"
    if ! cp "$PACKAGE_DIR/$file" "$temporary_target"; then
      for cleanup_file in "${public_files[@]}"; do
        rm -f "$destination/.$cleanup_file$temporary_suffix"
      done
      echo "Could not stage verified release artifacts for publication." >&2
      exit 2
    fi
  done
  for file in "${private_files[@]}"; do
    temporary_target="$private_destination/.$file$temporary_suffix"
    rm -f "$temporary_target"
    if ! cp "$PRIVATE_ARTIFACT_DIR/$file" "$temporary_target"; then
      for cleanup_file in "${public_files[@]}"; do
        rm -f "$destination/.$cleanup_file$temporary_suffix"
      done
      for cleanup_file in "${private_files[@]}"; do
        rm -f "$private_destination/.$cleanup_file$temporary_suffix"
      done
      echo "Could not stage the verified private symbols archive." >&2
      exit 2
    fi
  done

  for file in "${public_files[@]}"; do
    temporary_target="$destination/.$file$temporary_suffix"
    if ! cmp -s "$PACKAGE_DIR/$file" "$temporary_target"; then
      for cleanup_file in "${public_files[@]}"; do
        rm -f "$destination/.$cleanup_file$temporary_suffix"
      done
      for cleanup_file in "${private_files[@]}"; do
        rm -f "$private_destination/.$cleanup_file$temporary_suffix"
      done
      echo "A copied release artifact did not match its verified staging file." >&2
      exit 2
    fi
  done
  for file in "${private_files[@]}"; do
    temporary_target="$private_destination/.$file$temporary_suffix"
    if ! cmp -s "$PRIVATE_ARTIFACT_DIR/$file" "$temporary_target"; then
      for cleanup_file in "${public_files[@]}"; do
        rm -f "$destination/.$cleanup_file$temporary_suffix"
      done
      for cleanup_file in "${private_files[@]}"; do
        rm -f "$private_destination/.$cleanup_file$temporary_suffix"
      done
      echo "The copied private symbols archive did not match its verified staging file." >&2
      exit 2
    fi
  done

  for file in "${private_files[@]}"; do
    temporary_target="$private_destination/.$file$temporary_suffix"
    mv -f "$temporary_target" "$private_destination/$file"
  done
  for file in "${public_files[@]}"; do
    temporary_target="$destination/.$file$temporary_suffix"
    mv -f "$temporary_target" "$destination/$file"
  done

  echo "Published verified release candidate artifacts to: $destination"
  echo "Published private symbols archive to: $private_destination"
}

main() {
  case "$FORMAT" in
    zip | dmg | all | --help | -h)
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac

  if [[ "$FORMAT" == "--help" || "$FORMAT" == "-h" ]]; then
    usage
    exit 0
  fi

  if [[ "$RELEASE_MODE" != "0" && "$RELEASE_MODE" != "1" ]]; then
    echo "SHUO_RELEASE must be 0 or 1." >&2
    exit 2
  fi

  validate_release_configuration

  local final_package_dir="$PACKAGE_DIR"
  local final_private_artifact_dir="$PRIVATE_ARTIFACT_DIR"
  mkdir -p "$final_package_dir"
  if [[ "$RELEASE_MODE" == "1" ]]; then
    mkdir -p "$final_private_artifact_dir"
    validate_release_output_directory "$final_package_dir" "$final_private_artifact_dir"
    RELEASE_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shuo-release-stage.XXXXXX")"
    PACKAGE_DIR="$RELEASE_STAGING_DIR/public"
    PRIVATE_ARTIFACT_DIR="$RELEASE_STAGING_DIR/private"
    mkdir -p "$PACKAGE_DIR" "$PRIVATE_ARTIFACT_DIR"
    trap cleanup_release_workspaces EXIT
    prepare_release_derived_data
  fi

  echo "Packaging $APP_NAME ($CONFIGURATION, sign mode: $SIGN_MODE)"
  build_app
  "$ROOT_DIR/Scripts/embed-whisper-runtime.sh" "$APP_SOURCE"
  embed_distribution_notices
  sign_app
  notarize_app_bundle

  case "$FORMAT" in
    zip)
      create_zip
      ;;
    dmg)
      create_dmg
      ;;
    all)
      create_zip
      create_dmg
      ;;
  esac

  if [[ "$RELEASE_MODE" == "1" ]]; then
    create_release_symbols_archive
    create_release_checksum_manifest
    create_release_manifest
    verify_release_artifacts
    verify_release_source_unchanged
    publish_staged_release_artifacts "$final_package_dir" "$final_private_artifact_dir"
    trap - EXIT
    cleanup_release_workspaces
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
