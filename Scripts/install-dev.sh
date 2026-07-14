#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${SHUO_APP_NAME:-Shuo}"
DATA_NAMESPACE="${SHUO_DATA_NAMESPACE:-Shuo}"
SCHEME="${SHUO_SCHEME:-ShuoDirect}"
CONFIGURATION="${SHUO_CONFIGURATION:-Release}"
SIGN_IDENTITY="${SHUO_CODESIGN_IDENTITY:-Shuo Local Development}"
SIGN_MODE="${SHUO_SIGN_MODE:-local}"
KEYCHAIN="${SHUO_KEYCHAIN:-$HOME/Library/Keychains/shuo-development.keychain-db}"
RESOLVED_SIGN_IDENTITY="$SIGN_IDENTITY"
SIGNING_KEYCHAIN=""
NEEDS_CODESIGN_ACCESS_PREFLIGHT=0
DERIVED_DATA="${SHUO_DERIVED_DATA:-$ROOT_DIR/DerivedData/Install}"
REQUESTED_INSTALL_DIR="${SHUO_INSTALL_DIR:-/Applications}"
PKCS12_PASSWORD="${SHUO_PKCS12_PASSWORD:-shuo-local-development}"
KEYCHAIN_PASSWORD="${SHUO_KEYCHAIN_PASSWORD:-shuo-local-development}"
ENTITLEMENTS="${SHUO_ENTITLEMENTS:-$ROOT_DIR/App/ShuoDirect.entitlements}"

if [[ -w "$REQUESTED_INSTALL_DIR" ]]; then
  INSTALL_DIR="$REQUESTED_INSTALL_DIR"
else
  INSTALL_DIR="$HOME/Applications"
fi

APP_SOURCE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_DESTINATION="$INSTALL_DIR/$APP_NAME.app"
RUNTIME_DIR="$HOME/Library/Application Support/$DATA_NAMESPACE/Runtime"
EXPECTED_RESTART_MARKER="$RUNTIME_DIR/expected-restart.json"

ensure_local_codesign_identity() {
  local existing_identity
  existing_identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -v name="$SIGN_IDENTITY" 'index($0, "\"" name "\"") { print $2; exit }'
  )"
  if [[ -n "$existing_identity" ]]; then
    RESOLVED_SIGN_IDENTITY="$existing_identity"
    SIGNING_KEYCHAIN=""
    NEEDS_CODESIGN_ACCESS_PREFLIGHT=1
    echo "Using existing stable signing identity: $SIGN_IDENTITY"
    return
  fi

  if [[ ! -f "$KEYCHAIN" ]]; then
    echo "Creating dedicated Shuo development keychain"
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  fi

  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"

  if security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "\"$SIGN_IDENTITY\""; then
    return
  fi

  local work_dir
  work_dir="$(mktemp -d)"

  if ! security find-certificate -c "$SIGN_IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Creating local code signing identity: $SIGN_IDENTITY"
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
      -A \
      -T /usr/bin/codesign \
      -T /usr/bin/security >/dev/null
  else
    security find-certificate \
      -c "$SIGN_IDENTITY" \
      -p \
      "$KEYCHAIN" > "$work_dir/cert.pem"
  fi

  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN" >/dev/null

  echo "Trusting the Shuo development certificate (one-time macOS approval may appear)"
  security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN" \
    "$work_dir/cert.pem" >/dev/null 2>&1

  rm -rf "$work_dir"

  if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "\"$SIGN_IDENTITY\""; then
    echo "The Shuo development signing identity is not trusted." >&2
    exit 1
  fi

  RESOLVED_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning "$KEYCHAIN" \
      | awk -v name="$SIGN_IDENTITY" 'index($0, "\"" name "\"") { print $2; exit }'
  )"
  SIGNING_KEYCHAIN="$KEYCHAIN"
}

preflight_codesign_access() {
  if [[ "$SIGN_MODE" != "local" || "$NEEDS_CODESIGN_ACCESS_PREFLIGHT" != "1" ]]; then
    return
  fi

  local probe_executable="$APP_SOURCE/Contents/MacOS/$APP_NAME"
  if [[ ! -f "$probe_executable" ]]; then
    echo "Signing access probe could not find $probe_executable." >&2
    exit 1
  fi

  cat <<EOF
Checking persistent access to the existing "$SIGN_IDENTITY" private key.
If macOS shows a Keychain dialog, choose Always Allow (not Allow) once.
This keeps the same certificate so Shuo's existing macOS permissions remain attached.
EOF

  if ! codesign \
    --force \
    --options runtime \
    --timestamp=none \
    --sign "$RESOLVED_SIGN_IDENTITY" \
    "$probe_executable"; then
    echo "Could not authorize the existing Shuo signing identity." >&2
    exit 1
  fi
}

build_app() {
  xcodebuild \
    -project "$ROOT_DIR/Shuo.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -onlyUsePackageVersionsFromResolvedFile \
    -disableAutomaticPackageResolution \
    -skipPackageUpdates \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    build
}

codesign_with_resolved_keychain() {
  if [[ -n "$SIGNING_KEYCHAIN" ]]; then
    codesign --keychain "$SIGNING_KEYCHAIN" "$@"
  else
    codesign "$@"
  fi
}

remove_interrupted_codesign_artifacts() {
  # codesign can leave sibling *.cstemp executables when a Keychain prompt is
  # cancelled or interrupted. A later parent-bundle signature would seal those
  # transient files and become invalid as soon as codesign removes them.
  find "$APP_SOURCE" -name '*.cstemp' -type f -delete
}

sign_app() {
  local identity
  local signing_entitlements="$ENTITLEMENTS"
  local local_entitlements=""
  if [[ "$SIGN_MODE" == "local" ]]; then
    identity="$RESOLVED_SIGN_IDENTITY"
    local_entitlements="$(mktemp)"
    cp "$ENTITLEMENTS" "$local_entitlements"
    /usr/libexec/PlistBuddy \
      -c 'Add :com.apple.security.cs.disable-library-validation bool true' \
      "$local_entitlements"
    signing_entitlements="$local_entitlements"
  else
    identity=-
  fi

  local sparkle="$APP_SOURCE/Contents/Frameworks/Sparkle.framework"
  if [[ -d "$sparkle" ]]; then
    codesign_with_resolved_keychain --force --options runtime --timestamp=none --sign "$identity" \
      "$sparkle/Versions/B/XPCServices/Installer.xpc"
    codesign_with_resolved_keychain --force --options runtime --preserve-metadata=entitlements \
      --timestamp=none --sign "$identity" \
      "$sparkle/Versions/B/XPCServices/Downloader.xpc"
    codesign_with_resolved_keychain --force --options runtime --timestamp=none --sign "$identity" \
      "$sparkle/Versions/B/Autoupdate"
    codesign_with_resolved_keychain --force --options runtime --timestamp=none --sign "$identity" \
      "$sparkle/Versions/B/Updater.app"
    codesign_with_resolved_keychain --force --options runtime --timestamp=none --sign "$identity" "$sparkle"
  fi

  local whisper_runtime="$APP_SOURCE/Contents/Resources/Runtime/whisper-cli"
  if [[ -x "$whisper_runtime" ]]; then
    codesign_with_resolved_keychain --force --options runtime --timestamp=none --sign "$identity" "$whisper_runtime"
  fi

  case "$SIGN_MODE" in
    local)
      if ! codesign_with_resolved_keychain \
        --force \
        --options runtime \
        --entitlements "$signing_entitlements" \
        --timestamp=none \
        --sign "$identity" \
        "$APP_SOURCE"; then
        rm -f "$local_entitlements"
        return 1
      fi
      rm -f "$local_entitlements"
      ;;
    adhoc)
      codesign \
        --force \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --timestamp=none \
        --sign - \
        "$APP_SOURCE"
      ;;
    *)
      echo "Unknown SHUO_SIGN_MODE '$SIGN_MODE'. Use 'local' or 'adhoc'." >&2
      exit 2
      ;;
  esac
}

mark_development_build() {
  local info_plist="$APP_SOURCE/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Delete :ShuoDevelopmentBuild' "$info_plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c 'Add :ShuoDevelopmentBuild bool true' "$info_plist"
}

request_app_quit() {
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 &
  local osascript_pid=$!

  for _ in {1..10}; do
    if ! kill -0 "$osascript_pid" >/dev/null 2>&1; then
      wait "$osascript_pid" >/dev/null 2>&1 || true
      return
    fi
    sleep 0.1
  done

  kill "$osascript_pid" >/dev/null 2>&1 || true
  wait "$osascript_pid" >/dev/null 2>&1 || true
}

mark_expected_dev_restart() {
  mkdir -p "$RUNTIME_DIR"

  local created_at
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  cat > "$EXPECTED_RESTART_MARKER" <<EOF
{
  "createdAt" : "$created_at",
  "reason" : "dev-install"
}
EOF
}

install_app() {
  mkdir -p "$INSTALL_DIR"

  if pgrep -x "$APP_NAME" >/dev/null; then
    mark_expected_dev_restart
    request_app_quit

    for _ in {1..20}; do
      if ! pgrep -x "$APP_NAME" >/dev/null; then
        break
      fi
      sleep 0.2
    done

    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    sleep 0.5
  fi

  rm -rf "$APP_DESTINATION"
  ditto "$APP_SOURCE" "$APP_DESTINATION"
  codesign --verify --deep --strict --verbose=2 "$APP_DESTINATION"
}

open_app() {
  if open "$APP_DESTINATION"; then
    return
  fi

  sleep 1

  if ! open "$APP_DESTINATION"; then
    echo "Warning: installed app, but macOS did not launch it automatically. Open $APP_DESTINATION manually."
  fi
}

main() {
  echo "Installing $APP_NAME to $APP_DESTINATION"
  if [[ "$SIGN_MODE" == "local" ]]; then
    ensure_local_codesign_identity
  fi
  build_app
  "$ROOT_DIR/Scripts/embed-whisper-runtime.sh" "$APP_SOURCE"
  mark_development_build
  remove_interrupted_codesign_artifacts
  preflight_codesign_access
  sign_app
  install_app
  open_app

  cat <<EOF

Installed: $APP_DESTINATION

Use this installed app for daily testing instead of Xcode Run.
After the first successful install, grant Accessibility permission to this app once.
The default stable signing mode keeps macOS Accessibility permission attached across rebuilds.
If macOS asks codesign to access the "$SIGN_IDENTITY" key, choose Always Allow once.
Use make install-dev-adhoc only when you need to avoid local signing keychain access.
EOF
}

main "$@"
