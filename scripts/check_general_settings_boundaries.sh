#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

root="Sumi/Components/Settings/Tabs/General.swift"
window_section="Sumi/Components/Settings/Tabs/GeneralWindowSettingsSection.swift"
new_tabs_section="Sumi/Components/Settings/Tabs/GeneralNewTabsSettingsSection.swift"
search_section="Sumi/Components/Settings/Tabs/GeneralSearchSettingsSection.swift"
engines_section="Sumi/Components/Settings/Tabs/GeneralSearchEnginesSettingsSection.swift"
engine_table="Sumi/Components/Settings/Tabs/SumiSearchEngineTableController.swift"
engine_row="Sumi/Components/Settings/Tabs/SumiSearchEngineTableRowCell.swift"
engine_editor="Sumi/Components/Settings/Tabs/GeneralSearchEngineEditorAlert.swift"
mutation="Sumi/Components/Settings/Tabs/GeneralSearchEngineMutation.swift"

production=(
  "$root"
  "$window_section"
  "$new_tabs_section"
  "$search_section"
  "$engines_section"
  "$engine_table"
  "$engine_row"
  "$engine_editor"
  "$mutation"
)

for file in "${production[@]}"; do
  guard_require_file "$file"
done

require_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  local match_count
  match_count="$(guard_count_matches "$pattern" "$file")" || return
  if (( match_count == 0 )); then
    guard_record_failure "$message"
  fi
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  local matches
  matches="$(guard_capture_matches "$pattern" "$file")" || return
  if [[ -n "$matches" ]]; then
    guard_record_failure "$message: $matches"
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
  "$engine_table"
  "$engine_row"
  "$engine_editor"
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
require_pattern 'NSViewControllerRepresentable' "$engine_table" \
  "Search Engines must bridge its AppKit controller through a narrow representable"
require_pattern 'NSTableViewDataSource' "$engine_table" \
  "Search Engines must retain native AppKit table ownership"
require_pattern 'registerForDraggedTypes' "$engine_table" \
  "Search Engines must retain native row reordering"
reject_pattern '@State|ReorderDragState|\.sheet\(|\.confirmationDialog\(' "$engine_table" \
  "Search Engines transient interaction state must remain AppKit-owned"
require_pattern 'NSAlert' "$engine_editor" \
  "Search-engine editing must remain a native AppKit sheet"
reject_pattern 'SwiftUI|@State|\.sheet\(' "$engine_editor" \
  "Search-engine editor must not regain SwiftUI presentation state"

require_pattern 'enum GeneralSearchEngineMutation' "$mutation" \
  "Search-engine command/reorder seams must remain stateless"
reject_pattern '@Observable|class GeneralSearchEngineMutation|static var' "$mutation" \
  "Search-engine mutation seams must not become a new observable owner or hidden authority"

for file in "${production[@]}"; do
  reject_pattern \
    'Timer|Task[<(]|\.task\b|\.onReceive\b|NotificationCenter|RunLoop|asyncAfter|\bpoll' \
    "$file" \
    "General settings must add no idle observers, tasks, timers, or polling: $file"

  guard_max \
    "$file General-settings LOC" \
    "$(guard_count_lines "$file")" \
    499
done

guard_finish 'General settings view boundaries'
