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

fail_open_port_hits="$(
  rg -n 'weak\s+var\s+browserManager|weak\s+let\s+browserManager|guard\s+let\s+browserManager\s+else\s*\{\s*return' \
    Sumi/BrowserRuntime/Ports -g 'Tab*Port.swift' 2>/dev/null || true
)"
if [[ -n "$fail_open_port_hits" ]]; then
  printf 'error: Tab runtime ports must not fail open after their browser feature graph is released:\n%s\n' \
    "$fail_open_port_hits" >&2
  exit 1
fi

profile_root_lookup_hits="$(
  rg -n 'BrowserManager(RuntimeReference)?|runtime\.require\(\)' \
    Sumi/BrowserRuntime/Ports/TabProfileQueryPort.swift 2>/dev/null || true
)"
if [[ -n "$profile_root_lookup_hits" ]]; then
  printf 'error: the profile query port must retain exact profile/settings authorities, not re-enter BrowserManager:\n%s\n' \
    "$profile_root_lookup_hits" >&2
  exit 1
fi

session_side_effect_root_lookup_hits="$(
  rg -n 'BrowserManager(RuntimeReference)?|runtime\.require\(\)' \
    Sumi/BrowserRuntime/Ports/TabSessionSideEffectsPort.swift 2>/dev/null || true
)"
if [[ -n "$session_side_effect_root_lookup_hits" ]]; then
  printf 'error: the session side-effects port must retain exact services, not re-enter BrowserManager:\n%s\n' \
    "$session_side_effect_root_lookup_hits" >&2
  exit 1
fi

inactive_registry_hits="$(
  rg -n 'RuntimePortRegistry\.inactive|TabManagerWebViewLifecycleService\.inactive|static\s+(let|var)\s+inactive\s*(:\s*RuntimePortRegistry|=\s*RuntimePortRegistry)' \
    Sumi -g '*.swift' 2>/dev/null || true
)"
if [[ -n "$inactive_registry_hits" ]]; then
  printf 'error: no-op runtime registries belong in test support, not the production graph:\n%s\n' \
    "$inactive_registry_hits" >&2
  exit 1
fi

echo "no legacy/fail-open TabManager runtime context in source"
