#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
EXPORT_SCRIPT="$ROOT_DIR/Scripts/export-public.sh"
WORK_DIR="$(mktemp -d /tmp/shuo-public-export-tests.XXXXXX)"
PRIVATE_BUILD_FIXTURE="$ROOT_DIR/Tests/build/shuo-private-export-fixture.txt"
PRIVATE_XCRESULT_FIXTURE="$ROOT_DIR/Tests/shuo-private-export-fixture.xcresult/log.txt"

cleanup() {
  rm -rf "$WORK_DIR"
  rm -rf \
    "$ROOT_DIR/Tests/build" \
    "$ROOT_DIR/Tests/shuo-private-export-fixture.xcresult"
}
trap cleanup EXIT

fail() {
  echo "Public export test failed: $*" >&2
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

bash -n "$EXPORT_SCRIPT"

[[ ! -e "$ROOT_DIR/Tests/build" ]] \
  || fail "test fixture path already exists: $ROOT_DIR/Tests/build"
[[ ! -e "$ROOT_DIR/Tests/shuo-private-export-fixture.xcresult" ]] \
  || fail "test fixture path already exists: $ROOT_DIR/Tests/shuo-private-export-fixture.xcresult"
mkdir -p \
  "$(dirname "$PRIVATE_BUILD_FIXTURE")" \
  "$(dirname "$PRIVATE_XCRESULT_FIXTURE")"
printf 'private build output\n' >"$PRIVATE_BUILD_FIXTURE"
printf 'private test result\n' >"$PRIVATE_XCRESULT_FIXTURE"

PUBLIC_REPOSITORY="$WORK_DIR/public"
"$EXPORT_SCRIPT" "$PUBLIC_REPOSITORY" >/dev/null
[[ -f "$PUBLIC_REPOSITORY/.shuo-public-export" ]] \
  || fail "new export is missing its safety marker"
for required_path in \
  .gitleaks.toml \
  .github/FUNDING.yml \
  .github/pull_request_template.md \
  ARCHITECTURE.md \
  BUILDING.md \
  CODE_OF_CONDUCT.md \
  CONTRIBUTING.md \
  docs/good-first-issues.md \
  LICENSE \
  Packaging/DMG/background.png \
  Tests/Scripts/appcast-security-tests.sh \
  TRADEMARK.md; do
  [[ -f "$PUBLIC_REPOSITORY/$required_path" ]] \
    || fail "new export is missing public source file: $required_path"
done
for private_path in \
  NOTES.md \
  errors \
  docs/open-source-1.0-progress.md \
  docs/optimization-progress-2026-07.md \
  docs/release-plan-2026-07-08.md; do
  [[ ! -e "$PUBLIC_REPOSITORY/$private_path" ]] \
    || fail "new export leaked private path: $private_path"
done
[[ ! -e "$PUBLIC_REPOSITORY/web/concepts" ]] \
  || fail "new export leaked website concept drafts"
[[ ! -e "$PUBLIC_REPOSITORY/Tests/build" ]] \
  || fail "new export leaked an ignored nested build directory"
[[ ! -e "$PUBLIC_REPOSITORY/Tests/shuo-private-export-fixture.xcresult" ]] \
  || fail "new export leaked an ignored xcresult bundle"
[[ "$(find "$PUBLIC_REPOSITORY/Evaluation" -type f | wc -l | tr -d ' ')" == "3" ]] \
  || fail "new export copied an unapproved Evaluation file"

mkdir -p "$PUBLIC_REPOSITORY/.git"
printf 'preserve me\n' >"$PUBLIC_REPOSITORY/.git/export-test-sentinel"
printf 'remove me\n' >"$PUBLIC_REPOSITORY/stale-private-file"
"$EXPORT_SCRIPT" "$PUBLIC_REPOSITORY" >/dev/null
[[ -f "$PUBLIC_REPOSITORY/.git/export-test-sentinel" ]] \
  || fail "a repeated export removed public Git metadata"
[[ ! -e "$PUBLIC_REPOSITORY/stale-private-file" ]] \
  || fail "a repeated export did not remove stale exported content"

UNMARKED="$WORK_DIR/unmarked"
mkdir -p "$UNMARKED"
printf 'do not overwrite\n' >"$UNMARKED/user-file"
assert_failure_contains 'non-empty unmarked directory' \
  "$EXPORT_SCRIPT" "$UNMARKED"
[[ -f "$UNMARKED/user-file" ]] \
  || fail "the unmarked destination was modified"

SYMLINK_DESTINATION="$WORK_DIR/public-link"
ln -s "$PUBLIC_REPOSITORY" "$SYMLINK_DESTINATION"
assert_failure_contains 'symbolic-link destination' \
  "$EXPORT_SCRIPT" "$SYMLINK_DESTINATION"

INVALID_MARKER="$WORK_DIR/invalid-marker"
mkdir -p "$INVALID_MARKER/.shuo-public-export"
assert_failure_contains 'non-file export marker' \
  "$EXPORT_SCRIPT" "$INVALID_MARKER"

SYMLINK_GIT="$WORK_DIR/symlink-git"
mkdir -p "$SYMLINK_GIT"
touch "$SYMLINK_GIT/.shuo-public-export"
ln -s "$PUBLIC_REPOSITORY/.git" "$SYMLINK_GIT/.git"
assert_failure_contains 'symbolic-link Git metadata' \
  "$EXPORT_SCRIPT" "$SYMLINK_GIT"

assert_failure_contains 'private working repository' \
  "$EXPORT_SCRIPT" "$ROOT_DIR"
assert_failure_contains 'contain the private working repository' \
  "$EXPORT_SCRIPT" "$(dirname "$ROOT_DIR")"

echo "Public export safety tests passed."
