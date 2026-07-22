#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DESTINATION="${1:-$ROOT_DIR/../Shuo-public-export}"
MARKER=".shuo-public-export"

PUBLIC_PATHS=(
  ".github"
  ".gitleaks.toml"
  "App"
  "ARCHITECTURE.md"
  "BUILDING.md"
  "CODE_OF_CONDUCT.md"
  "Config"
  "CONTRIBUTING.md"
  "Evaluation/README.md"
  "Evaluation/bilingual-technical-corpus.json"
  "Evaluation/evaluate_transcripts.py"
  "LICENSE"
  "Makefile"
  "Packaging"
  "README.md"
  "SECURITY.md"
  "Scripts"
  "Shuo.xcodeproj"
  "THIRD_PARTY_NOTICES.md"
  "TRADEMARK.md"
  "Tests"
  "Tools"
  "web"
)

usage() {
  cat <<EOF
Usage: Scripts/export-public.sh [destination]

Copies the curated Shuo application source into a separate public-repository
working tree.
Default destination: ../Shuo-public-export

The export contains source, tests, public documentation, website files, and
release tooling. It intentionally excludes private planning notes, local
credentials, recordings, generated evaluation output, build products, and
private release artifacts.

The destination is marked with $MARKER on first export. If a non-empty
destination is not marked, the script exits instead of overwriting it.
Existing .git metadata is always preserved.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ -L "$DESTINATION" ]]; then
  echo "Refusing to export through a symbolic-link destination: $DESTINATION" >&2
  exit 2
fi

mkdir -p "$DESTINATION"

DESTINATION_PHYSICAL="$(cd -P "$DESTINATION" && pwd -P)"
DESTINATION="$DESTINATION_PHYSICAL"

case "$DESTINATION" in
  "$ROOT_DIR" | "$ROOT_DIR"/*)
    echo "Destination must not be the private working repository or one of its subdirectories." >&2
    exit 2
    ;;
esac

case "$ROOT_DIR" in
  "$DESTINATION"/*)
    echo "Destination must not contain the private working repository." >&2
    exit 2
    ;;
esac

if [[ -L "$DESTINATION/$MARKER" ]]; then
  echo "Refusing to trust a symbolic-link export marker: $DESTINATION/$MARKER" >&2
  exit 2
fi
if [[ -e "$DESTINATION/$MARKER" && ! -f "$DESTINATION/$MARKER" ]]; then
  echo "Refusing to trust a non-file export marker: $DESTINATION/$MARKER" >&2
  exit 2
fi
if [[ -L "$DESTINATION/.git" ]]; then
  echo "Refusing to preserve symbolic-link Git metadata: $DESTINATION/.git" >&2
  exit 2
fi

if [[ -n "$(find "$DESTINATION" -mindepth 1 -maxdepth 1 ! -name "$MARKER" -print -quit)" && ! -f "$DESTINATION/$MARKER" ]]; then
  echo "Refusing to export into a non-empty unmarked directory: $DESTINATION" >&2
  echo "Choose an empty folder or an existing Shuo audit export folder." >&2
  exit 2
fi

touch "$DESTINATION/$MARKER"

find "$DESTINATION" \
  -mindepth 1 \
  -maxdepth 1 \
  ! -name "$MARKER" \
  ! -name ".git" \
  -exec rm -rf {} +

for path in "${PUBLIC_PATHS[@]}"; do
  if [[ -e "$ROOT_DIR/$path" ]]; then
    if [[ -d "$ROOT_DIR/$path" ]]; then
      mkdir -p "$DESTINATION/$path"
      rsync -a \
        --exclude ".DS_Store" \
        --exclude ".build" \
        --exclude ".env" \
        --include ".env.example" \
        --exclude ".env.*" \
        --exclude ".swiftpm" \
        --exclude "*.bin" \
        --exclude "*.dSYM" \
        --exclude "*.keychain-db" \
        --exclude "*.key" \
        --exclude "*.gguf" \
        --exclude "*.aif" \
        --exclude "*.aiff" \
        --exclude "*.caf" \
        --exclude "*.flac" \
        --exclude "*.m4a" \
        --exclude "*.mlmodel" \
        --exclude "*.onnx" \
        --exclude "*.mp3" \
        --exclude "*.p12" \
        --exclude "*.p8" \
        --exclude "*.pem" \
        --exclude "*.pkg" \
        --exclude "*.dmg" \
        --exclude "*.zip" \
        --exclude "*.xcarchive" \
        --exclude "*.xcresult" \
        --exclude "*.mobileprovision" \
        --exclude "*.pyc" \
        --exclude "*.wav" \
        --exclude "Build" \
        --exclude "build" \
        --exclude "concepts" \
        --exclude "DerivedData" \
        --exclude "__pycache__" \
        --exclude "dist" \
        --exclude "hypotheses*.json" \
        --exclude "recordings" \
        --exclude "results*.json" \
        --exclude "xcuserdata" \
        --exclude "*.xcuserstate" \
        "$ROOT_DIR/$path/" \
        "$DESTINATION/$path/"
    else
      mkdir -p "$DESTINATION/$(dirname "$path")"
      rsync -a "$ROOT_DIR/$path" "$DESTINATION/$path"
    fi
  fi
done

PUBLIC_GITIGNORE_SOURCE="$ROOT_DIR/.public-gitignore"
if [[ ! -f "$PUBLIC_GITIGNORE_SOURCE" ]]; then
  PUBLIC_GITIGNORE_SOURCE="$ROOT_DIR/.gitignore"
fi
rsync -a "$PUBLIC_GITIGNORE_SOURCE" "$DESTINATION/.gitignore"

REQUIRED_PATHS=(
  ".github/ISSUE_TEMPLATE/bug_report.yml"
  ".github/ISSUE_TEMPLATE/config.yml"
  ".github/ISSUE_TEMPLATE/feature_request.yml"
  ".github/FUNDING.yml"
  ".github/pull_request_template.md"
  ".github/workflows/ci.yml"
  ".gitleaks.toml"
  "ARCHITECTURE.md"
  "App/Info-Community.plist"
  "App/Resources/ThirdParty/OpenAI-Whisper-LICENSE.txt"
  "App/Resources/ThirdParty/SenseVoice-LICENSE.txt"
  "App/Resources/ThirdParty/SenseVoiceSmall-GGUF-LICENSE.txt"
  "App/Resources/ThirdParty/Sparkle-LICENSE.txt"
  "App/Resources/ThirdParty/Unicode-CLDR-LICENSE.txt"
  "App/Resources/ThirdParty/llama.cpp-LICENSE.txt"
  "App/ShuoApp.swift"
  "BUILDING.md"
  "CODE_OF_CONDUCT.md"
  "CONTRIBUTING.md"
  "LICENSE"
  "Makefile"
  "Packaging/DMG/background.png"
  "Packaging/DMG/background@2x.png"
  "Packaging/DMG/layout.dsstore"
  "SECURITY.md"
  "Scripts/audit-public-source.sh"
  "Scripts/export-public.sh"
  "Scripts/embed-sensevoice-runtime.sh"
  "Scripts/initialize-public-repository.sh"
  "Scripts/patches/sensevoice-segment-delimiters.patch"
  "Scripts/prepare-sensevoice-runtime.sh"
  "Scripts/scan-secrets.sh"
  "Scripts/verify-release-artifacts.sh"
  "README.md"
  "Shuo.xcodeproj/project.pbxproj"
  "Shuo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  "Shuo.xcodeproj/xcshareddata/xcschemes/ShuoCommunity.xcscheme"
  "THIRD_PARTY_NOTICES.md"
  "Tests/Scripts/export-public-tests.sh"
  "Tests/Scripts/appcast-security-tests.sh"
  "Tests/Scripts/community-build-tests.sh"
  "Tests/Scripts/release-packaging-tests.sh"
  "Tests/ShuoTests/ShuoCoreTests.swift"
  "TRADEMARK.md"
  "Evaluation/bilingual-technical-corpus.json"
  "Evaluation/README.md"
  "Evaluation/evaluate_transcripts.py"
  "web/index.html"
  "web/privacy.html"
  "web/release-notes.html"
  "web/appcast.xml"
)

for path in "${REQUIRED_PATHS[@]}"; do
  if [[ ! -e "$DESTINATION/$path" ]]; then
    echo "Export validation failed; missing: $path" >&2
    exit 1
  fi
done

PROHIBITED_PATHS=(
  ".public-gitignore"
  "NOTES.md"
  "errors"
  "dist"
  "build"
  "Build"
  "DerivedData"
  "Evaluation/recordings"
  "EvaluationPrivate"
  "Internal"
  "InternalScripts"
  "InternalTests"
  "web/concepts"
  "docs/open-source-1.0-progress.md"
  "docs/optimization-progress-2026-07.md"
  "docs/personal-voice-platform-brainstorm.md"
  "docs/release-plan-2026-06-22.md"
  "docs/release-plan-2026-07-08.md"
  "docs/bilingual-release-smoke-test.md"
  "docs/good-first-issues.md"
  "docs/public-repo-plan.md"
  "docs/public-surface-policy.md"
)

for path in "${PROHIBITED_PATHS[@]}"; do
  if [[ -e "$DESTINATION/$path" ]]; then
    echo "Export validation failed; private path was copied: $path" >&2
    exit 1
  fi
done

if find "$DESTINATION" \
  -path "$DESTINATION/.git" -prune -o \
  \( \
    -name '.env' \
    -o -name '.build' \
    -o -name 'build' \
    -o -name 'Build' \
    -o -name 'DerivedData' \
    -o -name 'dist' \
    -o \( -name '.env.*' ! -name '.env.example' \) \
    -o -name '*.bin' \
    -o -name '*.dSYM' \
    -o -name '*.keychain-db' \
    -o -name '*.key' \
    -o -name '*.gguf' \
    -o -name '*.aif' \
    -o -name '*.aiff' \
    -o -name '*.caf' \
    -o -name '*.flac' \
    -o -name '*.m4a' \
    -o -name '*.mlmodel' \
    -o -name '*.onnx' \
    -o -name '*.mp3' \
    -o -name '*.p12' \
    -o -name '*.p8' \
    -o -name '*.pem' \
    -o -name '*.pkg' \
    -o -name '*.dmg' \
    -o -name '*.zip' \
    -o -name '*.xcarchive' \
    -o -name '*.xcresult' \
    -o -name '*.mobileprovision' \
    -o -name '*.wav' \
  \) \
  -print -quit | grep -q .; then
  echo "Export validation failed; a credential, model, private audio, or release artifact was copied." >&2
  exit 1
fi

cat <<EOF
Exported public tree to:
  $DESTINATION

This tree is suitable for a fresh public Git history after review. Private-only
files such as NOTES.md, internal progress/release plans, DerivedData, dist,
local credentials, evaluation audio, generated results, and model files are
not part of the public allowlist.
EOF
