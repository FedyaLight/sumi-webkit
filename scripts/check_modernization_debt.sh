#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v rg >/dev/null 2>&1; then
  printf 'error: ripgrep (rg) is required for modernization debt guardrail\n' >&2
  exit 1
fi

production_roots=(
  "App"
  "FloatingBar"
  "SidebarChrome"
  "Settings"
  "Sumi"
  "UI"
)

test_roots=(
  "SumiTests"
  "SumiUITests"
)

failures=0

count_matches() {
  local pattern="$1"
  shift

  local total=0
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    total=$((total + ${line##*:}))
  done < <(rg --count-matches "$pattern" -g "*.swift" "$@" || true)

  printf '%s\n' "$total"
}

check_max() {
  local label="$1"
  local actual="$2"
  local max="$3"

  printf '%-46s %4d / %4d\n' "$label" "$actual" "$max"
  if (( actual > max )); then
    printf 'error: %s increased above modernization baseline (%d > %d)\n' "$label" "$actual" "$max" >&2
    failures=$((failures + 1))
  fi
}

production_shared_definitions="$(
  count_matches 'static\s+(let|var)\s+shared\b|static\s+var\s+shared\b' "${production_roots[@]}"
)"
production_shared_call_sites="$(
  count_matches '\.shared\b' "${production_roots[@]}"
)"
production_try_optional="$(
  count_matches '\btry\?' "${production_roots[@]}"
)"
test_try_optional="$(
  count_matches '\btry\?' "${test_roots[@]}"
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

while IFS= read -r -d '' file; do
  line_count="$(wc -l < "$file" | tr -d ' ')"
  if (( line_count > 3000 )); then
    printf 'error: new test monolith above 3000 lines: %s (%d)\n' "$file" "$line_count" >&2
    failures=$((failures + 1))
  fi
done < <(find "${test_roots[@]}" -name "*.swift" -type f -print0)

if (( failures > 0 )); then
  exit 1
fi

printf '\nmodernization debt guardrail passed\n'
