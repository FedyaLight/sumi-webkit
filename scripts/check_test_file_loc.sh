#!/usr/bin/env bash
# SumiTests file LOC soft freeze (R7 harness).
#
# Existing mega-files (e.g. SumiFaviconV2Tests ~2126 LOC) are grandfathered
# under a hard ceiling of 2260. Files above 1500 print a warning so new growth
# stays visible without blocking CI until a split lands.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

tests_dir="SumiTests"
warn_loc=1500
fail_loc=2260
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
  if (( loc > fail_loc )); then
    printf 'error: %s is %d LOC (hard ceiling %d)\n' "$rel" "$loc" "$fail_loc" >&2
    failures=$((failures + 1))
  elif (( loc > warn_loc )); then
    printf 'warning: %s is %d LOC (soft warn > %d; hard fail > %d)\n' \
      "$rel" "$loc" "$warn_loc" "$fail_loc"
    warnings=$((warnings + 1))
  fi
done <<< "$test_source_files"

printf 'checked SumiTests/*.swift (warn > %d, fail > %d; %d warnings)\n' \
  "$warn_loc" "$fail_loc" "$warnings"

if (( failures > 0 )); then
  exit 1
fi

echo "SumiTests file LOC soft freeze passed"
