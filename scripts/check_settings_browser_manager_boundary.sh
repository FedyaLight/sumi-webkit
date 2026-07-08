#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

settings_root="Sumi/Components/Settings"

matches="$(
  grep -rEn --include='*.swift' \
    -e '\bBrowserManager\b' \
    -e '\bbrowserManager\b' \
    "$settings_root" || [[ $? -eq 1 ]]
)"

if [[ -n "$matches" ]]; then
  printf 'disallowed BrowserManager coupling under %s:\n%s\n' "$settings_root" "$matches" >&2
  echo "Settings UI must consume SettingsBrowserContext from WebsiteViewContextFactory instead." >&2
  exit 1
fi

echo "settings BrowserManager boundary audit passed"
