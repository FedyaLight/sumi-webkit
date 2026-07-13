#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

pane="Sumi/Components/Settings/SumiExtensionsSettingsPane.swift"
session="Sumi/Components/Settings/ExtensionSettingsScanSession.swift"
installed_section="Sumi/Components/Settings/ExtensionSettingsInstalledSection.swift"
candidate_sections="Sumi/Components/Settings/SafariExtensionImportCandidatesSection.swift"
commands="Sumi/Components/Settings/ExtensionSettingsSectionCommands.swift"
session_tests="SumiTests/ExtensionSettingsScanSessionTests.swift"
command_tests="SumiTests/ExtensionSettingsSectionCommandRoutingTests.swift"
runtime_gate_tests="SumiTests/ExtensionSettingsRuntimeGateTests.swift"

focused_production=(
  "$pane"
  "$session"
  "$installed_section"
  "$candidate_sections"
  "$commands"
  "Sumi/Components/Settings/ExtensionCatalogDetailsPopover.swift"
)

for file in \
  "${focused_production[@]}" \
  "$session_tests" \
  "$command_tests" \
  "$runtime_gate_tests"; do
  if [[ ! -f "$file" ]]; then
    echo "missing extension-settings boundary file: $file" >&2
    exit 1
  fi
done

require_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! rg -q "$pattern" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if rg -n "$pattern" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

require_pattern 'extensionsModule\.managerIfEnabled\(\) != nil' "$pane" \
  "extension settings must preserve fail-closed runtime readiness"
require_pattern 'struct ExtensionSettingsRuntimeGate' "$pane" \
  "extension settings must gate enabled-content construction on readiness"
require_pattern \
  'func testUnavailablePartialRuntimeDoesNotConstructOrBeginScanSession' \
  "$runtime_gate_tests" \
  "missing unavailable extension-runtime construction regression"

require_pattern 'struct ExtensionSettingsScanAttempt' "$session" \
  "extension-settings scan attempts must remain typed"
require_pattern 'private var scanTask: Task<Void, Never>\?' "$session" \
  "the scan session must own the scan task lifetime"
require_pattern 'guard activeAttempt == attempt else' "$session" \
  "terminal scan publication must reject stale attempts"
for state in inert scanning completed failed cancelled; do
  require_pattern "case $state" "$session" \
    "missing extension-settings terminal/session state: $state"
done

reject_pattern \
  'SafariExtensionScanner|\b(scanTask|nextGeneration|activeAttempt)\b|Task[[:space:]]*(<|\{)' \
  "$pane" \
  "SumiExtensionsSettingsPane must not regain scan, task, or generation ownership"

scan_owner_files="$(
  rg -l '\b(scanTask|nextGeneration|activeAttempt)\b' \
    "${focused_production[@]}" || true
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

require_pattern 'struct ExtensionSettingsInstalledSection: View' \
  "$installed_section" \
  "the installed catalog must remain a real semantic section"
require_pattern 'struct ExtensionSettingsContentBlockersSection: View' \
  "$candidate_sections" \
  "content blockers must remain a real semantic section"
require_pattern 'struct ExtensionSettingsUnsupportedSection: View' \
  "$candidate_sections" \
  "unsupported extensions must remain a real semantic section"
require_pattern 'let projection: ExtensionSettingsInstalledProjection' \
  "$installed_section" \
  "the installed section must receive a narrow immutable projection"
require_pattern 'let commands: ExtensionSettingsInstalledCommands' \
  "$installed_section" \
  "the installed section must receive exact commands"
require_pattern 'let commands: ExtensionSettingsContentBlockerCommands' \
  "$candidate_sections" \
  "the content-blocker section must receive exact commands"

session_consumer_files="$(
  rg -l '\bExtensionSettingsScanSession\b' \
    Sumi/Components/Settings --glob '*.swift' | sort
)"
expected_session_consumers="$(printf '%s\n%s\n' "$session" "$pane" | sort)"
if [[ "$session_consumer_files" != "$expected_session_consumers" ]]; then
  printf 'the scan session must not be passed through semantic sections:\n%s\n' \
    "$session_consumer_files" >&2
  exit 1
fi

for test_name in \
  testInitialStateIsInertAndStartsNoScan \
  testFirstScanPublishesTypedTerminalSnapshot \
  testRefreshSupersedesActiveAttempt \
  testRefreshWhileSynchronizeIsSuspendedRejectsCancelledAttemptBeforeBlockerLoad \
  testCancellationPublishesTerminalState \
  testCancelledSessionBeginsAgainWhenPresented \
  testTeardownCancelsAttemptAndReleasesSession \
  testStaleResultCannotReplaceNewerTerminalSnapshot \
  testPartialResultAggregatesScannerAndImportIssues \
  testCapabilityErrorPublishesTerminalFailure; do
  require_pattern "func $test_name" "$session_tests" \
    "missing deterministic extension-settings session regression: $test_name"
done
for test_name in \
  testInstalledSectionCommandRouting \
  testContentBlockerSectionCommandRouting; do
  require_pattern "func $test_name" "$command_tests" \
    "missing extension-settings section command regression: $test_name"
done
reject_pattern 'Task\.sleep|RunLoop|asyncAfter' "$session_tests" \
  "extension-settings session tests must use event-driven synchronization"

for file in "${focused_production[@]}"; do
  line_count="$(wc -l < "$file" | tr -d ' ')"
  if (( line_count > 500 )); then
    echo "extension-settings production file exceeds 500 LOC: $file ($line_count)" >&2
    exit 1
  fi
done

echo "extension-settings scan/session boundary passed"
