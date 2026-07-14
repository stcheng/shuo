#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHITECTURE="$(uname -m)"
DESTINATION="platform=macOS,arch=$ARCHITECTURE"
DERIVED_DATA="${SHUO_VERIFY_DERIVED_DATA:-$ROOT_DIR/DerivedData/Verify}"
EXPORT_DIR="$(mktemp -d /tmp/shuo-verify-export.XXXXXX)"
EXPORT_DERIVED_DATA="$(mktemp -d /tmp/shuo-verify-derived.XXXXXX)"
PACKAGE_RESOLUTION_ARGS=(
  -onlyUsePackageVersionsFromResolvedFile
  -disableAutomaticPackageResolution
  -skipPackageUpdates
)

cleanup() {
  rm -rf \
    "$EXPORT_DIR" \
    "$EXPORT_DERIVED_DATA" \
    "$DERIVED_DATA-direct" \
    "$DERIVED_DATA-community" \
    "$EXPORT_DERIVED_DATA-direct" \
    "$EXPORT_DERIVED_DATA-community"
}

trap cleanup EXIT

run_static_checks() {
  local source_root="$1"

  "$source_root/Scripts/audit-public-source.sh" "$source_root"

  jq empty "$source_root/App/Resources/Localization.json"
  while IFS= read -r config_file; do
    jq empty "$config_file"
  done < <(find "$source_root/Config/PluginProfiles" -type f -name '*.json' | sort)
  jq empty "$source_root/Evaluation/bilingual-technical-corpus.json"
  test "$(jq '.utterances | length' "$source_root/Evaluation/bilingual-technical-corpus.json")" -ge 50
  test "$(jq '.utterances | length' "$source_root/Evaluation/bilingual-technical-corpus.json")" -le 100
  test "$(jq '[.utterances[].id] | length' "$source_root/Evaluation/bilingual-technical-corpus.json")" \
    = "$(jq '[.utterances[].id] | unique | length' "$source_root/Evaluation/bilingual-technical-corpus.json")"
  python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' \
    "$source_root/Evaluation/evaluate_transcripts.py"

  plutil -lint \
	"$source_root/App/Info.plist" \
	"$source_root/App/Info-Community.plist" \
	"$source_root/App/Info-Direct.plist" \
    "$source_root/App/Shuo.entitlements" \
    "$source_root/App/ShuoDirect.entitlements"
  test "$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsAutomaticTermination' "$source_root/App/Info.plist")" = "false"
  test "$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsSuddenTermination' "$source_root/App/Info.plist")" = "false"
  test "$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsAutomaticTermination' "$source_root/App/Info-Direct.plist")" = "false"
  test "$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsSuddenTermination' "$source_root/App/Info-Direct.plist")" = "false"
  test "$(/usr/libexec/PlistBuddy -c 'Print :ShuoDistributionChannel' "$source_root/App/Info-Community.plist")" = "community"
  test "$(/usr/libexec/PlistBuddy -c 'Print :ShuoStorageDirectoryName' "$source_root/App/Info-Community.plist")" = "Shuo Community"
  test "$(/usr/libexec/PlistBuddy -c 'Print :ShuoCredentialServicePrefix' "$source_root/App/Info-Community.plist")" = "org.shuo.community"
  ! /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$source_root/App/Info-Community.plist" >/dev/null 2>&1
  ! /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$source_root/App/Info-Community.plist" >/dev/null 2>&1
  xmllint --noout \
	"$source_root/Shuo.xcodeproj/xcshareddata/xcschemes/Shuo.xcscheme" \
	"$source_root/Shuo.xcodeproj/xcshareddata/xcschemes/ShuoCommunity.xcscheme" \
	"$source_root/Shuo.xcodeproj/xcshareddata/xcschemes/ShuoDirect.xcscheme" \
    "$source_root/web/appcast.xml"

  while IFS= read -r script_file; do
    bash -n "$script_file"
  done < <(find "$source_root/Scripts" -type f -name '*.sh' | sort)

  bash -n "$source_root/Tests/Scripts/community-build-tests.sh"
  "$source_root/Tests/Scripts/community-build-tests.sh"

  local legacy_product_name="Shuo""Type"
  local legacy_product_name_lowercase="shuo""type"
  ! rg -n "$legacy_product_name|$legacy_product_name_lowercase" \
    "$source_root/Shuo.xcodeproj/project.pbxproj" \
    "$source_root/Shuo.xcodeproj/xcshareddata/xcschemes" \
    "$source_root/Scripts" \
    "$source_root/README.md" \
    "$source_root/web"

  # Keep website analytics narrow and auditable. App telemetry remains absent;
  # the public site may load only this production-restricted Umami tracker and
  # the three disclosed, content-free click events.
  local umami_tracker='src="https://cloud.umami.is/script.js" data-website-id="bcb36453-df04-4498-aa66-6ae00ed1094f" data-domains="stcheng.github.io" data-exclude-search="true" data-exclude-hash="true" data-do-not-track="true"'
  local analytics_page
  for analytics_page in index.html privacy.html release-notes.html 404.html; do
    rg -Fq "$umami_tracker" "$source_root/web/$analytics_page"
  done
  test "$(rg -l -F 'src="https://cloud.umami.is/script.js"' "$source_root/web" --glob '*.html' | wc -l | tr -d ' ')" = "4"
  test "$(rg -o -F 'data-umami-event="download-dmg"' "$source_root/web/index.html" | wc -l | tr -d ' ')" = "3"
  test "$(rg -o -F 'data-umami-event="download-zip"' "$source_root/web/index.html" | wc -l | tr -d ' ')" = "1"
  test "$(rg -l -F 'data-umami-event="sponsor-click"' "$source_root/web/index.html" "$source_root/web/privacy.html" "$source_root/web/release-notes.html" | wc -l | tr -d ' ')" = "3"
  local analytics_event_token analytics_event_name
  while IFS= read -r analytics_event_token; do
    analytics_event_name="${analytics_event_token#data-umami-event=\"}"
    analytics_event_name="${analytics_event_name%\"}"
    case "$analytics_event_name" in
      download-dmg | download-zip | sponsor-click)
        ;;
      *)
        echo "Undisclosed website analytics event: $analytics_event_name" >&2
        return 1
        ;;
    esac
  done < <(rg -o --no-filename 'data-umami-event="[^"]+"' \
    "$source_root/web" --glob '*.html')
  rg -Fq 'Umami Cloud' "$source_root/web/privacy.html"
  ! rg -n 'umami\.identify|recorder\.js|data-performance="true"' "$source_root/web"
  ! rg -n \
    'data-analytics-event|window\.plausible|plausible\.io|googletagmanager|gtag\(|mixpanel|posthog|segment\.io|sendBeacon\(' \
    "$source_root/web"

  (
    local site_build
    site_build="$(mktemp -d /tmp/shuo-web-verify.XXXXXX)"
    trap 'rm -rf "$site_build"' EXIT
    rsync -a \
      --exclude 'concepts/' \
      --exclude 'build-localized-site.py' \
      "$source_root/web/" \
      "$site_build/"
    python3 "$source_root/web/build-localized-site.py" \
      --source "$source_root/web" \
      --output "$site_build"
    local language
    for language in en zh-hans zh-hant ja; do
      test -s "$site_build/$language/index.html"
      test -s "$site_build/$language/privacy.html"
      test -s "$site_build/$language/release-notes.html"
    done
    ! rg -n '0\.1\.0' "$site_build" --glob '*.html'
  )
}

run_xcode_checks() {
  local source_root="$1"
  local derived_data="$2"

  xcodebuild test \
    -quiet \
    -project "$source_root/Shuo.xcodeproj" \
    -scheme Shuo \
    -destination "$DESTINATION" \
    -derivedDataPath "$derived_data" \
    "${PACKAGE_RESOLUTION_ARGS[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO

  xcodebuild build \
    -quiet \
    -project "$source_root/Shuo.xcodeproj" \
    -scheme Shuo \
    -configuration Release \
    -destination "$DESTINATION" \
    -derivedDataPath "$derived_data" \
    "${PACKAGE_RESOLUTION_ARGS[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO

  local app_store_app="$derived_data/Build/Products/Release/Shuo.app"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$app_store_app/Contents/Info.plist")" = "Shuo"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_store_app/Contents/Info.plist")" = "1.0.0"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_store_app/Contents/Info.plist")" = "3"
  test -x "$app_store_app/Contents/MacOS/Shuo"
  test -f "$app_store_app/Contents/Resources/LICENSE"
  cmp -s "$source_root/LICENSE" "$app_store_app/Contents/Resources/LICENSE"
  test ! -e "$app_store_app/Contents/Frameworks/Sparkle.framework"
  test "$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsAutomaticTermination' "$app_store_app/Contents/Info.plist")" = "false"
  test "$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsSuddenTermination' "$app_store_app/Contents/Info.plist")" = "false"
  ! /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app_store_app/Contents/Info.plist" >/dev/null 2>&1

  xcodebuild build \
    -quiet \
    -project "$source_root/Shuo.xcodeproj" \
    -scheme ShuoCommunity \
    -configuration Community \
    -destination "$DESTINATION" \
    -derivedDataPath "$derived_data-community" \
    "${PACKAGE_RESOLUTION_ARGS[@]}"

  local community_app="$derived_data-community/Build/Products/Community/Shuo Community.app"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$community_app/Contents/Info.plist")" = "org.shuo.community"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$community_app/Contents/Info.plist")" = "Shuo Community"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$community_app/Contents/Info.plist")" = "1.0.0"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$community_app/Contents/Info.plist")" = "3"
  test -x "$community_app/Contents/MacOS/Shuo Community"
  test -f "$community_app/Contents/Resources/LICENSE"
  cmp -s "$source_root/LICENSE" "$community_app/Contents/Resources/LICENSE"
  test ! -e "$community_app/Contents/Frameworks/Sparkle.framework"
  test "$(/usr/libexec/PlistBuddy -c 'Print :ShuoStorageDirectoryName' "$community_app/Contents/Info.plist")" = "Shuo Community"
  test "$(/usr/libexec/PlistBuddy -c 'Print :ShuoCredentialServicePrefix' "$community_app/Contents/Info.plist")" = "org.shuo.community"
  ! /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$community_app/Contents/Info.plist" >/dev/null 2>&1
  ! /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$community_app/Contents/Info.plist" >/dev/null 2>&1
  codesign --verify --deep --strict "$community_app"
  codesign -dv --verbose=4 "$community_app" 2>&1 | rg -Fq 'Signature=adhoc'
  codesign -dv --verbose=4 "$community_app" 2>&1 | rg -Fq 'TeamIdentifier=not set'

  xcodebuild build \
    -quiet \
    -project "$source_root/Shuo.xcodeproj" \
    -scheme ShuoDirect \
    -configuration Release \
    -destination "$DESTINATION" \
    -derivedDataPath "$derived_data-direct" \
    "${PACKAGE_RESOLUTION_ARGS[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO

  local direct_app="$derived_data-direct/Build/Products/Release/Shuo.app"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$direct_app/Contents/Info.plist")" = "Shuo"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$direct_app/Contents/Info.plist")" = "1.0.0"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$direct_app/Contents/Info.plist")" = "3"
  test -x "$direct_app/Contents/MacOS/Shuo"
  test -f "$direct_app/Contents/Resources/LICENSE"
  cmp -s "$source_root/LICENSE" "$direct_app/Contents/Resources/LICENSE"
  test -d "$direct_app/Contents/Frameworks/Sparkle.framework"
  test "$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsAutomaticTermination' "$direct_app/Contents/Info.plist")" = "false"
  test "$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsSuddenTermination' "$direct_app/Contents/Info.plist")" = "false"
  test "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$direct_app/Contents/Info.plist")" \
    = "https://stcheng.github.io/shuo/appcast.xml"
  test -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$direct_app/Contents/Info.plist")"
}

cd "$ROOT_DIR"

git diff --check
run_static_checks "$ROOT_DIR"
run_xcode_checks "$ROOT_DIR" "$DERIVED_DATA"

"$ROOT_DIR/Scripts/export-public.sh" "$EXPORT_DIR"

test -f "$EXPORT_DIR/App/ShuoApp.swift"
test -f "$EXPORT_DIR/Shuo.xcodeproj/xcshareddata/xcschemes/Shuo.xcscheme"
test -f "$EXPORT_DIR/Shuo.xcodeproj/xcshareddata/xcschemes/ShuoCommunity.xcscheme"
test -f "$EXPORT_DIR/Shuo.xcodeproj/xcshareddata/xcschemes/ShuoDirect.xcscheme"
test -f "$EXPORT_DIR/web/appcast.xml"
test -f "$EXPORT_DIR/.github/workflows/ci.yml"
test -f "$EXPORT_DIR/Evaluation/bilingual-technical-corpus.json"
test ! -d "$EXPORT_DIR/App/App"
test ! -d "$EXPORT_DIR/web/web"

run_static_checks "$EXPORT_DIR"
run_xcode_checks "$EXPORT_DIR" "$EXPORT_DERIVED_DATA"

echo "Verification passed for the working tree and exported public tree."
