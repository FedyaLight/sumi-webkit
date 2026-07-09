#!/usr/bin/env bash
# SumiWebRuntime isolation boundary.
#
# The SumiWebRuntime SPM package may use Foundation, WebKit, AppKit, Combine,
# and OSLog. SwiftUI is forbidden. Sources must not type-edge into app-target
# BrowserManager / BrowserWindowState / concrete Tab.
#
# Intended dependency direction: SumiDomain → SumiWebRuntime → SumiAppUI.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

sumi_webruntime_root="Packages/SumiWebRuntime/Sources"
failures=0

printf '%s\n' 'SumiWebRuntime isolation boundary guardrail'
printf '%s\n' '------------------------------------------'

if [[ ! -d "$sumi_webruntime_root" ]]; then
  printf 'error: SumiWebRuntime package sources missing: %s\n' "$sumi_webruntime_root" >&2
  exit 1
fi

# Strip // line comments and /* */ block comments so comment prose does not
# trip the type-edge check.
strip_swift_comments() {
  local file="$1"
  perl -0777 -pe 's{/\*.*?\*/}{}gs; s{//[^\n]*}{}g' "$file"
}

forbidden_import_pattern='^import SwiftUI\b'
# Word-boundary type edges into app/runtime composition types.
# Avoids substrings like TabWebViewSession / TabLoadingState / VisibleTabPreparationPlan.
runtime_type_pattern='\b(BrowserManager|BrowserWindowState|Tab)\b'

if rg -n "$forbidden_import_pattern" -g '*.swift' "$sumi_webruntime_root" >/dev/null 2>&1; then
  printf 'error: SumiWebRuntime package imports SwiftUI:\n' >&2
  rg -n "$forbidden_import_pattern" -g '*.swift' "$sumi_webruntime_root" >&2 || true
  failures=$((failures + 1))
else
  printf 'ok  Packages/SumiWebRuntime/Sources (no SwiftUI imports)\n'
fi

type_failures=0
while IFS= read -r -d '' file; do
  type_hits="$(
    strip_swift_comments "$file" | rg -n "$runtime_type_pattern" || true
  )"
  if [[ -n "$type_hits" ]]; then
    printf 'error: SumiWebRuntime references app type (BrowserManager/BrowserWindowState/Tab): %s\n' "$file" >&2
    printf '%s\n' "$type_hits" >&2
    type_failures=$((type_failures + 1))
  fi
done < <(find "$sumi_webruntime_root" -name '*.swift' -print0)

if (( type_failures > 0 )); then
  failures=$((failures + type_failures))
else
  printf 'ok  Packages/SumiWebRuntime/Sources (no BrowserManager/BrowserWindowState/Tab type edges)\n'
fi

if (( failures > 0 )); then
  exit 1
fi

printf '\nSumiWebRuntime isolation boundary audit passed\n'
