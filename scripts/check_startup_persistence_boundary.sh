#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

runtime_paths=(App Sumi Settings SidebarChrome FloatingBar UI)
allowed_file="Sumi/Services/SumiStartupPersistence.swift"
status=0

check_pattern() {
  local label="$1"
  local pattern="$2"
  local matches

  matches="$(grep -rEn --include='*.swift' -e "$pattern" "${runtime_paths[@]}" || [[ $? -eq 1 ]])"
  [[ -z "$matches" ]] && return

  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    local relative_path="${match%%:*}"
    if [[ "$relative_path" != "$allowed_file" ]]; then
      printf 'disallowed %s outside %s: %s\n' "$label" "$allowed_file" "$match" >&2
      status=1
    fi
  done <<< "$matches"
}

check_pattern "SwiftData model container construction" 'ModelContainer\s*\('
check_pattern "SwiftData model configuration construction" 'ModelConfiguration\s*\('
check_pattern "SwiftData schema construction" 'Schema\s*\('

if [[ "$status" -ne 0 ]]; then
  echo "startup persistence boundary audit failed" >&2
  exit "$status"
fi

echo "startup persistence boundary audit passed"
