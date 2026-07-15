#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/sumi-architecture-guard.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT
fixture="$fixture_root/Fixture.swift"
printf '%s\n' 'needle' 'neutral' 'needle' '-prefixed' > "$fixture"

assert_equal() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'error: %s (%s != %s)\n' "$label" "$actual" "$expected" >&2
    exit 1
  fi
}

assert_equal 'line counting' "$(guard_count_lines "$fixture")" 4
assert_equal 'match capture' "$(guard_capture_matches 'needle' "$fixture")" \
  "1:needle
3:needle"
assert_equal 'valid empty capture' "$(guard_capture_matches 'absent' "$fixture")" ''
assert_equal 'option-shaped capture' "$(guard_capture_matches '-prefixed' "$fixture")" \
  '4:-prefixed'
assert_equal 'file capture' "$(guard_capture_files 'needle' "$fixture")" "$fixture"
assert_equal 'valid empty file capture' "$(guard_capture_files 'absent' "$fixture")" ''
assert_equal 'option-shaped file capture' "$(guard_capture_files '-prefixed' "$fixture")" "$fixture"
assert_equal 'match counting' "$(guard_count_matches 'needle' "$fixture")" 2
assert_equal 'valid empty scan' "$(guard_count_matches 'absent' "$fixture")" 0
assert_equal 'option-shaped pattern' "$(guard_count_matches '-prefixed' "$fixture")" 1

if guard_count_lines "$fixture_root/Missing.swift" >/dev/null 2>&1; then
  printf 'error: a missing living source passed line counting\n' >&2
  exit 1
fi

if guard_count_matches 'needle' "$fixture_root/Missing.swift" >/dev/null 2>&1; then
  printf 'error: a missing scan root passed match counting\n' >&2
  exit 1
fi

if guard_capture_matches 'needle' "$fixture_root/Missing.swift" >/dev/null 2>&1; then
  printf 'error: a missing scan root passed match capture\n' >&2
  exit 1
fi

if guard_capture_files 'needle' "$fixture_root/Missing.swift" >/dev/null 2>&1; then
  printf 'error: a missing scan root passed file capture\n' >&2
  exit 1
fi

if guard_count_matches '[' "$fixture" >/dev/null 2>&1; then
  printf 'error: an invalid expression passed match counting\n' >&2
  exit 1
fi

if guard_capture_matches '[' "$fixture" >/dev/null 2>&1; then
  printf 'error: an invalid expression passed match capture\n' >&2
  exit 1
fi

if guard_capture_files '[' "$fixture" >/dev/null 2>&1; then
  printf 'error: an invalid expression passed file capture\n' >&2
  exit 1
fi

guard_failures=0
guard_expect_absent_path 'retired fixture' "$fixture_root/Retired.swift"
printf 'returned\n' > "$fixture_root/Retired.swift"
guard_expect_absent_path 'retired fixture' "$fixture_root/Retired.swift" 2>/dev/null
if guard_finish 'deliberately red self-test' >/dev/null 2>&1; then
  printf 'error: a returned tombstone passed final settlement\n' >&2
  exit 1
fi

printf 'architecture guard DSL passed\n'
