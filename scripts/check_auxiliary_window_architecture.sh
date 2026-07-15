#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

status=0

record_scan_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

required_files=(
  Sumi/AuxiliaryWindows/AuxiliaryPopupOpeningService.swift
  Sumi/AuxiliaryWindows/AuxiliaryWindowCapabilities.swift
  Sumi/AuxiliaryWindows/AuxiliaryWindowNestingPolicy.swift
  Sumi/AuxiliaryWindows/AuxiliaryWindowPresentationService.swift
  Sumi/AuxiliaryWindows/AuxiliaryWindowSessionRegistry.swift
  Sumi/AuxiliaryWindows/AuxiliaryWindowTabIdentityPolicy.swift
  Sumi/AuxiliaryWindows/AuxiliaryWindowTeardownService.swift
  Sumi/AuxiliaryWindows/ExtensionAuxiliaryWindowOpeningService.swift
  Sumi/AuxiliaryWindows/BrowserAuxiliaryWindowComposition.swift
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: auxiliary-window boundary missing: %s\n' "$file" >&2
    status=1
  fi
done

removed_files=(
  Sumi/Managers/AuxiliaryWindowManager/AuxiliaryWindowManager.swift
  Sumi/Managers/BrowserManager/BrowserAuxiliaryWindowRuntimeService.swift
  Sumi/Managers/BrowserManager/BrowserAuxiliaryWindowServices.swift
)

for file in "${removed_files[@]}"; do
  if [[ -e "$file" ]]; then
    printf 'error: retired auxiliary-window god surface returned: %s\n' "$file" >&2
    status=1
  fi
done

if [[ -d Sumi/Managers/AuxiliaryWindowManager ]]; then
  printf 'error: retired AuxiliaryWindowManager feature directory returned\n' >&2
  status=1
fi

legacy_hits="$(
  guard_capture_matches \
    '\b(AuxiliaryWindowManager|AuxiliaryWindowRuntime|BrowserAuxiliaryWindowRuntimeService|BrowserAuxiliaryWindowServices|auxiliaryWindowManager)\b' \
    App Sumi SumiTests -g '*.swift'
)"
record_scan_matches "retired auxiliary-window facade/runtime symbol returned" "$legacy_hits"

owner_declarations="$(
  guard_capture_matches \
    '^(private )?(final )?(class|struct|enum|protocol) [A-Za-z0-9_]*Auxiliary[A-Za-z0-9_]*Owner\b' \
    Sumi/AuxiliaryWindows \
    Sumi/AuxiliaryWindows/BrowserAuxiliaryWindowComposition.swift \
    -g '*.swift'
)"
record_scan_matches "auxiliary-window responsibility hidden behind an Owner type" "$owner_declarations"

browser_manager_hits="$(
  guard_capture_matches '\bBrowserManager\b|\bbrowserManager\b' \
    Sumi/AuxiliaryWindows \
    Sumi/AuxiliaryWindows/BrowserAuxiliaryWindowComposition.swift \
    -g '*.swift'
)"
record_scan_matches "auxiliary-window boundary reaches back into BrowserManager" "$browser_manager_hits"

extension_manager_hits="$(
  guard_capture_files '\bExtensionManager\b' Sumi/AuxiliaryWindows -g '*.swift' \
    | while IFS= read -r file; do
        if [[ "$file" != Sumi/AuxiliaryWindows/BrowserAuxiliaryWindowComposition.swift \
              && "$file" != Sumi/AuxiliaryWindows/ExtensionAuxiliaryWindowOpeningService.swift ]]; then
          printf '%s\n' "$file"
        fi
      done
)"
record_scan_matches "long-lived auxiliary runtime depends on the ExtensionManager god surface" "$extension_manager_hits"

registry_file='Sumi/AuxiliaryWindows/AuxiliaryWindowSessionRegistry.swift'
registry_hits="$(
  guard_capture_files \
    '\b(sessionsByID|sessionIDByWebView|sessionIDByWindow|sessionIDByTabID|focusOrderByExtensionID)\b' \
    Sumi -g '*.swift' \
    | while IFS= read -r file; do
        [[ "$file" == "$registry_file" ]] || printf '%s\n' "$file"
      done
)"
record_scan_matches "auxiliary session indexes escaped the canonical registry" "$registry_hits"

if [[ -f Sumi/AuxiliaryWindows/BrowserAuxiliaryWindowComposition.swift ]]; then
  composition_forwarders="$(
    awk '
      /final class BrowserAuxiliaryWindowComposition/ { in_composition = 1 }
      in_composition && /^[[:space:]]+func[[:space:]]/ { print NR ":" $0 }
    ' Sumi/AuxiliaryWindows/BrowserAuxiliaryWindowComposition.swift
  )"
  record_scan_matches "auxiliary composition root grew forwarding methods" "$composition_forwarders"

  composition_lines="$(
    wc -l < Sumi/AuxiliaryWindows/BrowserAuxiliaryWindowComposition.swift \
      | tr -d ' '
  )"
  if (( composition_lines > 320 )); then
    printf 'error: auxiliary composition grew beyond assembly duties (%s > 320 LOC)\n' \
      "$composition_lines" >&2
    status=1
  fi
fi

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo "auxiliary-window architecture boundary passed"
