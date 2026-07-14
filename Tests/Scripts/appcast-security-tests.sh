#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPCAST_SCRIPT="$ROOT_DIR/Scripts/generate-appcast.sh"
EXPECTED_PUBLIC_KEY="i0Hw/eZpvDeme6HTBGedmDhGfLECOXuTZ1q6urwyZyg="
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shuo-appcast-security-tests.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
  echo "Appcast security test failed: $*" >&2
  exit 1
}

assert_failure_preserves_feed() {
  local expected_message="$1"
  local appcast_output="$2"
  shift 2
  local before="$WORK_DIR/appcast.before.xml"
  local output status

  cp "$appcast_output" "$before"
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "command unexpectedly succeeded"
  [[ "$output" == *"$expected_message"* ]] \
    || fail "failure did not mention '$expected_message': $output"
  cmp -s "$before" "$appcast_output" \
    || fail "failed appcast generation replaced the existing feed"
}

FIXTURE="$WORK_DIR/fixture"
APP="$FIXTURE/payload/Shuo.app"
PLIST="$APP/Contents/Info.plist"
SPARKLE_INFO="$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Resources/Info.plist"
RELEASE_DIR="$FIXTURE/release"
ARCHIVE="$RELEASE_DIR/Shuo-0.1.0-macOS.zip"
CHECKSUM="$RELEASE_DIR/Shuo-0.1.0-macOS.sha256"
MANIFEST="$RELEASE_DIR/Shuo-0.1.0-macOS.manifest.json"
APPCAST_OUTPUT="$FIXTURE/appcast.xml"
FAKE_BIN="$FIXTURE/bin"
FAKE_DERIVED_DATA="$FIXTURE/DerivedData"
SPARKLE_BIN="$FAKE_DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"

mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources/Runtime" \
  "$(dirname "$SPARKLE_INFO")" \
  "$RELEASE_DIR" \
  "$FAKE_BIN" \
  "$SPARKLE_BIN"
RESOLVED_SPARKLE_REVISION="$(jq -er \
  '.pins[] | select(.identity == "sparkle") | .state.revision' \
  "$ROOT_DIR/Shuo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")"
RESOLVED_SPARKLE_VERSION="$(jq -er \
  '.pins[] | select(.identity == "sparkle") | .state.version' \
  "$ROOT_DIR/Shuo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")"
jq -n \
  --arg revision "$RESOLVED_SPARKLE_REVISION" \
  --arg version "$RESOLVED_SPARKLE_VERSION" \
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
  }' >"$FAKE_DERIVED_DATA/SourcePackages/workspace-state.json"
plutil -create xml1 "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.1.0' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 7' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.shuotian.Shuo' "$PLIST"
plutil -create xml1 "$SPARKLE_INFO"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 2.9.4' "$SPARKLE_INFO"
printf '#!/bin/sh\nexit 0\n' >"$APP/Contents/MacOS/Shuo"
chmod 755 "$APP/Contents/MacOS/Shuo"
cp "$ROOT_DIR/LICENSE" "$APP/Contents/Resources/LICENSE"
cat >"$APP/Contents/Resources/CORRESPONDING_SOURCE.txt" <<'EOF'
Shuo Corresponding Source

License: GPL-3.0-only
Release tag: v0.1.0
Tagged source: https://github.com/stcheng/shuo/tree/v0.1.0
Source archive: https://github.com/stcheng/shuo/archive/refs/tags/v0.1.0.tar.gz
Source commit: 1111111111111111111111111111111111111111
Exact source: https://github.com/stcheng/shuo/tree/1111111111111111111111111111111111111111

The tagged source and this binary must resolve to the same commit.
EOF
printf '%s\n' \
  '1.8.6:f8e632016ceae556f3132a16c7f704be1e7715595041f474fa81a2b64c1abf7c:arm64;x86_64:test' \
  >"$APP/Contents/Resources/Runtime/whisper-runtime-provenance.txt"
ditto -c -k --keepParent "$APP" "$ARCHIVE"

ZIP_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')"
DMG_SHA="$(printf 'dmg payload' | shasum -a 256 | awk '{ print $1 }')"
printf '%s  %s\n%s  %s\n' \
  "$ZIP_SHA" "$(basename "$ARCHIVE")" \
  "$DMG_SHA" 'Shuo-0.1.0-macOS.dmg' >"$CHECKSUM"
jq -n \
  --arg zip_sha "$ZIP_SHA" \
  --arg dmg_sha "$DMG_SHA" \
  '{
    schema_version: 1,
    product: "Shuo",
    bundle_id: "dev.shuotian.Shuo",
    version: "0.1.0",
    build: "7",
    source: {
      git_sha: "1111111111111111111111111111111111111111",
      git_ref: "main",
      repository: "https://github.com/stcheng/shuo.git",
      tag: "v0.1.0"
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
  }' >"$MANIFEST"

cat >"$FAKE_BIN/codesign" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" --display "* ]]; then
  cat <<DETAILS
Authority=Developer ID Application: Release Test (4GQ47468NJ)
TeamIdentifier=4GQ47468NJ
Timestamp=Jul 12, 2026 at 12:00:00
CodeDirectory v=20500 size=1 flags=0x10000(runtime) hashes=1+1 location=embedded
DETAILS
fi
exit 0
EOF
cat >"$FAKE_BIN/xcrun" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$SPARKLE_BIN/generate_keys" <<'EOF'
#!/usr/bin/env bash
[[ "$#" == "3" && "$1" == '--account' && "$2" == 'production-test' && "$3" == '-p' ]] || exit 64
printf '%s\n' "${MOCK_PUBLIC_KEY:?}"
EOF
cat >"$SPARKLE_BIN/sign_update" <<'EOF'
#!/usr/bin/env bash
[[ "$#" == "5" ]] || exit 64
[[ "$1" == '--account' && "$2" == 'production-test' && "$3" == '--verify' ]] || exit 64
[[ -f "$4" && -n "$5" ]] || exit 64
EOF
cat >"$SPARKLE_BIN/generate_appcast" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

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

[[ "$account" == 'production-test' && -n "$output" && -n "$download_prefix" ]]
archive="$(find "$archive_directory" -maxdepth 1 -type f -name 'Shuo-*-macOS.zip' -print -quit)"
archive_length="$(stat -f '%z' "$archive")"
archive_name="$(basename "$archive")"
canonical_url="$download_prefix$archive_name"
preserve_old=0
if [[ -f "$output" ]] && grep -Fq 'sparkle:version="6"' "$output"; then
  preserve_old=1
fi

case "${MOCK_APPCAST_CASE:?}" in
  success)
    current_urls=("$canonical_url")
    ;;
  duplicate)
    current_urls=("$canonical_url" "$canonical_url")
    ;;
  rogue-duplicate)
    current_urls=("$canonical_url" "https://downloads.example.invalid/$archive_name")
    ;;
  wrong-url)
    current_urls=("https://downloads.example.invalid/$archive_name")
    ;;
  substring-url)
    current_urls=("$canonical_url.tampered")
    ;;
  *)
    exit 64
    ;;
esac

{
  cat <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
XML
  if [[ "$preserve_old" == "1" ]]; then
    cat <<'XML'
    <item><enclosure url="https://github.com/stcheng/shuo/releases/download/v0.0.9/Shuo-0.0.9-macOS.zip" length="1" sparkle:version="6" sparkle:shortVersionString="0.0.9" sparkle:edSignature="old-signature" /></item>
XML
  fi
  for url in "${current_urls[@]}"; do
    printf '    <item><enclosure url="%s" length="%s" sparkle:version="7" sparkle:shortVersionString="0.1.0" sparkle:edSignature="test-signature" /></item>\n' \
      "$url" "$archive_length"
  done
  cat <<'XML'
  </channel>
</rss>
XML
} >"$output"
EOF
chmod 755 \
  "$FAKE_BIN/codesign" \
  "$FAKE_BIN/xcrun" \
  "$SPARKLE_BIN/generate_appcast" \
  "$SPARKLE_BIN/generate_keys" \
  "$SPARKLE_BIN/sign_update"

cat >"$APPCAST_OUTPUT" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item><enclosure url="https://github.com/stcheng/shuo/releases/download/v0.0.9/Shuo-0.0.9-macOS.zip" length="1" sparkle:version="6" sparkle:shortVersionString="0.0.9" sparkle:edSignature="old-signature" /></item>
  </channel>
</rss>
XML

run_appcast() {
  local appcast_case="$1"
  local public_key="$2"
  env \
    PATH="$FAKE_BIN:$PATH" \
    MOCK_APPCAST_CASE="$appcast_case" \
    MOCK_PUBLIC_KEY="$public_key" \
    SHUO_APPCAST_OUTPUT="$APPCAST_OUTPUT" \
    SHUO_DERIVED_DATA="$FAKE_DERIVED_DATA" \
    SHUO_SPARKLE_ACCOUNT='production-test' \
    "$APPCAST_SCRIPT" "$ARCHIVE"
}

bash -n "$APPCAST_SCRIPT"
bash -n "$0"
! grep -Fq 'Library/Developer/Xcode/DerivedData/Shuo-*' "$APPCAST_SCRIPT" \
  || fail "appcast generator still searches arbitrary Xcode DerivedData directories"
! grep -Fq 'SHUO_SPARKLE_BIN' "$APPCAST_SCRIPT" \
  || fail "appcast generator still accepts an arbitrary Sparkle tool directory"

assert_failure_preserves_feed \
  "does not match the production SUPublicEDKey" \
  "$APPCAST_OUTPUT" \
  run_appcast success 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
assert_failure_preserves_feed \
  "exactly one enclosure with canonical URL" \
  "$APPCAST_OUTPUT" \
  run_appcast duplicate "$EXPECTED_PUBLIC_KEY"
assert_failure_preserves_feed \
  "exactly once across all enclosure URLs" \
  "$APPCAST_OUTPUT" \
  run_appcast rogue-duplicate "$EXPECTED_PUBLIC_KEY"
assert_failure_preserves_feed \
  "exactly one enclosure with canonical URL" \
  "$APPCAST_OUTPUT" \
  run_appcast wrong-url "$EXPECTED_PUBLIC_KEY"
assert_failure_preserves_feed \
  "exactly one enclosure with canonical URL" \
  "$APPCAST_OUTPUT" \
  run_appcast substring-url "$EXPECTED_PUBLIC_KEY"

run_appcast success "$EXPECTED_PUBLIC_KEY" >/dev/null
xmllint --noout "$APPCAST_OUTPUT"
[[ "$(xmllint --xpath \
  "count(//*[local-name()='enclosure' and @url='https://github.com/stcheng/shuo/releases/download/v0.1.0/Shuo-0.1.0-macOS.zip'])" \
  "$APPCAST_OUTPUT")" == "1" ]] \
  || fail "success case did not publish exactly one canonical enclosure"
grep -Fq 'sparkle:version="6"' "$APPCAST_OUTPUT" \
  || fail "success case did not preserve the prior feed entry"

echo "Appcast security tests passed."
