#!/usr/bin/env bash
# Shortcut routing must dispatch actions at behaviorful domain boundaries. A
# broad routing protocol or a one-method-per-command forwarding owner is a
# service locator in disguise and is forbidden.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

router='Sumi/Managers/KeyboardShortcutManager/BrowserShortcutActionRouter.swift'
composition='Sumi/Managers/KeyboardShortcutManager/BrowserShortcutActionComposition.swift'
manager='Sumi/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift'
tab_commands='Sumi/Managers/BrowserManager/BrowserKeyboardTabSelectionCommands.swift'
split_commands='Sumi/Managers/BrowserManager/BrowserKeyboardSplitCommands.swift'
space_commands='Sumi/Managers/BrowserManager/BrowserKeyboardSpaceCommands.swift'
reader_commands='Sumi/Managers/BrowserManager/BrowserKeyboardReaderCommands.swift'
selection_roles=(
  Sumi/Managers/BrowserManager/BrowserTabSelectionActivation.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionStateApplication.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionMaterializationOwner.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionChromeEffects.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionMediaEffects.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionPresentationEffects.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionPublicationTransaction.swift
)
browser_root='Sumi/Managers/BrowserManager/BrowserManager.swift'
production_roots=(App Sumi Settings SidebarChrome FloatingBar UI)
shortcut_sources=(
  "$router"
  "$composition"
  "$manager"
  "$tab_commands"
  "$split_commands"
  "$space_commands"
  "$reader_commands"
)

for file in "${shortcut_sources[@]}" "${selection_roles[@]}" "$browser_root"; do
  guard_require_file "$file"
done

guard_expect_no_matches \
  'retired broad shortcut routers stay physically absent' \
  '\b(ShortcutActionRouting|KeyboardShortcutChromeRouting|ShortcutActionDispatcher|BrowserKeyboardShortcutCommandOwner)\b' \
  "${production_roots[@]}" SumiTests -g '*.swift'
guard_expect_no_matches \
  'shortcut source defines no replacement dependency bag' \
  '\bstruct[[:space:]]+(Dependencies|Capabilities|Actions)\b' \
  "${shortcut_sources[@]}"
guard_expect_no_matches \
  'shortcut source stores no provider callbacks' \
  '^[[:space:]]*(private[[:space:]]+)?(let|var)[[:space:]].*->[[:space:]]*' \
  "${shortcut_sources[@]}"
guard_expect_no_matches \
  'shortcut manager has no extension callback slot' \
  '\bextensionCommandHandler\b' \
  "$manager" App/BrowserAppOrchestrationOwner.swift SumiTests
guard_expect_no_matches \
  'shortcut tab and selection roles store no broad shell runtime' \
  '\bBrowserShellRuntime\b' \
  "$tab_commands" "${selection_roles[@]}"
guard_expect_no_matches \
  'shortcut composition cannot recover a browser root' \
  '\bBrowserManager\b|\bbrowserManager\b' \
  "$router" "$composition" "$tab_commands" "$split_commands" \
  "$space_commands" "$reader_commands"

guard_exact \
  'browser root composes shortcut graph once' \
  "$(guard_count_matches 'BrowserShortcutActionComposition\.make\(' "$browser_root")" \
  1
guard_exact \
  'composition constructs shortcut router once' \
  "$(guard_count_matches 'BrowserShortcutActionRouter\(' "$composition")" \
  1
guard_exact \
  'router contains five behaviorful domain dispatchers' \
  "$(guard_count_matches '^final class BrowserShortcut.*CommandDispatcher' "$router")" \
  5
guard_exact \
  'five domain switches plus one domain router' \
  "$(guard_count_matches 'switch action' "$router")" \
  6
guard_exact \
  'shortcut domain classification is exhaustive' \
  "$(guard_count_matches 'switch self' "$router")" \
  1

count_type_collaborators() {
  local type="$1"
  local file="$2"
  awk -v type="$type" '
    $0 ~ "^final class " type "[[:space:]]*\\{" {
      inside = 1
      next
    }
    inside && /^final class / { exit }
    inside && /^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)[[:space:]]/ {
      count += 1
    }
    END { print count + 0 }
  ' "$file"
}

for type in \
  BrowserShortcutPageCommandDispatcher \
  BrowserShortcutTabCommandDispatcher \
  BrowserShortcutWindowSpaceCommandDispatcher \
  BrowserShortcutChromeCommandDispatcher \
  BrowserShortcutOverlayCommandDispatcher \
  BrowserShortcutActionRouter; do
  guard_max "$type collaborators" \
    "$(count_type_collaborators "$type" "$router")" 5
done

guard_max 'BrowserKeyboardTabSelectionCommands collaborators' \
  "$(count_type_collaborators BrowserKeyboardTabSelectionCommands "$tab_commands")" 5
guard_max 'BrowserKeyboardSplitCommands collaborators' \
  "$(count_type_collaborators BrowserKeyboardSplitCommands "$split_commands")" 5
guard_max 'BrowserKeyboardSpaceCommands collaborators' \
  "$(count_type_collaborators BrowserKeyboardSpaceCommands "$space_commands")" 5
guard_max 'BrowserKeyboardReaderCommands collaborators' \
  "$(count_type_collaborators BrowserKeyboardReaderCommands "$reader_commands")" 1
guard_max 'BrowserTabSelectionStateApplication collaborators' \
  "$(count_type_collaborators \
    BrowserTabSelectionStateApplication \
    Sumi/Managers/BrowserManager/BrowserTabSelectionStateApplication.swift)" 5
guard_max 'BrowserTabSelectionMediaEffects collaborators' \
  "$(count_type_collaborators \
    BrowserTabSelectionMediaEffects \
    Sumi/Managers/BrowserManager/BrowserTabSelectionMediaEffects.swift)" 4

guard_finish 'shortcut action routing boundary'
