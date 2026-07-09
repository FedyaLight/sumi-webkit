#!/usr/bin/env bash
# Chrome SPM package boundary (R6 scaffolds).
#
# Ensures SumiChrome* packages stay free of app-hub types (BrowserManager /
# TabManager) and that each package builds standalone via `swift build`.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

chrome_packages=(
  "Packages/SumiChromeTokens"
  "Packages/SumiChromeContracts"
  "Packages/SumiSidebarChrome"
  "Packages/SumiFloatingBarChrome"
)

forbidden_import_pattern='^import (BrowserManager|TabManager)\b'
forbidden_type_pattern='\b(BrowserManager|TabManager)\b'
failures=0

strip_swift_comments() {
  local file="$1"
  perl -0777 -pe 's{/\*.*?\*/}{}gs; s{//[^\n]*}{}g' "$file"
}

printf '%s\n' 'Chrome package boundary guardrail'
printf '%s\n' '---------------------------------'

for pkg in "${chrome_packages[@]}"; do
  sources="${pkg}/Sources"
  if [[ ! -d "$sources" ]]; then
    printf 'error: chrome package sources missing: %s\n' "$sources" >&2
    failures=$((failures + 1))
    continue
  fi

  pkg_ok=1
  while IFS= read -r -d '' file; do
    if rg -n "$forbidden_import_pattern" "$file" >/dev/null 2>&1; then
      printf 'error: chrome package imports BrowserManager/TabManager: %s\n' "$file" >&2
      rg -n "$forbidden_import_pattern" "$file" >&2 || true
      pkg_ok=0
    fi

    type_hits="$(
      strip_swift_comments "$file" | rg -n "$forbidden_type_pattern" || true
    )"
    if [[ -n "$type_hits" ]]; then
      printf 'error: chrome package references BrowserManager/TabManager: %s\n' "$file" >&2
      printf '%s\n' "$type_hits" >&2
      pkg_ok=0
    fi
  done < <(find "$sources" -name '*.swift' -print0)

  if (( pkg_ok == 0 )); then
    failures=$((failures + 1))
  else
    printf 'ok  %s (no BrowserManager/TabManager)\n' "$pkg"
  fi
done

for pkg in "${chrome_packages[@]}"; do
  printf '==> swift build --package-path %s\n' "$pkg"
  if ! swift build --package-path "$pkg"; then
    printf 'error: swift build failed for %s\n' "$pkg" >&2
    failures=$((failures + 1))
  fi
done

if (( failures > 0 )); then
  exit 1
fi

echo "chrome package boundaries passed"
