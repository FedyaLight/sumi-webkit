#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

runtime_paths=(App Sumi Settings SidebarChrome FloatingBar UI)
allowed_files=(
  "Sumi/Managers/BrowserManager/BrowserManager.swift"
  "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
)
status=0

is_allowed_file() {
  local candidate="$1"
  local allowed
  for allowed in "${allowed_files[@]}"; do
    if [[ "$candidate" == "$allowed" ]]; then
      return 0
    fi
  done
  return 1
}

matches="$(
  grep -rEn --include='*.swift' \
    -e 'attach(BrowserRuntimeContext|InitialDocumentRuntimeContext|ShutdownRuntimeContext|VisiblePreparationRuntimeContext)' \
    -e 'detach(BrowserRuntimeContext|InitialDocumentRuntimeContext|ShutdownRuntimeContext|VisiblePreparationRuntimeContext)' \
    "${runtime_paths[@]}" || [[ $? -eq 1 ]]
)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  relative_path="${match%%:*}"
  if ! is_allowed_file "$relative_path"; then
    printf 'disallowed WebView runtime context attachment outside BrowserManager shell binding: %s\n' "$match" >&2
    status=1
  fi
done <<< "$matches"

if [[ "$status" -ne 0 ]]; then
  echo "WebView runtime context boundary audit failed" >&2
  exit "$status"
fi

echo "WebView runtime context boundary audit passed"
