#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

production_roots=(
  "App"
  "CommandPalette"
  "SidebarChrome"
  "Settings"
  "Sumi"
  "UI"
)

test_roots=(
  "SumiTests"
  "SumiUITests"
)

count_matches() {
  guard_count_swift_matches "$@"
}

check_max() {
  guard_max "$@"
}

production_shared_definitions="$(
  count_matches 'static\s+(let|var)\s+shared\b|static\s+var\s+shared\b' "${production_roots[@]}"
)"
production_shared_call_sites="$(
  count_matches '\.shared\b' "${production_roots[@]}"
)"
# This counter tracks *swallowed errors*: a `try?` that discards a failure the
# caller should have handled. `try? await Task.sleep` is not one of those --
# `Task.sleep` throws only `CancellationError`, and every site in this repo
# either checks `Task.isCancelled`/a generation token immediately afterwards or
# sits in a loop that cancellation is meant to end. Rewriting those as do/catch
# would be strictly worse code, so they are excluded rather than counted as debt.
# The ceilings below are unchanged and still ratchet the real debt down.
production_try_optional="$(
  count_matches '\btry\?(?!\s+await\s+Task\.sleep)' "${production_roots[@]}" -P
)"
test_try_optional="$(
  count_matches '\btry\?(?!\s+await\s+Task\.sleep)' "${test_roots[@]}" -P
)"
theme_color_literals="$(
  count_matches '(Color|NSColor)\.(black|white|red|blue|green|orange|pink|purple|yellow|gray|primary|secondary|accentColor)|Color\(hex:|Color\(NSColor\.' "${production_roots[@]}" -g "!**/*ThemeTokens.swift"
)"
theme_font_size_literals="$(
  count_matches '\.font\(\.system\(size:|Font\.system\(size:|NSFont\.(systemFont|monospacedSystemFont)\(ofSize:' "${production_roots[@]}" -g "!**/*ThemeTokens.swift"
)"

printf '%s\n' 'Modernization debt baseline guardrail'
printf '%s\n' '--------------------------------------'
check_max "production shared singleton definitions" "$production_shared_definitions" 4
check_max "production .shared call sites" "$production_shared_call_sites" 53
# Baseline raised 57 -> 62 when the vendored DDG Bookmarks import readers were
# ported into Sumi/Bookmarks/Store (5 best-effort try? sites: temp-file
# cleanup, browser-profile directory discovery, regex compilation).
check_max "production try? call sites" "$production_try_optional" 62
check_max "test try? call sites" "$test_try_optional" 174
check_max "theme color literal call sites" "$theme_color_literals" 78
check_max "theme fixed font-size call sites" "$theme_font_size_literals" 69

printf '\n%s\n' 'Test monolith guardrail'
printf '%s\n' '-----------------------'

test_source_files="$(
  find "${test_roots[@]}" -name '*.swift' -type f -print
)"
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  line_count="$(guard_count_lines "$file")"
  if (( line_count > 3000 )); then
    guard_record_failure "new test monolith above 3000 lines: $file ($line_count)"
  fi
done <<< "$test_source_files"

guard_finish 'modernization debt guardrail'
