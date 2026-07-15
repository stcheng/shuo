#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT_DIR/Shuo.xcodeproj"
SCHEME="ShuoCommunity"
CONFIGURATION="Community"
INFO_PLIST="$ROOT_DIR/App/Info-Community.plist"

fail() {
  echo "community-build-tests: $*" >&2
  exit 1
}

settings="$({
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -onlyUsePackageVersionsFromResolvedFile \
    -disableAutomaticPackageResolution \
    -skipPackageUpdates \
    -showBuildSettings
} 2>/dev/null)"

setting_value() {
  local key="$1"
  awk -F ' = ' -v key="$key" '
    $1 == "    " key && !found {
      value = $2
      found = 1
    }
    END {
      if (found) print value
    }
  ' <<<"$settings"
}

assert_setting() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(setting_value "$key")"
  [[ "$actual" == "$expected" ]] \
    || fail "$key must be '$expected' (found '${actual:-missing}')"
}

assert_setting PRODUCT_BUNDLE_IDENTIFIER org.shuo.community
assert_setting PRODUCT_NAME 'Shuo Community'
assert_setting INFOPLIST_FILE 'App/Info-Community.plist'
assert_setting ASSETCATALOG_COMPILER_APPICON_NAME CommunityAppIcon
assert_setting CODE_SIGN_STYLE Manual
assert_setting CODE_SIGN_IDENTITY '-'
assert_setting ENABLE_APP_SANDBOX NO

[[ -z "$(setting_value DEVELOPMENT_TEAM)" ]] \
  || fail "Community builds must not require a DEVELOPMENT_TEAM"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :ShuoDistributionChannel' "$INFO_PLIST")" == community ]] \
  || fail "Community Info.plist must identify the community channel"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ShuoStorageDirectoryName' "$INFO_PLIST")" == 'Shuo Community' ]] \
  || fail "Community data must use its own Application Support directory"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ShuoCredentialServicePrefix' "$INFO_PLIST")" == org.shuo.community ]] \
  || fail "Community credentials must use their own Keychain namespace"

if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$INFO_PLIST" >/dev/null 2>&1 \
  || /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST" >/dev/null 2>&1; then
  fail "Community builds must not contain the official Sparkle feed or key"
fi

echo "Community build configuration is isolated and account-free."
