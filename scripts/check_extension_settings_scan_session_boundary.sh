#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

pane="Sumi/Components/Settings/SumiExtensionsSettingsPane.swift"
session="Sumi/Components/Settings/ExtensionSettingsScanSession.swift"
installed_section="Sumi/Components/Settings/ExtensionSettingsInstalledSection.swift"
candidate_sections="Sumi/Components/Settings/SafariExtensionImportCandidatesSection.swift"
commands="Sumi/Components/Settings/ExtensionSettingsSectionCommands.swift"

focused_production=(
  "$pane"
  "$session"
  "$installed_section"
  "$candidate_sections"
  "$commands"
  "Sumi/Components/Settings/ExtensionCatalogDetailsPopover.swift"
)

for file in "${focused_production[@]}"; do
  guard_require_file "$file"
done

require_scan_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  local count
  count="$(guard_count_matches "$pattern" "$file")" || return
  if (( count == 0 )); then
    echo "$message" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  local matches
  matches="$(guard_capture_matches "$pattern" "$file")" || return
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
    echo "$message" >&2
    return 1
  fi
}

require_scan_pattern 'extensionsModule\.extensionRuntimeIsAvailable\(\)' "$pane" \
  "extension settings must preserve fail-closed runtime readiness"
require_scan_pattern 'struct ExtensionSettingsRuntimeGate' "$pane" \
  "extension settings must gate enabled-content construction on readiness"
require_scan_pattern 'struct ExtensionSettingsScanAttempt' "$session" \
  "extension-settings scan attempts must remain typed"
require_scan_pattern 'private var scanTask: Task<Void, Never>\?' "$session" \
  "the scan session must own the scan task lifetime"
require_scan_pattern 'guard activeAttempt == attempt else' "$session" \
  "terminal scan publication must reject stale attempts"
for state in inert scanning completed failed cancelled; do
  require_scan_pattern "case $state" "$session" \
    "missing extension-settings terminal/session state: $state"
done

reject_pattern \
  'SafariExtensionScanner|\b(scanTask|nextGeneration|activeAttempt)\b|Task[[:space:]]*(<|\{)' \
  "$pane" \
  "SumiExtensionsSettingsPane must not regain scan, task, or generation ownership"

scan_owner_files="$(
  guard_capture_files '\b(scanTask|nextGeneration|activeAttempt)\b' \
    "${focused_production[@]}"
)"
if [[ "$scan_owner_files" != "$session" ]]; then
  printf 'extension-settings scan ownership escaped its session:\n%s\n' \
    "$scan_owner_files" >&2
  exit 1
fi

focused_boundaries=("$session" "$installed_section" "$candidate_sections" "$commands")
for file in "${focused_boundaries[@]}"; do
  reject_pattern \
    '\b(SumiExtensionsModule|ExtensionManager|BrowserManager)\b' \
    "$file" \
    "extension-settings session/sections must not retain manager backreferences: $file"
done

reject_pattern \
  '\b(Dependencies|DependencyBag|ManagerContext|ServiceLocator)\b' \
  "$session" \
  "the extension-settings scan session must receive exact capabilities"
reject_pattern \
  'Timer|Task\.sleep|RunLoop|asyncAfter|static let shared|\bpoll' \
  "$session" \
  "the extension-settings scan session must not introduce background polling or hidden defaults"

require_scan_pattern 'struct ExtensionSettingsInstalledSection: View' \
  "$installed_section" \
  "the installed catalog must remain a real semantic section"
require_scan_pattern 'struct ExtensionSettingsContentBlockersSection: View' \
  "$candidate_sections" \
  "content blockers must remain a real semantic section"
require_scan_pattern 'struct ExtensionSettingsUnsupportedSection: View' \
  "$candidate_sections" \
  "unsupported extensions must remain a real semantic section"
require_scan_pattern 'let projection: ExtensionSettingsInstalledProjection' \
  "$installed_section" \
  "the installed section must receive a narrow immutable projection"
require_scan_pattern 'let commands: ExtensionSettingsInstalledCommands' \
  "$installed_section" \
  "the installed section must receive exact commands"
require_scan_pattern 'let commands: ExtensionSettingsContentBlockerCommands' \
  "$candidate_sections" \
  "the content-blocker section must receive exact commands"

session_consumer_files="$(
  guard_capture_files '\bExtensionSettingsScanSession\b' \
    Sumi/Components/Settings --glob '*.swift' | sort
)"
expected_session_consumers="$(printf '%s\n%s\n' "$session" "$pane" | sort)"
if [[ "$session_consumer_files" != "$expected_session_consumers" ]]; then
  printf 'the scan session must not be passed through semantic sections:\n%s\n' \
    "$session_consumer_files" >&2
  exit 1
fi

for file in "${focused_production[@]}"; do
  line_count="$(wc -l < "$file" | tr -d ' ')"
  if (( line_count > 500 )); then
    echo "extension-settings production file exceeds 500 LOC: $file ($line_count)" >&2
    exit 1
  fi
done

echo "extension-settings scan/session boundary passed"
