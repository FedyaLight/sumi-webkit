#!/usr/bin/env bash
# Domain isolation boundary — Phase 7 enforcement.
#
# Pure domain files that remain in the app target must stay Foundation-only
# (no SwiftUI / AppKit / WebKit) and must not type-edge into known runtime
# types (Tab, Profile, ExtensionUtils, ShortcutPin, BrowserWindowState).
# The closed SumiDomain SPM package is the compile-time home for peeled
# clusters; this script also guards that package against UI/runtime framework
# imports.
#
# Eventual SPM shape: SumiDomain → SumiWebRuntime → SumiAppUI.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

DOMAIN_FILES=(
  # W5/X5 peeled into Packages/SumiDomain:
  #   SumiProfileIcon, SidebarInputRecoveryOwner (+ reason), SumiURLNormalization
  #   (+ SumiStartupPageURL / SumiNewTabPageURL), BrowserWindowSelectionHistoryItem,
  #   WindowSelectionHistoryOwner, SumiPermissionState / Persistence / DecisionSource,
  #   SumiPermissionCoordinatorOutcome, TabPlacementStateOwner
  # SumiPermissionCoordinatorDecision stays app-target (system snapshot /
  # prompt-suppression edges); FailClosedMapper stays with it (Foundation-only).
  "Sumi/Permissions/SumiPermissionFailClosedMapper.swift"
  # KeyboardShortcut stays app-target (name collides with SwiftUI.KeyboardShortcut when
  # re-exported from SumiDomain); Foundation-only after KeyCombination peel.
  "Sumi/Models/KeyboardShortcut/KeyboardShortcut.swift"
  "Sumi/Models/KeyboardShortcut/DefaultKeyboardShortcuts.swift"
  # excluded: references ShortcutPin — Sumi/Models/History/HistoryTypes.swift
  "Sumi/Models/Tab/TabDependencyStateOwner.swift"
  # excluded: references Tab/Profile — Sumi/Models/Tab/TabProfileResolutionOwner.swift
  # excluded: references Tab — Sumi/Models/Tab/Tab+Favicon.swift
  # excluded: references Tab/Profile — Sumi/Models/Tab/Navigation/SumiAutoplayPolicyNavigationResponder.swift
  # excluded: references Tab — Sumi/Models/Tab/Navigation/SumiInstallNavigationResponder.swift
  # excluded: references Tab — Sumi/Models/Tab/Navigation/SumiInternalSurfaceNavigationResponder.swift
  #   (unused Tab init arg dropped; still app-target navigation responder)
  # AppKit bridge retained in app (NSEvent init): Sumi/Models/KeyboardShortcut/KeyCombination+NSEvent.swift
)

forbidden_import_pattern='^import (SwiftUI|AppKit|WebKit)\b'
# Word-boundary type edges into app/runtime types. Avoids substrings like
# TabLoadingState / TabDependencyStateOwner / SumiProfileIcon.
# KeyCombination / ShortcutPinRole live in SumiDomain (V6); do not treat as runtime edges.
runtime_type_pattern='\b(Tab|Profile|ExtensionUtils|ShortcutPin|BrowserWindowState)\b'
failures=0

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
    printf 'error: domain file missing: %s\n' "$file" >&2
    failures=$((failures + 1))
    continue
  fi

  file_ok=1
  if rg -n "$forbidden_import_pattern" "$file" >/dev/null 2>&1; then
    printf 'error: domain file imports UI/runtime framework: %s\n' "$file" >&2
    rg -n "$forbidden_import_pattern" "$file" >&2 || true
    file_ok=0
  fi

  type_hits="$(
    strip_swift_comments "$file" | rg -n "$runtime_type_pattern" || true
  )"
  if [[ -n "$type_hits" ]]; then
    printf 'error: domain file references runtime type (Tab/Profile/ExtensionUtils/ShortcutPin/BrowserWindowState): %s\n' "$file" >&2
    printf '%s\n' "$type_hits" >&2
    file_ok=0
  fi

  if (( file_ok == 0 )); then
    failures=$((failures + 1))
  else
    printf 'ok  %s\n' "$file"
  fi
done

# SumiDomain SPM package must stay Foundation/Combine/Observation/OSLog only.
sumi_domain_root="Packages/SumiDomain/Sources"
if [[ ! -d "$sumi_domain_root" ]]; then
  printf 'error: SumiDomain package sources missing: %s\n' "$sumi_domain_root" >&2
  failures=$((failures + 1))
else
  if rg -n "$forbidden_import_pattern" -g '*.swift' "$sumi_domain_root" >/dev/null 2>&1; then
    printf 'error: SumiDomain package imports UI/runtime framework:\n' >&2
    rg -n "$forbidden_import_pattern" -g '*.swift' "$sumi_domain_root" >&2 || true
    failures=$((failures + 1))
  else
    printf 'ok  Packages/SumiDomain/Sources (no SwiftUI/AppKit/WebKit imports)\n'
  fi
fi

# Models must not grow new SwiftUI Views (ProfileIconView already moved out).
if rg -n 'struct\s+\w+:\s*View\b' -g '*.swift' Sumi/Models >/dev/null 2>&1; then
  printf 'error: SwiftUI View types must not live under Sumi/Models:\n' >&2
  rg -n 'struct\s+\w+:\s*View\b' -g '*.swift' Sumi/Models >&2 || true
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  exit 1
fi

printf '\ndomain isolation boundary audit passed (%d app-target domain files + SumiDomain package)\n' "${#DOMAIN_FILES[@]}"
