#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

ui_paths=(App Sumi Navigation FloatingBar Settings UI)

matches="$(
  grep -rEn --include='*.swift' \
    -e '@EnvironmentObject.*BrowserManager' \
    -e '@Environment\([^)]*BrowserManager' \
    -e '\.environmentObject\([^)]*\bbrowserManager\s*\)' \
    -e '\.environment\([^)]*\bbrowserManager\s*\)' \
    "${ui_paths[@]}" || [[ $? -eq 1 ]]
)"

if [[ -n "$matches" ]]; then
  printf 'disallowed direct BrowserManager SwiftUI environment coupling:\n%s\n' "$matches" >&2
  echo "Use feature-specific projection/context types instead." >&2
  exit 1
fi

echo "sidebar BrowserManager environment boundary audit passed"
