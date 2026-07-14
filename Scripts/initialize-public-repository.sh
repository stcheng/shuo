#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${1:-$ROOT_DIR/../Shuo-public}"

usage() {
  cat <<EOF
Usage: Scripts/initialize-public-repository.sh [destination]

Creates a fresh, source-bearing public Git working tree from the curated export.
It never copies private Git history, never configures a remote, and leaves the
initial files staged but uncommitted for human review.

Default destination: ../Shuo-public
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ -L "$DESTINATION" ]]; then
  echo "Refusing to initialize a public repository through a symbolic link: $DESTINATION" >&2
  exit 2
fi

if [[ -e "$DESTINATION" && -n "$(find "$DESTINATION" -mindepth 1 -print -quit)" ]]; then
  echo "Public repository destination must be new or empty: $DESTINATION" >&2
  exit 2
fi

if [[ "$(git -C "$ROOT_DIR" rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]]; then
  echo "The private source must be a Git working tree." >&2
  exit 2
fi

source_status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)"
if [[ -n "$source_status" ]]; then
  echo "Commit and verify the private source before creating public history." >&2
  printf '%s\n' "$source_status" >&2
  exit 2
fi

"$ROOT_DIR/Scripts/export-public.sh" "$DESTINATION"
"$DESTINATION/Scripts/audit-public-source.sh" "$DESTINATION"
"$DESTINATION/Scripts/scan-secrets.sh" "$DESTINATION"
rm -f "$DESTINATION/.shuo-public-export"

git -C "$DESTINATION" init -b main
git -C "$DESTINATION" config user.name "${SHUO_PUBLIC_GIT_NAME:-Boliang Dai}"
git -C "$DESTINATION" config user.email \
  "${SHUO_PUBLIC_GIT_EMAIL:-stcheng@users.noreply.github.com}"
git -C "$DESTINATION" add -A

if git -C "$DESTINATION" diff --cached --quiet; then
  echo "Public repository initialization produced no staged files." >&2
  exit 1
fi

cat <<EOF
Initialized a fresh public repository at:
  $(cd "$DESTINATION" && pwd -P)

No remote was configured and no commit was created. Review every staged path:
  git -C "$DESTINATION" status --short
  git -C "$DESTINATION" diff --cached --stat
  git -C "$DESTINATION" diff --cached

The repository-local author identity is:
  $(git -C "$DESTINATION" config user.name) <$(git -C "$DESTINATION" config user.email)>

Override it before committing only with a deliberately public address, or set
SHUO_PUBLIC_GIT_NAME and SHUO_PUBLIC_GIT_EMAIL when running this initializer.

After review, create the one curated initial commit:
  git -C "$DESTINATION" commit -m "Initial public source release"
EOF
