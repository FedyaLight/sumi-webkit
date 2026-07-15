#!/usr/bin/env bash
# Domain isolation boundary.
#
# Pure domain files that remain in the app target must stay Foundation-only
# (no SwiftUI / AppKit / WebKit) and must not type-edge into known runtime
# types (Tab, Profile, ExtensionUtils, ShortcutPin, BrowserWindowState).
# The SumiDomain SPM package is the compile-time home for peeled clusters;
# this script also guards that package against observation, scheduling, logging,
# and UI/runtime framework imports.
#
# SumiDomain and SumiWebRuntime are sibling packages consumed by the app.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

DOMAIN_FILES=(
  # App-target allowlist (Foundation-only). FailClosedMapper stays with
  # SumiPermissionCoordinatorDecision (system snapshot / prompt-suppression).
  "Sumi/Permissions/SumiPermissionFailClosedMapper.swift"
  # KeyboardShortcut stays app-target (name collides with SwiftUI.KeyboardShortcut
  # when re-exported from SumiDomain).
  "Sumi/Models/KeyboardShortcut/KeyboardShortcut.swift"
  "Sumi/Models/KeyboardShortcut/DefaultKeyboardShortcuts.swift"
  "Sumi/Models/Tab/TabDependencyStateOwner.swift"
)

forbidden_import_pattern='^import (SwiftUI|AppKit|WebKit)\b'
# Word-boundary type edges into app/runtime types. Avoids substrings like
# TabLoadingState / TabDependencyStateOwner / SumiProfileIcon.
# KeyCombination / ShortcutPinRole live in SumiDomain (V6); do not treat as runtime edges.
runtime_type_pattern='\b(Tab|Profile|ExtensionUtils|ShortcutPin|BrowserWindowState)\b'

# Strip // line comments and /* */ block comments so comment prose (e.g.
# "Profile icons…") does not trip the type-edge check.
strip_swift_comments() {
  local file="$1"
  # Remove block comments first (non-greedy across lines via perl), then // tails.
  perl -0777 -pe 's{/\*.*?\*/}{}gs; s{//[^\n]*}{}g' "$file"
}

printf '%s\n' 'Domain isolation boundary guardrail'
printf '%s\n' '----------------------------------'

for file in "${DOMAIN_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    guard_record_failure "domain file missing: $file"
    continue
  fi

  file_ok=1
  import_hits="$(guard_capture_matches "$forbidden_import_pattern" "$file")"
  if [[ -n "$import_hits" ]]; then
    guard_record_failure "domain file imports UI/runtime framework ($file): $import_hits"
    file_ok=0
  fi

  type_hits="$(
    strip_swift_comments "$file" \
      | guard_capture_matches "$runtime_type_pattern" -
  )"
  if [[ -n "$type_hits" ]]; then
    guard_record_failure \
      "domain file references runtime type (Tab/Profile/ExtensionUtils/ShortcutPin/BrowserWindowState) ($file): $type_hits"
    file_ok=0
  fi

  if (( file_ok != 0 )); then
    printf 'ok  %s\n' "$file"
  fi
done

# SumiDomain contains deterministic values, policies, and reducers. Observation,
# app-actor isolation, scheduling, and logging belong to app/runtime targets.
sumi_domain_root="Packages/SumiDomain/Sources"
if ! guard_require_directory "$sumi_domain_root"; then
  guard_record_failure "SumiDomain package sources missing: $sumi_domain_root"
else
  package_import_hits="$(
    guard_capture_matches \
      "$forbidden_import_pattern" \
      -g '*.swift' "$sumi_domain_root"
  )"
  if [[ -n "$package_import_hits" ]]; then
    guard_record_failure "SumiDomain package imports UI/runtime framework: $package_import_hits"
  else
    printf 'ok  Packages/SumiDomain/Sources (no SwiftUI/AppKit/WebKit imports)\n'
  fi

  domain_runtime_pattern='^import (Combine|Observation|OSLog|Dispatch)\b|@(Observable|ObservationIgnored|Published|MainActor)\b|\b(ObservableObject|ObservationRegistrar|withObservationTracking|Task|DispatchQueue|Logger|OSLog|os_log)\b'
  domain_source_files="$(
    find "$sumi_domain_root" -type f -name '*.swift' -print
  )"
  domain_runtime_hits=''
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    hits="$(
      strip_swift_comments "$file" \
        | guard_capture_matches "$domain_runtime_pattern" -
    )"
    if [[ -n "$hits" ]]; then
      domain_runtime_hits+="$file"$'\n'"$hits"$'\n'
    fi
  done <<< "$domain_source_files"
  if [[ -n "$domain_runtime_hits" ]]; then
    guard_record_failure \
      "SumiDomain package contains app observation/scheduling/logging runtime: $domain_runtime_hits"
  else
    printf 'ok  Packages/SumiDomain/Sources (no app observation/scheduling/logging runtime)\n'
  fi
fi

# Models must not grow new SwiftUI Views (ProfileIconView already moved out).
model_view_hits="$(
  guard_capture_matches \
    'struct\s+\w+:\s*View\b' \
    -g '*.swift' Sumi/Models
)"
if [[ -n "$model_view_hits" ]]; then
  guard_record_failure "SwiftUI View types live under Sumi/Models: $model_view_hits"
fi

guard_finish \
  "domain isolation boundary audit (${#DOMAIN_FILES[@]} app-target domain files + SumiDomain package)"
