#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/Scripts/package-app.sh"
VERIFY_SCRIPT="$ROOT_DIR/Scripts/verify-release-artifacts.sh"
APPCAST_SCRIPT="$ROOT_DIR/Scripts/generate-appcast.sh"
WHISPER_PREPARE_SCRIPT="$ROOT_DIR/Scripts/prepare-whisper-runtime.sh"
EXPORT_TEST_SCRIPT="$ROOT_DIR/Tests/Scripts/export-public-tests.sh"
TEST_IDENTITY='Developer ID Application: Release Test (4GQ47468NJ)'
WORK_DIR="$(mktemp -d /tmp/shuo-release-packaging-tests.XXXXXX)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
  echo "Release packaging test failed: $*" >&2
  exit 1
}

assert_failure_contains() {
  local expected="$1"
  shift
  local output status

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "command unexpectedly succeeded: $*"
  grep -Fq "$expected" <<<"$output" \
    || fail "failure did not contain '$expected': $output"
}

assert_failure() {
  local status

  set +e
  "$@" >/dev/null 2>&1
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "command unexpectedly succeeded: $*"
}

run_preflight() (
  export SHUO_RELEASE="${TEST_RELEASE_MODE:-1}"
  export SHUO_SIGN_MODE="${TEST_SIGN_MODE:-identity}"
  export SHUO_CODESIGN_IDENTITY="${TEST_SIGN_IDENTITY-$TEST_IDENTITY}"
  export SHUO_NOTARIZE="${TEST_NOTARIZE:-1}"
  export SHUO_NOTARY_PROFILE="${TEST_NOTARY_PROFILE-Shuo-Notary}"
  export SHUO_CONFIGURATION="${TEST_CONFIGURATION:-Release}"
  export SHUO_SCHEME="${TEST_SCHEME:-ShuoDirect}"
  export SHUO_APP_NAME="${TEST_APP_NAME:-Shuo}"
  export SHUO_WHISPER_ARCHITECTURES="${TEST_ARCHITECTURES:-arm64;x86_64}"
  export SHUO_ENTITLEMENTS="${TEST_ENTITLEMENTS:-$ROOT_DIR/App/ShuoDirect.entitlements}"
  unset SHUO_WHISPER_CPP_VERSION SHUO_WHISPER_CPP_SHA256 SHUO_WHISPER_RUNTIME_CACHE
  [[ -z "${TEST_WHISPER_VERSION:-}" ]] \
    || export SHUO_WHISPER_CPP_VERSION="$TEST_WHISPER_VERSION"
  [[ -z "${TEST_WHISPER_SHA256:-}" ]] \
    || export SHUO_WHISPER_CPP_SHA256="$TEST_WHISPER_SHA256"
  [[ -z "${TEST_WHISPER_CACHE:-}" ]] \
    || export SHUO_WHISPER_RUNTIME_CACHE="$TEST_WHISPER_CACHE"
  set -- all
  # shellcheck source=../../Scripts/package-app.sh
  source "$PACKAGE_SCRIPT"

  git() {
    case "$*" in
      *'rev-parse --is-inside-work-tree'*)
        echo true
        ;;
      *'status --porcelain --untracked-files=all'*)
        if [[ "${TEST_GIT_DIRTY:-0}" == "1" ]]; then
          echo ' M App/Test.swift'
        fi
        ;;
      *'rev-parse --verify HEAD'*)
        printf '%040d\n' 1
        ;;
      *'rev-parse --verify refs/tags/v1.0.0^{commit}'*)
        printf '%s\n' "${TEST_LOCAL_TAG_SHA:-$(printf '%040d' 1)}"
        ;;
      *'symbolic-ref --quiet --short HEAD'*)
        echo main
        ;;
      *'ls-remote https://github.com/stcheng/shuo.git refs/tags/v1.0.0'*)
        printf '%s\trefs/tags/v1.0.0\n' \
          "${TEST_REMOTE_TAG_SHA:-$(printf '%040d' 1)}"
        ;;
      *)
        return 1
        ;;
    esac
  }

  xcodebuild() {
    printf '    MARKETING_VERSION = 1.0.0\n'
  }

  curl() {
    [[ "${TEST_ARCHIVE_FAILURE:-0}" != "1" ]]
  }

  security() {
    if [[ "${TEST_SECURITY_FAILURE:-0}" == "1" ]]; then
      echo "0 valid identities found"
    else
      echo "  1) ABCDEF \"$TEST_IDENTITY\""
      echo "     1 valid identities found"
    fi
  }

  xcrun() {
    if [[ "${TEST_NOTARY_FAILURE:-0}" == "1" ]]; then
      echo "No Keychain password item found for profile" >&2
      return 1
    fi
    printf '{"history": []}\n'
  }

  validate_release_configuration
)

run_submission() (
  local test_status="${1:-Accepted}"
  export SHUO_NOTARY_PROFILE='Shuo-Notary'
  set -- all
  # shellcheck source=../../Scripts/package-app.sh
  source "$PACKAGE_SCRIPT"

  xcrun() {
    if [[ "${2:-}" == "submit" ]]; then
      if [[ "$test_status" == "Malformed" ]]; then
        echo 'not-json'
      else
        printf '{"id":"test-submission","status":"%s"}\n' "$test_status"
      fi
      return 0
    fi
    if [[ "${2:-}" == "log" ]]; then
      echo '{"issues":[]}'
      return 0
    fi
    return 1
  }

  submit_for_notarization '/tmp/fake-release-artifact.zip' 'Test artifact'
)

run_manifest_and_staging_test() (
  local fixture="$WORK_DIR/release-stage"
  local derived_data="$fixture/DerivedData"
  local stage="$fixture/stage"
  local private_stage="$fixture/private-stage"
  local destination="$fixture/published"
  local private_destination="$fixture/private-published"
  local app="$derived_data/Build/Products/Release/Shuo.app"
  local info_plist="$app/Contents/Info.plist"
  local basename='Shuo-0.1.0-macOS'

  mkdir -p "$app/Contents" "$stage" "$private_stage" "$destination" "$private_destination"
  plutil -create xml1 "$info_plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.1.0' "$info_plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 7' "$info_plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.shuotian.Shuo' "$info_plist"
  printf 'zip payload\n' >"$stage/$basename.zip"
  printf 'dmg payload\n' >"$stage/$basename.dmg"
  printf 'symbols payload\n' >"$private_stage/$basename-symbols.zip"
  cp "$stage/$basename.zip" "$stage/Shuo-latest-macOS.zip"
  cp "$stage/$basename.dmg" "$stage/Shuo-latest-macOS.dmg"

  export SHUO_RELEASE=1
  export SHUO_DERIVED_DATA="$derived_data"
  export SHUO_PACKAGE_DIR="$stage"
  export SHUO_PRIVATE_ARTIFACT_DIR="$private_stage"
  set -- all
  # shellcheck source=../../Scripts/package-app.sh
  source "$PACKAGE_SCRIPT"
  SOURCE_GIT_SHA='1111111111111111111111111111111111111111'
  SOURCE_GIT_REF='release/0.1.0'
  SOURCE_GIT_TAG='v0.1.0'

  create_release_checksum_manifest >/dev/null
  create_release_manifest >/dev/null
  jq -e \
    --arg sha "$SOURCE_GIT_SHA" \
    '.version == "0.1.0"
      and .build == "7"
      and .bundle_id == "dev.shuotian.Shuo"
      and .source.repository == "https://github.com/stcheng/shuo.git"
      and .source.tag == "v0.1.0"
      and .source.git_sha == $sha
      and .dependencies.sparkle.repository == "https://github.com/sparkle-project/Sparkle"
      and .dependencies.sparkle.version == "2.9.4"
      and .dependencies.sparkle.revision == "b6496a74a087257ef5e6da1c5b29a447a60f5bd7"
      and .dependencies.whisper_cpp.version == "1.8.6"
      and (.dependencies.whisper_cpp.source_sha256 | length) == 64
      and (.artifacts.zip.sha256 | length) == 64
      and (.artifacts.dmg.sha256 | length) == 64
      and (.artifacts.symbols.sha256 | length) == 64
      and .artifacts.symbols.path == "private/Shuo-0.1.0-macOS-symbols.zip"
      and .artifacts.symbols.visibility == "private"' \
    "$stage/$basename.manifest.json" >/dev/null \
    || fail "release manifest is missing traceability data"

  publish_staged_release_artifacts "$destination" "$private_destination" >/dev/null
  for file in \
    "$basename.zip" \
    "$basename.dmg" \
    "$basename.sha256" \
    "$basename.manifest.json" \
    'Shuo-latest-macOS.zip' \
    'Shuo-latest-macOS.dmg'; do
    cmp -s "$stage/$file" "$destination/$file" \
      || fail "staged publication changed or omitted $file"
  done
  [[ ! -e "$destination/$basename-symbols.zip" ]] \
    || fail "private symbols archive leaked into the public artifact directory"
  cmp -s \
    "$private_stage/$basename-symbols.zip" \
    "$private_destination/$basename-symbols.zip" \
    || fail "private symbols archive was not published to the private directory"

  local public_asset_list public_asset_count
  public_asset_list="$(SHUO_RELEASE_MANIFEST="$destination/$basename.manifest.json" \
    make -s -C "$ROOT_DIR" release-public-assets)"
  public_asset_count="$(awk 'NF { count += 1 } END { print count + 0 }' <<<"$public_asset_list")"
  [[ "$public_asset_count" == "6" ]] \
    || fail "public release allowlist must contain exactly six explicit files"
  [[ "$public_asset_list" != *symbols* && "$public_asset_list" != *private* ]] \
    || fail "public release allowlist leaked a private artifact"

  printf 'tampered alias\n' >>"$destination/Shuo-latest-macOS.dmg"
  assert_failure env \
    SHUO_RELEASE_MANIFEST="$destination/$basename.manifest.json" \
    make -s -C "$ROOT_DIR" release-public-assets
  cp "$destination/$basename.dmg" "$destination/Shuo-latest-macOS.dmg"

  printf 'tampered versioned artifact\n' >>"$destination/$basename.zip"
  assert_failure env \
    SHUO_RELEASE_MANIFEST="$destination/$basename.manifest.json" \
    make -s -C "$ROOT_DIR" release-public-assets
  cp "$stage/$basename.zip" "$destination/$basename.zip"

  local republish_output republish_status
  set +e
  republish_output="$(publish_staged_release_artifacts "$destination" "$private_destination" 2>&1)"
  republish_status=$?
  set -e
  [[ "$republish_status" -ne 0 ]] \
    || fail "release publication unexpectedly overwrote a versioned artifact"
  grep -Fq 'Refusing to overwrite existing versioned release artifact' <<<"$republish_output" \
    || fail "release publication did not explain its overwrite refusal"

  local output_guard_output output_guard_status
  set +e
  output_guard_output="$(validate_release_output_directory "$destination" "$private_destination" 2>&1)"
  output_guard_status=$?
  set -e
  [[ "$output_guard_status" -ne 0 ]] \
    || fail "release preflight accepted a directory with versioned artifacts"
  grep -Fq 'already contains a versioned artifact' <<<"$output_guard_output" \
    || fail "release output guard did not explain its refusal"

  local mixed_output mixed_status empty_mixed="$fixture/mixed-output"
  mkdir -p "$empty_mixed"
  set +e
  mixed_output="$(validate_release_output_directory "$empty_mixed" "$empty_mixed" 2>&1)"
  mixed_status=$?
  set -e
  [[ "$mixed_status" -ne 0 && "$mixed_output" == *"must be separate"* ]] \
    || fail "release output guard allowed private dSYM files in the public root"
)

run_distribution_notices_test() (
  local fixture="$WORK_DIR/distribution-notices"
  local app="$fixture/Shuo.app"
  local resources="$app/Contents/Resources"
  local plist="$app/Contents/Info.plist"

  mkdir -p "$resources"
  plutil -create xml1 "$plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 1.0.0' "$plist"

  export SHUO_RELEASE=1
  export SHUO_DERIVED_DATA="$fixture/DerivedData"
  set -- all
  # shellcheck source=../../Scripts/package-app.sh
  source "$PACKAGE_SCRIPT"
  APP_SOURCE="$app"
  SOURCE_GIT_SHA='1111111111111111111111111111111111111111'

  git() {
    if [[ "$*" == *'rev-parse --verify refs/tags/v1.0.0^{commit}'* ]]; then
      printf '%s\n' "$SOURCE_GIT_SHA"
      return 0
    fi
    return 1
  }

  embed_distribution_notices
  cmp -s "$ROOT_DIR/LICENSE" "$resources/LICENSE" \
    || fail "packager did not embed the canonical GPL license"
  grep -Fxq 'Release tag: v1.0.0' "$resources/CORRESPONDING_SOURCE.txt" \
    || fail "source notice did not bind the release tag"
  grep -Fxq 'Source archive: https://github.com/stcheng/shuo/archive/refs/tags/v1.0.0.tar.gz' \
    "$resources/CORRESPONDING_SOURCE.txt" \
    || fail "source notice did not provide the immutable tag archive"
  grep -Fxq "Source commit: $SOURCE_GIT_SHA" "$resources/CORRESPONDING_SOURCE.txt" \
    || fail "source notice did not bind the source commit"

  git() {
    printf '%040d\n' 2
  }
  assert_failure_contains 'must point to source commit' embed_distribution_notices
)

run_fresh_derived_data_test() (
  local stale_derived="$WORK_DIR/stale-derived"
  mkdir -p "$stale_derived"
  printf 'stale build output\n' >"$stale_derived/stale.txt"

  export SHUO_RELEASE=1
  export SHUO_DERIVED_DATA="$stale_derived"
  set -- all
  # shellcheck source=../../Scripts/package-app.sh
  source "$PACKAGE_SCRIPT"

  RELEASE_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shuo-release-stage-test.XXXXXX")"
  prepare_release_derived_data
  [[ "$DERIVED_DATA" != "$stale_derived" ]] \
    || fail "release packaging reused caller-provided stale DerivedData"
  [[ "$(basename "$DERIVED_DATA")" == shuo-release-derived.* ]] \
    || fail "release packaging did not allocate temporary DerivedData: $DERIVED_DATA"
  [[ -d "$DERIVED_DATA" ]] \
    || fail "fresh release DerivedData directory was not created"
  [[ -z "$(find "$DERIVED_DATA" -mindepth 1 -print -quit)" ]] \
    || fail "fresh release DerivedData contained stale files"
  [[ "$APP_SOURCE" == "$DERIVED_DATA/Build/Products/Release/Shuo.app" ]] \
    || fail "release app path was not rebound to fresh DerivedData"
  [[ "$SHUO_WHISPER_RUNTIME_CACHE" == "$RELEASE_STAGING_DIR/whisper-runtime" ]] \
    || fail "release runtime cache was not isolated inside the fresh staging directory"
  [[ "$SHUO_WHISPER_CPP_VERSION" == "1.8.6" ]] \
    || fail "release runtime version was not forced to the pinned value"

  local temporary_derived="$RELEASE_TEMP_DERIVED_DATA"
  local temporary_stage="$RELEASE_STAGING_DIR"
  cleanup_release_workspaces
  [[ ! -e "$temporary_derived" && ! -e "$temporary_stage" ]] \
    || fail "release success/failure cleanup left a temporary workspace behind"
  [[ -f "$stale_derived/stale.txt" ]] \
    || fail "release cleanup touched caller-provided stale DerivedData"
)

run_update_archive_binding_test() (
  local fixture="$WORK_DIR/update-binding"
  local app="$fixture/payload/Shuo.app"
  local plist="$app/Contents/Info.plist"
  local sparkle_info="$app/Contents/Frameworks/Sparkle.framework/Versions/B/Resources/Info.plist"
  local archive_dir="$fixture/release"
  local archive="$archive_dir/Shuo-0.1.0-macOS.zip"
  local checksum="$archive_dir/Shuo-0.1.0-macOS.sha256"
  local manifest="$archive_dir/Shuo-0.1.0-macOS.manifest.json"
  local fake_bin="$fixture/bin"
  local fake_derived_data="$fixture/DerivedData"
  local sparkle_bin="$fake_derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin"
  local appcast_output="$fixture/appcast.xml"
  local zip_sha dmg_sha resolved_sparkle_revision resolved_sparkle_version

  mkdir -p \
    "$app/Contents/MacOS" \
    "$app/Contents/Resources/Runtime" \
    "$(dirname "$sparkle_info")" \
    "$archive_dir" \
    "$fake_bin" \
    "$sparkle_bin"
  resolved_sparkle_revision="$(jq -er \
    '.pins[] | select(.identity == "sparkle") | .state.revision' \
    "$ROOT_DIR/Shuo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")"
  resolved_sparkle_version="$(jq -er \
    '.pins[] | select(.identity == "sparkle") | .state.version' \
    "$ROOT_DIR/Shuo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")"
  jq -n \
    --arg revision "$resolved_sparkle_revision" \
    --arg version "$resolved_sparkle_version" \
    '{
      object: {
        dependencies: [{
          packageRef: {
            identity: "sparkle",
            location: "https://github.com/sparkle-project/Sparkle"
          },
          state: {checkoutState: {revision: $revision, version: $version}}
        }]
      }
    }' >"$fake_derived_data/SourcePackages/workspace-state.json"
  plutil -create xml1 "$plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.1.0' "$plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 7' "$plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.shuotian.Shuo' "$plist"
  plutil -create xml1 "$sparkle_info"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 2.9.4' "$sparkle_info"
  printf '#!/bin/sh\nexit 0\n' >"$app/Contents/MacOS/Shuo"
  chmod 755 "$app/Contents/MacOS/Shuo"
  cp "$ROOT_DIR/LICENSE" "$app/Contents/Resources/LICENSE"
  cat >"$app/Contents/Resources/CORRESPONDING_SOURCE.txt" <<'EOF'
Shuo Corresponding Source

License: GPL-3.0-only
Release tag: v0.1.0
Tagged source: https://github.com/stcheng/shuo/tree/v0.1.0
Source archive: https://github.com/stcheng/shuo/archive/refs/tags/v0.1.0.tar.gz
Source commit: 1111111111111111111111111111111111111111
Exact source: https://github.com/stcheng/shuo/tree/1111111111111111111111111111111111111111

The tagged source and this binary must resolve to the same commit.
EOF
  printf '%s' \
    '1.8.6:f8e632016ceae556f3132a16c7f704be1e7715595041f474fa81a2b64c1abf7c:arm64;x86_64:test-script:test-cmake' \
    >"$app/Contents/Resources/Runtime/whisper-runtime-provenance.txt"
  ditto -c -k --keepParent "$app" "$archive"
  zip_sha="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
  dmg_sha="$(printf 'dmg payload' | shasum -a 256 | awk '{ print $1 }')"
  printf '%s  %s\n%s  %s\n' \
    "$zip_sha" "$(basename "$archive")" \
    "$dmg_sha" 'Shuo-0.1.0-macOS.dmg' >"$checksum"
  jq -n \
    --arg zip_sha "$zip_sha" \
    --arg dmg_sha "$dmg_sha" \
    '{
      schema_version: 1,
      product: "Shuo",
      bundle_id: "dev.shuotian.Shuo",
      version: "0.1.0",
      build: "7",
      source: {
        repository: "https://github.com/stcheng/shuo.git",
        tag: "v0.1.0",
        git_sha: "1111111111111111111111111111111111111111",
        git_ref: "main"
      },
      dependencies: {
        sparkle: {
          repository: "https://github.com/sparkle-project/Sparkle",
          version: "2.9.4",
          revision: "b6496a74a087257ef5e6da1c5b29a447a60f5bd7"
        },
        whisper_cpp: {
          version: "1.8.6",
          source_sha256: "f8e632016ceae556f3132a16c7f704be1e7715595041f474fa81a2b64c1abf7c"
        }
      },
      artifacts: {
        zip: {filename: "Shuo-0.1.0-macOS.zip", sha256: $zip_sha},
        dmg: {filename: "Shuo-0.1.0-macOS.dmg", sha256: $dmg_sha},
        symbols: {
          filename: "Shuo-0.1.0-macOS-symbols.zip",
          path: "private/Shuo-0.1.0-macOS-symbols.zip",
          sha256: "2222222222222222222222222222222222222222222222222222222222222222",
          visibility: "private"
        }
      }
    }' >"$manifest"

  cat >"$fake_bin/codesign" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" --display "* ]]; then
  cat <<DETAILS
Authority=Developer ID Application: Release Test (${FAKE_TEAM_ID:-4GQ47468NJ})
TeamIdentifier=${FAKE_TEAM_ID:-4GQ47468NJ}
Timestamp=Jul 12, 2026 at 12:00:00
CodeDirectory v=20500 size=1 flags=0x10000(runtime) hashes=1+1 location=embedded
DETAILS
fi
exit 0
EOF
  cat >"$fake_bin/xcrun" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod 755 "$fake_bin/codesign" "$fake_bin/xcrun"

  PATH="$fake_bin:$PATH" \
    "$VERIFY_SCRIPT" --update-archive "$archive" "$checksum" "$manifest" >/dev/null

  local wrong_team_output wrong_team_status
  set +e
  wrong_team_output="$(FAKE_TEAM_ID=WRONGTEAM PATH="$fake_bin:$PATH" \
    "$VERIFY_SCRIPT" --update-archive "$archive" "$checksum" "$manifest" 2>&1)"
  wrong_team_status=$?
  set -e
  [[ "$wrong_team_status" -ne 0 && "$wrong_team_output" == *"team 4GQ47468NJ"* ]] \
    || fail "update verifier accepted or poorly explained a wrong Developer ID team"

  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier invalid.bundle' "$plist"
  ditto -c -k --keepParent "$app" "$archive"
  assert_failure_contains 'bundle ID must be dev.shuotian.Shuo' env PATH="$fake_bin:$PATH" \
    "$VERIFY_SCRIPT" --update-archive "$archive" "$checksum" "$manifest"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.shuotian.Shuo' "$plist"
  ditto -c -k --keepParent "$app" "$archive"

  jq '.build = "8"' "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
  assert_failure_contains 'build does not match' env PATH="$fake_bin:$PATH" \
    "$VERIFY_SCRIPT" --update-archive "$archive" "$checksum" "$manifest"
  jq '.build = "7"' "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"

  jq '.dependencies.sparkle.revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
    "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
  assert_failure_contains 'wrong Sparkle revision' env PATH="$fake_bin:$PATH" \
    "$VERIFY_SCRIPT" --update-archive "$archive" "$checksum" "$manifest"
  jq '.dependencies.sparkle.revision = "b6496a74a087257ef5e6da1c5b29a447a60f5bd7"' \
    "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"

  printf 'stale archive bytes\n' >>"$archive"
  assert_failure_contains 'hash does not match the release manifest' env PATH="$fake_bin:$PATH" \
    "$VERIFY_SCRIPT" --update-archive "$archive" "$checksum" "$manifest"

  ditto -c -k --keepParent "$app" "$archive"
  zip_sha="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
  awk -v replacement="$zip_sha" \
    -v expected="$(basename "$archive")" \
    '{ if ($2 == expected) $1 = replacement; print $1 "  " $2 }' \
    "$checksum" >"$checksum.tmp"
  mv "$checksum.tmp" "$checksum"
  jq --arg zip_sha "$zip_sha" '.artifacts.zip.sha256 = $zip_sha' \
    "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"

  cat >"$sparkle_bin/generate_keys" <<'EOF'
#!/usr/bin/env bash
[[ "$#" == "3" && "$1" == '--account' && "$2" == 'production-test' && "$3" == '-p' ]] || exit 64
printf '%s\n' 'i0Hw/eZpvDeme6HTBGedmDhGfLECOXuTZ1q6urwyZyg='
EOF
  cat >"$sparkle_bin/generate_appcast" <<'EOF'
#!/usr/bin/env bash
output=''
download_prefix=''
account=''
archive_directory="${!#}"
while (($#)); do
  case "$1" in
    --account)
      account="$2"
      shift 2
      ;;
    --download-url-prefix)
      download_prefix="$2"
      shift 2
      ;;
    -o)
      output="$2"
      shift 2
      ;;
    --link|--maximum-versions|--maximum-deltas)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[[ "$account" == 'production-test' && -n "$download_prefix" && -n "$output" ]] || exit 64
archive="$(find "$archive_directory" -maxdepth 1 -type f -name 'Shuo-*-macOS.zip' -print -quit)"
archive_length="$(stat -f '%z' "$archive")"
cat >"$output" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel><item><enclosure url="${download_prefix}Shuo-0.1.0-macOS.zip" length="$archive_length" sparkle:version="7" sparkle:shortVersionString="0.1.0" sparkle:edSignature="test" /></item></channel>
</rss>
XML
EOF
  cat >"$sparkle_bin/sign_update" <<'EOF'
#!/usr/bin/env bash
[[ "$#" == "5" ]] || exit 64
[[ "$1" == '--account' && "$2" == 'production-test' && "$3" == '--verify' ]] || exit 64
[[ -f "$4" && -n "$5" ]]
EOF
  chmod 755 \
    "$sparkle_bin/generate_appcast" \
    "$sparkle_bin/generate_keys" \
    "$sparkle_bin/sign_update"

  PATH="$fake_bin:$PATH" \
  SHUO_APPCAST_OUTPUT="$appcast_output" \
  SHUO_DERIVED_DATA="$fake_derived_data" \
  SHUO_SPARKLE_ACCOUNT='production-test' \
    "$APPCAST_SCRIPT" "$archive" >/dev/null
  grep -Fq 'Shuo-0.1.0-macOS.zip' "$appcast_output" \
    || fail "appcast generation did not use the manifest-bound archive"

  cp "$appcast_output" "$appcast_output.before-failure"
  jq '.build = "8"' "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
  assert_failure_contains 'build does not match' env \
    PATH="$fake_bin:$PATH" \
    SHUO_APPCAST_OUTPUT="$appcast_output" \
    SHUO_DERIVED_DATA="$fake_derived_data" \
    SHUO_SPARKLE_ACCOUNT='production-test' \
    "$APPCAST_SCRIPT" "$archive"
  cmp -s "$appcast_output.before-failure" "$appcast_output" \
    || fail "failed appcast validation replaced the previously valid feed"
)

bash -n "$PACKAGE_SCRIPT"
bash -n "$VERIFY_SCRIPT"
bash -n "$APPCAST_SCRIPT"
bash -n "$EXPORT_TEST_SCRIPT"
bash -n "$0"

"$EXPORT_TEST_SCRIPT"

run_preflight
run_submission Accepted >/dev/null
run_manifest_and_staging_test
run_distribution_notices_test
run_fresh_derived_data_test
run_update_archive_binding_test
assert_failure_contains 'status: Invalid' run_submission Invalid
assert_failure_contains 'unreadable response' run_submission Malformed

TEST_SIGN_MODE=adhoc \
  assert_failure_contains 'requires SHUO_SIGN_MODE=identity' run_preflight
TEST_NOTARIZE=0 \
  assert_failure_contains 'requires SHUO_NOTARIZE=1' run_preflight
TEST_SIGN_IDENTITY='Shuo Local Development' \
  assert_failure_contains 'Developer ID Application certificate' run_preflight
TEST_NOTARY_PROFILE='' \
  assert_failure_contains 'non-empty SHUO_NOTARY_PROFILE' run_preflight
TEST_ARCHITECTURES='arm64' \
  assert_failure_contains 'arm64;x86_64' run_preflight
TEST_WHISPER_VERSION='9.9.9' \
  assert_failure_contains 'version must be 1.8.6' run_preflight
TEST_WHISPER_SHA256='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  assert_failure_contains 'source hash must match' run_preflight
TEST_WHISPER_CACHE='/tmp/untrusted-whisper-cache' \
  assert_failure_contains 'caller-provided whisper runtime cache' run_preflight
TEST_ENTITLEMENTS="$WORK_DIR/empty.entitlements" \
  assert_failure_contains 'pinned App/ShuoDirect.entitlements' run_preflight
TEST_LOCAL_TAG_SHA='2222222222222222222222222222222222222222' \
  assert_failure_contains 'must point to source commit' run_preflight
TEST_REMOTE_TAG_SHA='2222222222222222222222222222222222222222' \
  assert_failure_contains 'Canonical public tag' run_preflight
TEST_ARCHIVE_FAILURE=1 \
  assert_failure_contains 'source archive is not anonymously reachable' run_preflight
TEST_SECURITY_FAILURE=1 \
  assert_failure_contains 'signing identity is unavailable' run_preflight
TEST_NOTARY_FAILURE=1 \
  assert_failure_contains "Notary profile 'Shuo-Notary'" run_preflight
TEST_GIT_DIRTY=1 \
  assert_failure_contains 'clean Git working tree' run_preflight

MAKE_DRY_RUN="$(make -n -C "$ROOT_DIR" release-rc)"
grep -Fq 'SHUO_RELEASE=1' <<<"$MAKE_DRY_RUN" \
  || fail "release-rc does not force SHUO_RELEASE=1"
grep -Fq 'SHUO_SIGN_MODE=identity' <<<"$MAKE_DRY_RUN" \
  || fail "release-rc does not force identity signing"
grep -Fq 'SHUO_NOTARIZE=1' <<<"$MAKE_DRY_RUN" \
  || fail "release-rc does not force notarization"
grep -Fq "SHUO_WHISPER_ARCHITECTURES='arm64;x86_64'" <<<"$MAKE_DRY_RUN" \
  || fail "release-rc does not force a Universal whisper runtime"
grep -Fq 'git status --porcelain --untracked-files=all' <<<"$MAKE_DRY_RUN" \
  || fail "release-rc does not reject a dirty source tree"
grep -Fq 'stdout is a machine-readable contract' "$WHISPER_PREPARE_SCRIPT" \
  || fail "whisper runtime preparation does not document its stdout contract"
grep -Fq '} >&2' "$WHISPER_PREPARE_SCRIPT" \
  || fail "fresh whisper builds can contaminate the executable path on stdout"

DMG_SIGN_LINE="$(grep -n 'sign_disk_image "$dmg_path"' "$PACKAGE_SCRIPT" | cut -d: -f1)"
DMG_NOTARY_LINE="$(grep -n 'notarize_disk_image "$dmg_path"' "$PACKAGE_SCRIPT" | cut -d: -f1)"
[[ -n "$DMG_SIGN_LINE" && -n "$DMG_NOTARY_LINE" && "$DMG_SIGN_LINE" -lt "$DMG_NOTARY_LINE" ]] \
  || fail "DMG must be signed before it is submitted for notarization"
grep -Fq 'Packaging/DMG/layout.dsstore' "$PACKAGE_SCRIPT" \
  || fail "formal DMGs must require the committed Finder layout template"
grep -Fq 'ditto "$layout_template" "$mount_dir/.DS_Store"' "$PACKAGE_SCRIPT" \
  || fail "DMG assembly does not apply the committed Finder layout template"

for required_check in \
  'codesign --verify' \
  'stapler validate' \
  'spctl' \
  '--assess' \
  'lipo -archs' \
  'CFBundleShortVersionString' \
  'dev.shuotian.Shuo' \
  'Sparkle.framework' \
  '.dependencies.sparkle.revision' \
  'otool -L' \
  'unapproved dynamic dependency' \
  'Runtime/whisper-cli' \
	'resources/LICENSE' \
  'CORRESPONDING_SOURCE.txt' \
  'whisper.cpp-LICENSE' \
  'THIRD_PARTY_NOTICES.md' \
  'SUFeedURL' \
  'SUPublicEDKey' \
  'ShuoDevelopmentBuild' \
  'com.apple.security.device.audio-input' \
  'production app entitlements must contain only audio-input=true' \
  '.source.git_sha' \
  '.source.repository' \
  '.dependencies.whisper_cpp.version' \
  '.artifacts.symbols' \
  '.artifacts.symbols.path' \
  'whisper-runtime-provenance.txt' \
  'CDHash' \
  'DMG Applications link does not target /Applications' \
  'EXPECTED_DMG_TOP_LEVEL' \
  'dwarfdump --uuid' \
  'shasum -a 256 --check'; do
  grep -Fq -- "$required_check" "$VERIFY_SCRIPT" \
    || fail "release verifier is missing: $required_check"
done

# Reading codesign through an early-exiting pipeline can make codesign receive
# SIGPIPE under `set -o pipefail`, failing a valid release at the final gate.
grep -Fq 'details="$(codesign --display --verbose=4 "$1" 2>&1)"' "$VERIFY_SCRIPT" \
  || fail "release verifier must capture codesign metadata before extracting CDHash"
grep -Fq '<<<"$details"' "$VERIFY_SCRIPT" \
  || fail "release verifier must extract CDHash after codesign completes"
grep -Fq 'MARKETING_VERSION$/ && !found' "$PACKAGE_SCRIPT" \
  || fail "release packager must drain build settings while reading MARKETING_VERSION"

for required_staging_behavior in \
  'shuo-release-stage.' \
  'verify_release_source_unchanged' \
  'validate_release_output_directory' \
  'create_release_manifest' \
  'embed_distribution_notices' \
  'prepare_release_derived_data' \
  'trap cleanup_release_workspaces EXIT' \
  'publish_staged_release_artifacts'; do
  grep -Fq -- "$required_staging_behavior" "$PACKAGE_SCRIPT" \
    || fail "release packager is missing staging behavior: $required_staging_behavior"
done

for required_appcast_binding in \
  '--update-archive' \
  'SHUO_RELEASE_CHECKSUM' \
  'SHUO_RELEASE_MANIFEST' \
  'BUILD_NUMBER' \
  'EXPECTED_SPARKLE_PUBLIC_KEY' \
  'EXPECTED_SPARKLE_VERSION' \
  'EXPECTED_SPARKLE_REVISION' \
  'workspace-state.json' \
  'CANONICAL_URL_COUNT' \
  'sign_update' \
  '--account "$SPARKLE_ACCOUNT" --verify "$ARCHIVE"'; do
  grep -Fq -- "$required_appcast_binding" "$APPCAST_SCRIPT" \
    || fail "appcast generator is missing RC binding: $required_appcast_binding"
done

echo "Release packaging guard tests passed."
