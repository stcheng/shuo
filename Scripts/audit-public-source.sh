#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
ROOT_DIR="$(cd -P "$ROOT_DIR" && pwd -P)"

fail() {
  echo "Public source audit failed: $*" >&2
  exit 1
}

for command_name in awk find jq rg shasum; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "missing command: $command_name"
done

for required_path in \
  LICENSE \
  TRADEMARK.md \
  CONTRIBUTING.md \
  CODE_OF_CONDUCT.md \
  BUILDING.md \
  ARCHITECTURE.md \
  SECURITY.md \
  THIRD_PARTY_NOTICES.md \
  App/Resources/ThirdParty/OpenAI-Whisper-LICENSE.txt \
  App/Resources/ThirdParty/SenseVoice-LICENSE.txt \
  App/Resources/ThirdParty/SenseVoiceSmall-GGUF-LICENSE.txt \
  App/Resources/ThirdParty/Sparkle-LICENSE.txt \
  App/Resources/ThirdParty/Unicode-CLDR-LICENSE.txt \
  App/Resources/ThirdParty/llama.cpp-LICENSE.txt \
  Scripts/package-app.sh \
  Scripts/embed-sensevoice-runtime.sh \
  Scripts/patches/sensevoice-segment-delimiters.patch \
  Scripts/prepare-sensevoice-runtime.sh \
  Scripts/prepare-whisper-runtime.sh \
  Shuo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved; do
  [[ -f "$ROOT_DIR/$required_path" ]] \
    || fail "missing required file: $required_path"
done

rg -Fq 'VERSION="${SHUO_WHISPER_CPP_VERSION:-1.8.6}"' \
  "$ROOT_DIR/Scripts/prepare-whisper-runtime.sh" \
  || fail "whisper.cpp development default is no longer 1.8.6"
rg -Fq 'f8e632016ceae556f3132a16c7f704be1e7715595041f474fa81a2b64c1abf7c' \
  "$ROOT_DIR/Scripts/prepare-whisper-runtime.sh" \
  "$ROOT_DIR/Scripts/package-app.sh" \
  || fail "whisper.cpp source hash pin is missing"
rg -Fq 'PINNED_WHISPER_CPP_VERSION="1.8.6"' \
  "$ROOT_DIR/Scripts/package-app.sh" \
  || fail "formal release does not pin whisper.cpp 1.8.6"
rg -Fq 'RUNTIME_VERSION="${SHUO_SENSEVOICE_RUNTIME_VERSION:-0.1.4}"' \
  "$ROOT_DIR/Scripts/prepare-sensevoice-runtime.sh" \
  || fail "SenseVoice runtime development default is no longer 0.1.4"
rg -Fq '9c67454515426253a0fb9bbe4f1bd1b836066b3396e2ea8ea1a4a1b3c0d506af' \
  "$ROOT_DIR/Scripts/prepare-sensevoice-runtime.sh" \
  "$ROOT_DIR/Scripts/package-app.sh" \
  || fail "SenseVoice runtime source hash pin is missing"
rg -Fq '1984103666eb25bd45110a40cba22b9d4286116f26e51bbc76f6f41dc86bc7b5' \
  "$ROOT_DIR/Scripts/prepare-sensevoice-runtime.sh" \
  "$ROOT_DIR/Scripts/package-app.sh" \
  || fail "SenseVoice llama.cpp source hash pin is missing"
rg -Fq 'PINNED_SENSEVOICE_RUNTIME_VERSION="0.1.4"' \
  "$ROOT_DIR/Scripts/package-app.sh" \
  || fail "formal release does not pin SenseVoice runtime 0.1.4"
rg -Fq '16b5a7420bfb79fe4d6a4564adf2bae8552735413f46fd80d2e2f234063e955a' \
  "$ROOT_DIR/Scripts/prepare-sensevoice-runtime.sh" \
  "$ROOT_DIR/Scripts/package-app.sh" \
  "$ROOT_DIR/Scripts/verify-release-artifacts.sh" \
  || fail "SenseVoice segment-delimiter patch pin is missing"
[[ "$(shasum -a 256 "$ROOT_DIR/Scripts/patches/sensevoice-segment-delimiters.patch" | awk '{print $1}')" \
    == "16b5a7420bfb79fe4d6a4564adf2bae8552735413f46fd80d2e2f234063e955a" ]] \
  || fail "SenseVoice segment-delimiter patch changed without a pin update"

rg -Fq 'GNU GENERAL PUBLIC LICENSE' "$ROOT_DIR/LICENSE" \
  || fail "LICENSE is not the GPL text"
rg -Fq 'Version 3, 29 June 2007' "$ROOT_DIR/LICENSE" \
  || fail "LICENSE is not GPL version 3"
rg -Fq 'Shuo' "$ROOT_DIR/TRADEMARK.md" \
  || fail "trademark policy does not identify Shuo"

package_file="$ROOT_DIR/Shuo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
[[ "$(jq '.pins | length' "$package_file")" == "1" ]] \
  || fail "SwiftPM dependency allowlist changed"
[[ "$(jq -r '.pins[0].identity' "$package_file")" == "sparkle" ]] \
  || fail "unexpected SwiftPM dependency"
[[ "$(jq -r '.pins[0].location' "$package_file")" == "https://github.com/sparkle-project/Sparkle" ]] \
  || fail "Sparkle resolves from an unexpected repository"
[[ "$(jq -r '.pins[0].state.version' "$package_file")" == "2.9.4" ]] \
  || fail "Sparkle version changed without a notice review"
[[ "$(jq -r '.pins[0].state.revision' "$package_file")" == "b6496a74a087257ef5e6da1c5b29a447a60f5bd7" ]] \
  || fail "Sparkle 2.9.4 resolved to an unexpected revision"
rg -Fq 'kind = exactVersion;' "$ROOT_DIR/Shuo.xcodeproj/project.pbxproj" \
  || fail "the Xcode project does not require an exact Sparkle version"
rg -Fq 'version = 2.9.4;' "$ROOT_DIR/Shuo.xcodeproj/project.pbxproj" \
  || fail "the Xcode project does not require Sparkle 2.9.4 exactly"

for notice in \
  'Sparkle 2.9.4' \
  'whisper.cpp 1.8.6' \
  'SenseVoice llama.cpp runtime 0.1.4' \
  'SenseVoiceSmall GGUF and FSMN-VAD model weights' \
  'OpenAI Whisper model weights' \
  'Unicode CLDR annotation data'; do
  rg -Fq "$notice" "$ROOT_DIR/THIRD_PARTY_NOTICES.md" \
    || fail "THIRD_PARTY_NOTICES is missing: $notice"
done

rg -Fq 'Permission is hereby granted, free of charge' \
  "$ROOT_DIR/App/Resources/ThirdParty/OpenAI-Whisper-LICENSE.txt" \
  || fail "OpenAI Whisper license text is incomplete"
rg -Fq 'Permission is hereby granted, free of charge' \
  "$ROOT_DIR/App/Resources/ThirdParty/Sparkle-LICENSE.txt" \
  || fail "Sparkle license text is incomplete"
rg -Fq 'UNICODE LICENSE V3' \
  "$ROOT_DIR/App/Resources/ThirdParty/Unicode-CLDR-LICENSE.txt" \
  || fail "Unicode CLDR license text is incomplete"
rg -Fq 'Permission is hereby granted, free of charge' \
  "$ROOT_DIR/App/Resources/ThirdParty/SenseVoice-LICENSE.txt" \
  || fail "SenseVoice license text is incomplete"
rg -Fq 'Apache License' \
  "$ROOT_DIR/App/Resources/ThirdParty/SenseVoiceSmall-GGUF-LICENSE.txt" \
  || fail "SenseVoiceSmall GGUF license text is incomplete"
rg -Fq 'Permission is hereby granted, free of charge' \
  "$ROOT_DIR/App/Resources/ThirdParty/llama.cpp-LICENSE.txt" \
  || fail "llama.cpp license text is incomplete"

while IFS=' ' read -r expected_hash relative_path; do
  actual_hash="$(shasum -a 256 "$ROOT_DIR/$relative_path" | awk '{print $1}')"
  [[ "$actual_hash" == "$expected_hash" ]] \
    || fail "canonical license text changed: $relative_path"
done <<'HASHES'
3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986 LICENSE
b5d65a59060e68c4ff940e1eddfa6f94b2d68fdf58ed7f4dd57721c997e35e9d App/Resources/ThirdParty/OpenAI-Whisper-LICENSE.txt
389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe App/Resources/ThirdParty/Sparkle-LICENSE.txt
220ba0e1c43b99530d2d5bdb892a99dca0989414f51ab695ecd90163eaa1ec3b App/Resources/ThirdParty/Unicode-CLDR-LICENSE.txt
4bc3bffe14ebe38cc67309991e04f92866835eac1c5e2e1abd37163f67c6de5f App/Resources/ThirdParty/SenseVoice-LICENSE.txt
7ac4eb17fc25e904a4935e43ac31cebea0597c7c06210292699af1eb2d96551d App/Resources/ThirdParty/SenseVoiceSmall-GGUF-LICENSE.txt
94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d App/Resources/ThirdParty/llama.cpp-LICENSE.txt
HASHES

prohibited_file="$(find "$ROOT_DIR" \
  \( \
    -path "$ROOT_DIR/.git" \
    -o -name '.build' \
    -o -name 'build' \
    -o -name 'Build' \
    -o -name 'DerivedData' \
    -o -name 'dist' \
  \) -prune -o \
  \( \
    -name '.env' \
    -o \( -name '.env.*' ! -name '.env.example' \) \
    -o -name '*.bin' \
    -o -name '*.dSYM' \
    -o -name '*.gguf' \
    -o -name '*.aif' \
    -o -name '*.aiff' \
    -o -name '*.caf' \
    -o -name '*.flac' \
    -o -name '*.key' \
    -o -name '*.keychain-db' \
    -o -name '*.m4a' \
    -o -name '*.mlmodel' \
    -o -name '*.mobileprovision' \
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
    -o -name '*.wav' \
  \) \
  -print -quit)"
[[ -z "$prohibited_file" ]] \
  || fail "credential, model, private audio, or release artifact is present: $prohibited_file"

if [[ -f "$ROOT_DIR/.shuo-public-export" ]]; then
  prohibited_export_directory="$(find "$ROOT_DIR" \
    -path "$ROOT_DIR/.git" -prune -o \
    -type d \
    \( \
      -name '.build' \
      -o -name 'build' \
      -o -name 'Build' \
      -o -name 'DerivedData' \
      -o -name 'dist' \
      -o -name '*.xcresult' \
    \) \
    -print -quit)"
  [[ -z "$prohibited_export_directory" ]] \
    || fail "generated directory is present in the curated export: $prohibited_export_directory"
fi

# Cover only high-confidence credential formats. Public identifiers such as the
# Apple Team ID, Sparkle public key, Umami site ID, URLs, and test placeholders
# are intentionally not treated as secrets.
credential_paths="$(rg -l --hidden \
  --glob '!.git/**' \
  --glob '!.build/**' \
  --glob '!build/**' \
  --glob '!Build/**' \
  --glob '!DerivedData/**' \
  --glob '!dist/**' \
  '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|sk-(proj-|svcacct-)[A-Za-z0-9_-]{20,})' \
  "$ROOT_DIR" || true)"
if [[ -n "$credential_paths" ]]; then
  fail "a high-confidence credential pattern was found in: $credential_paths"
fi

echo "Public source and dependency-license audit passed."
