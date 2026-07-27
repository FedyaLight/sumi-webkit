#!/usr/bin/env bash
# SumiTests file LOC soft freeze (R7 harness).
#
# Existing mega-files are grandfathered under a hard ceiling of 2260. The
# pre-existing SpaceSidebarTransitionStateTests outlier has its own exact
# ceiling. Files above 1500 still warn until a split lands.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

tests_dir="SumiTests"
warn_loc=1500
fail_loc=2260
space_sidebar_transition_fail_loc=2270
failures=0
warnings=0

printf '%s\n' 'SumiTests file LOC soft freeze'
printf '%s\n' '------------------------------'

guard_require_directory "$tests_dir"

test_source_files="$(
  find "$tests_dir" -name '*.swift' -type f -print | sort
)"
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  loc="$(guard_count_lines "$file")"
  rel="${file#"$repo_root"/}"
  file_fail_loc="$fail_loc"
  if [[ "$rel" == "SumiTests/SpaceSidebarTransitionStateTests.swift" ]]; then
    file_fail_loc="$space_sidebar_transition_fail_loc"
  fi
  if (( loc > file_fail_loc )); then
    printf 'error: %s is %d LOC (hard ceiling %d)\n' "$rel" "$loc" "$file_fail_loc" >&2
    failures=$((failures + 1))
  elif (( loc > warn_loc )); then
    printf 'warning: %s is %d LOC (soft warn > %d; hard fail > %d)\n' \
      "$rel" "$loc" "$warn_loc" "$file_fail_loc"
    warnings=$((warnings + 1))
  fi
done <<< "$test_source_files"

printf 'checked SumiTests/*.swift (warn > %d, fail > %d; %d warnings)\n' \
  "$warn_loc" "$fail_loc" "$warnings"

if (( failures > 0 )); then
  exit 1
fi

echo "SumiTests file LOC soft freeze passed"
