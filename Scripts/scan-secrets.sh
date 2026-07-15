#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_PATH="$ROOT_DIR/.gitleaks.toml"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks is required for the full secret scan." >&2
  echo "Install it with: brew install gitleaks" >&2
  exit 2
fi
command -v rsync >/dev/null 2>&1 || {
  echo "rsync is required for the source-tree secret scan." >&2
  exit 2
}

[[ -f "$CONFIG_PATH" ]] || {
  echo "Missing Gitleaks configuration: $CONFIG_PATH" >&2
  exit 2
}

scan_root="$ROOT_DIR"
temporary_scan_root=""
if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  temporary_scan_root="$(mktemp -d /tmp/shuo-gitleaks-tree.XXXXXX)"
  trap 'rm -rf "$temporary_scan_root"' EXIT
  while IFS= read -r -d '' relative_path; do
    if [[ -e "$ROOT_DIR/$relative_path" || -L "$ROOT_DIR/$relative_path" ]]; then
      printf '%s\0' "$relative_path"
    fi
  done < <(git -C "$ROOT_DIR" ls-files -co --exclude-standard -z) \
    | rsync -a --from0 --files-from=- "$ROOT_DIR/" "$temporary_scan_root/"
  scan_root="$temporary_scan_root"
fi

# Scan the complete candidate tree even when no commit exists. In a working
# repository, the temporary tree includes tracked, staged, and non-ignored
# untracked files while excluding DerivedData and other ignored build output.
gitleaks dir \
  --config "$CONFIG_PATH" \
  --redact \
  --no-banner \
  "$scan_root"

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && git -C "$ROOT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
  gitleaks git \
    --config "$CONFIG_PATH" \
    --redact \
    --no-banner \
    --log-opts='--all' \
    "$ROOT_DIR"
fi

echo "Redacted source-tree and available Git-history secret scans passed."
