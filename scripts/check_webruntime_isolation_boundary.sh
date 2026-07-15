#!/usr/bin/env bash
# SumiWebRuntime isolation boundary.
#
# The SumiWebRuntime SPM package may use Foundation, WebKit, AppKit, Combine,
# and OSLog. SwiftUI is forbidden. Sources must not type-edge into app-target
# BrowserManager / BrowserWindowState / concrete Tab.
#
# SumiDomain and SumiWebRuntime are sibling packages consumed by the app.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

sumi_webruntime_root="Packages/SumiWebRuntime/Sources"

printf '%s\n' 'SumiWebRuntime isolation boundary guardrail'
printf '%s\n' '------------------------------------------'

guard_require_directory "$sumi_webruntime_root"

# Strip string literals and comments so diagnostics/documentation do not trip
# the type-edge check. Triple-quoted literals must be removed before ordinary
# strings, and strings before comments because URLs can contain `//`.
strip_swift_noncode() {
  local file="$1"
  perl -0777 -pe '
    s{""".*?"""}{""}gs;
    s{"(?:\\.|[^"\\])*"}{""}g;
    s{/\*.*?\*/}{}gs;
    s{//[^\n]*}{}g
  ' "$file"
}

forbidden_import_pattern='^import SwiftUI\b'
# Word-boundary type edges into app/runtime composition types.
# Avoids substrings like TabWebViewSession / TabLoadingState / VisibleTabPreparationPlan.
runtime_type_pattern='\b(BrowserManager|BrowserWindowState|Tab)\b'

forbidden_imports="$(
  guard_capture_matches \
    "$forbidden_import_pattern" \
    -g '*.swift' "$sumi_webruntime_root"
)"
if [[ -n "$forbidden_imports" ]]; then
  guard_record_failure "SumiWebRuntime package imports SwiftUI: $forbidden_imports"
else
  printf 'ok  Packages/SumiWebRuntime/Sources (no SwiftUI imports)\n'
fi

runtime_source_files="$(
  find "$sumi_webruntime_root" -name '*.swift' -type f -print
)"
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  type_hits="$(
    strip_swift_noncode "$file" \
      | guard_capture_matches "$runtime_type_pattern" -
  )"
  if [[ -n "$type_hits" ]]; then
    guard_record_failure \
      "SumiWebRuntime references app type (BrowserManager/BrowserWindowState/Tab) in $file: $type_hits"
  fi
done <<< "$runtime_source_files"

if (( guard_failures == 0 )); then
  printf 'ok  Packages/SumiWebRuntime/Sources (no BrowserManager/BrowserWindowState/Tab type edges)\n'
fi

guard_finish 'SumiWebRuntime isolation boundary audit'
