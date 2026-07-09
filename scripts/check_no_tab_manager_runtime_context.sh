#!/usr/bin/env bash
# Fail if legacy TabManagerRuntimeContext / makeLegacyRuntimeContext resurfaces (W1).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v rg >/dev/null 2>&1; then
  printf 'error: ripgrep (rg) is required\n' >&2
  exit 1
fi

# Source trees only (docs/plan intentionally excluded; build artifacts ignored).
search_roots=(
  Sumi
  SumiTests
  App
  FloatingBar
  SidebarChrome
  Settings
  UI
)

existing_roots=()
for root in "${search_roots[@]}"; do
  if [[ -d "$root" ]]; then
    existing_roots+=("$root")
  fi
done

if [[ ${#existing_roots[@]} -eq 0 ]]; then
  printf 'error: no source roots found to scan\n' >&2
  exit 1
fi

matches="$(
  rg -n 'TabManagerRuntimeContext|makeLegacyRuntimeContext' \
    -g '*.swift' \
    "${existing_roots[@]}" 2>/dev/null || true
)"

if [[ -n "$matches" ]]; then
  printf 'error: legacy TabManagerRuntimeContext / makeLegacyRuntimeContext must not appear in source:\n%s\n' "$matches" >&2
  exit 1
fi

echo "no TabManagerRuntimeContext / makeLegacyRuntimeContext in source"
