#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

root="Sumi/Components/Settings/Tabs/General.swift"
window_section="Sumi/Components/Settings/Tabs/GeneralWindowSettingsSection.swift"
new_tabs_section="Sumi/Components/Settings/Tabs/GeneralNewTabsSettingsSection.swift"
search_section="Sumi/Components/Settings/Tabs/GeneralSearchSettingsSection.swift"
engines_section="Sumi/Components/Settings/Tabs/GeneralSearchEnginesSettingsSection.swift"
mutation="Sumi/Components/Settings/Tabs/GeneralSearchEngineMutation.swift"
editor="Sumi/Components/Settings/Tabs/SearchEngineEditor.swift"
tests="SumiTests/GeneralSettingsBoundaryTests.swift"

production=(
  "$root"
  "$window_section"
  "$new_tabs_section"
  "$search_section"
  "$engines_section"
  "$mutation"
  "$editor"
)

for file in "${production[@]}" "$tests"; do
  if [[ ! -f "$file" ]]; then
    echo "missing General settings boundary file: $file" >&2
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

for section in \
  GeneralWindowSettingsSection \
  GeneralNewTabsSettingsSection \
  GeneralSearchSettingsSection \
  GeneralSearchEnginesSettingsSection; do
  require_pattern "${section}\\(" "$root" \
    "General root must compose $section"
done
require_pattern 'DefaultBrowserSettingsSection\(' "$root" \
  "General root must preserve the existing Default Browser section"
reject_pattern \
  '^[[:space:]]*SettingsSection\(|@State|\.sheet\(|\.confirmationDialog\(|SumiNewTabPageURL|GeneralSearchEngineMutation|ReorderDragState' \
  "$root" \
  "General.swift must remain composition-only and must not regain business sections or interaction state"

children=(
  "$window_section"
  "$new_tabs_section"
  "$search_section"
  "$engines_section"
  "$editor"
)
for file in "${children[@]}"; do
  reject_pattern \
    'SumiSettingsService|BrowserManager|SettingsManager|GeneralSettings(Context|Actions|Dependencies)|Settings(DependencyBag|Context|Actions|Dependencies)|ServiceLocator|@Environment\([^)]*sumiSettings' \
    "$file" \
    "General child must not receive or recover a broad settings/service/context/bag dependency: $file"
done

require_pattern '@Binding private var askBeforeQuit: Bool' "$window_section" \
  "Window section must receive the exact quit-warning binding"
require_pattern '@Binding private var glanceEnabled: Bool' "$window_section" \
  "Window section must receive the exact Glance binding"
require_pattern '@Binding private var mode: SumiNewTabMode' "$new_tabs_section" \
  "New Tabs section must receive the exact mode binding"
require_pattern '@Binding private var pageURLString: String' "$new_tabs_section" \
  "New Tabs section must receive the exact URL binding"
require_pattern 'let engineChoices: \[GeneralSearchEngineChoice\]' "$search_section" \
  "Search section must receive immutable id/name choices"
reject_pattern 'let engine: SumiSearchEngine' "$search_section" \
  "Search choices must not retain the full engine value"

require_pattern '@Binding private var searchEngines: \[SumiSearchEngine\]' "$engines_section" \
  "Search Engines section must bind only to the durable engine list"
reject_pattern '@Binding[^\n]*(default|searchEngineId)' "$engines_section" \
  "Search Engines must rely on SearchSettingsStore for default-ID repair"
for state in \
  searchEngineFilter \
  editingSearchEngine \
  searchEnginePendingRemoval \
  showingRestoreDefaultsConfirmation \
  searchEngineReorder; do
  require_pattern "@State private var ${state}" "$engines_section" \
    "Search Engines must locally own transient interaction state: $state"
done

require_pattern 'enum GeneralSearchEngineMutation' "$mutation" \
  "Search-engine command/reorder seams must remain stateless"
reject_pattern '@Observable|class GeneralSearchEngineMutation|static var' "$mutation" \
  "Search-engine mutation seams must not become a new observable owner or hidden authority"

for test_name in \
  testSearchStoreRepairsDefaultAfterSelectedEngineRemoval \
  testSearchStoreRepairsCustomDefaultWhenRestoringDefaults \
  testUnrelatedStoreMutationDoesNotInvalidateObservedWindowSetting \
  testSectionConstructionNeedsOnlyExactBindingsAndProjections; do
  require_pattern "func ${test_name}" "$tests" \
    "missing General settings boundary regression: $test_name"
done
require_pattern 'settings\.search\.searchEngines =' "$tests" \
  "default repair tests must exercise the real SearchSettingsStore setter"
reject_pattern 'Task\.sleep|RunLoop|asyncAfter' "$tests" \
  "General settings tests must remain deterministic without polling"

for file in "${production[@]}"; do
  reject_pattern \
    'Timer|Task[<(]|\.task\b|\.onReceive\b|NotificationCenter|RunLoop|asyncAfter|\bpoll' \
    "$file" \
    "General settings must add no idle observers, tasks, timers, or polling: $file"

  line_count="$(wc -l < "$file" | tr -d ' ')"
  if (( line_count >= 500 )); then
    echo "General settings production file must stay below 500 LOC: $file ($line_count)" >&2
    exit 1
  fi
done

echo "General settings view boundaries passed"
