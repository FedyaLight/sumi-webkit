#!/usr/bin/env bash
# Fail if legacy TabManagerRuntimeContext / makeLegacyRuntimeContext resurfaces (W1).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

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

for root in "${search_roots[@]}"; do
  guard_require_directory "$root"
done

matches="$(
  guard_capture_matches 'TabManagerRuntimeContext|makeLegacyRuntimeContext' \
    -g '*.swift' "${search_roots[@]}"
)"

if [[ -n "$matches" ]]; then
  printf 'error: legacy TabManagerRuntimeContext / makeLegacyRuntimeContext must not appear in source:\n%s\n' "$matches" >&2
  exit 1
fi

fail_open_port_hits="$(
  guard_capture_matches 'weak\s+var\s+browserManager|weak\s+let\s+browserManager|guard\s+let\s+browserManager\s+else\s*\{\s*return' \
    Sumi/BrowserRuntime/Ports -g 'Tab*Port.swift'
)"
if [[ -n "$fail_open_port_hits" ]]; then
  printf 'error: Tab runtime ports must not fail open after their browser feature graph is released:\n%s\n' \
    "$fail_open_port_hits" >&2
  exit 1
fi

profile_root_lookup_hits="$(
  guard_capture_matches 'BrowserManager(RuntimeReference)?|runtime\.require\(\)' \
    Sumi/BrowserRuntime/Ports/TabProfileQueryPort.swift
)"
if [[ -n "$profile_root_lookup_hits" ]]; then
  printf 'error: the profile query port must retain exact profile/settings authorities, not re-enter BrowserManager:\n%s\n' \
    "$profile_root_lookup_hits" >&2
  exit 1
fi

session_side_effect_root_lookup_hits="$(
  guard_capture_matches 'BrowserManager(RuntimeReference)?|runtime\.require\(\)' \
    Sumi/BrowserRuntime/Ports/TabSessionSideEffectsPort.swift
)"
if [[ -n "$session_side_effect_root_lookup_hits" ]]; then
  printf 'error: the session side-effects port must retain exact services, not re-enter BrowserManager:\n%s\n' \
    "$session_side_effect_root_lookup_hits" >&2
  exit 1
fi

retired_runtime_reference_hits="$(
  guard_capture_matches 'BrowserManagerRuntimeReference|runtime\.require\(\)' \
    Sumi -g '*.swift'
)"
if [[ -n "$retired_runtime_reference_hits" ]]; then
  printf 'error: Tab runtime feature ports must retain exact services, not a late BrowserManager reference:\n%s\n' \
    "$retired_runtime_reference_hits" >&2
  exit 1
fi

for exact_port in \
  Sumi/BrowserRuntime/Ports/TabWindowQueryPort.swift \
  Sumi/BrowserRuntime/Ports/TabExtensionLifecyclePort.swift \
  Sumi/Managers/BrowserManager/BrowserTabManagerWebViewLifecycleFactory.swift; do
  guard_require_file "$exact_port"
  root_lookup_hits="$(
    guard_capture_matches 'BrowserManager|OptionalModuleHost' "$exact_port"
  )"
  if [[ -n "$root_lookup_hits" ]]; then
    printf 'error: %s must retain its exact feature authorities, not the browser/module root:\n%s\n' \
      "$exact_port" "$root_lookup_hits" >&2
    exit 1
  fi
done

if [[ -e Sumi/BrowserRuntime/Ports/BrowserManagerRuntimeReference.swift ]]; then
  printf 'error: retired BrowserManager runtime reference was reintroduced\n' >&2
  exit 1
fi

inactive_registry_hits="$(
  guard_capture_matches 'RuntimePortRegistry\.inactive|TabManagerWebViewLifecycleService\.inactive|static\s+(let|var)\s+inactive\s*(:\s*RuntimePortRegistry|=\s*RuntimePortRegistry)' \
    Sumi -g '*.swift'
)"
if [[ -n "$inactive_registry_hits" ]]; then
  printf 'error: no-op runtime registries belong in test support, not the production graph:\n%s\n' \
    "$inactive_registry_hits" >&2
  exit 1
fi

echo "no legacy/fail-open TabManager runtime context in source"
