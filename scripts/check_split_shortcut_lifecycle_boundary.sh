#!/usr/bin/env bash
# Split-shortcut focus, unload and close paths retain concrete
# behavioral roles. Lifetime callback slots and replacement bags are forbidden.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

sources=(
  Sumi/Managers/BrowserManager/SplitShortcutFocusPresentationService.swift
  Sumi/Managers/BrowserManager/SplitShortcutFocusService.swift
  Sumi/Managers/BrowserManager/ShortcutHostedSplitUnloadService.swift
  Sumi/Managers/BrowserManager/ShortcutHostedSplitFallbackQuery.swift
  Sumi/Managers/BrowserManager/ShortcutLiveTabCloseService.swift
  Sumi/Managers/BrowserManager/ShortcutLiveTabSplitCloseTransaction.swift
  Sumi/Managers/BrowserManager/ShortcutLiveTabStandaloneCloseTransaction.swift
  Sumi/Managers/BrowserManager/ShortcutLiveTabClosePublication.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherDestinationResolver.swift
)

for file in "${sources[@]}"; do
  guard_require_file "$file"
done

guard_expect_no_matches \
  'split shortcut lifecycle stores no callbacks' \
  '^[[:space:]]*private[[:space:]]+(let|var)[[:space:]].*->[[:space:]]*' \
  "${sources[@]}"
guard_expect_no_matches \
  'split shortcut lifecycle exposes no optional notification provider' \
  'notifications:[[:space:]]*(@escaping|@MainActor|\(\))|\(\)[[:space:]]*->[[:space:]]*\(any[[:space:]]+BrowserNotificationPresenting\)\?' \
  "${sources[@]}"
guard_expect_no_matches \
  'retired split shortcut callback initializer labels stay absent' \
  'folderSpaceID:|topLevelItemCount:|selectTabWithoutPersistence:|performImmediateVisualHandoff:|refreshCompositor:|unloadShortcutHostedSplitGroup:|restoreShortcutSplitMember:' \
  "${sources[@]}"
guard_expect_no_matches \
  'split shortcut lifecycle defines no replacement bag' \
  '\bstruct[[:space:]]+(Dependencies|Capabilities|Actions|OwnerBag)\b' \
  "${sources[@]}"
guard_expect_no_matches \
  'split shortcut lifecycle defines no forwarding protocol surface' \
  '^[[:space:]]*(public[[:space:]]+|private[[:space:]]+|internal[[:space:]]+)?protocol[[:space:]]' \
  "${sources[@]}"
guard_expect_no_matches \
  'split shortcut lifecycle cannot recover a manager root' \
  '\b(browserManager|tabManager)\b|:[[:space:]]*(BrowserManager|TabManager)[?!]?' \
  "${sources[@]}"

declare -a type_limits=(
  'SplitShortcutFocusPresentationService|3'
  'SplitShortcutFocusService|4'
  'ShortcutHostedSplitFallbackQuery|2'
  'ShortcutHostedSplitUnloadService|5'
  'ShortcutLiveTabCloseService|4'
  'ShortcutLiveTabSplitCloseTransaction|3'
  'ShortcutLiveTabStandaloneCloseTransaction|5'
  'ShortcutLiveTabClosePublication|3'
  'ShortcutSplitLauncherDestinationResolver|2'
)

count_type_collaborators() {
  local type="$1"
  awk -v type="$type" '
    $0 ~ "^(final class|struct) " type "[[:space:]]*\\{" {
      inside = 1
      next
    }
    inside && /^(final class|struct) / { exit }
    inside && /^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)[[:space:]]/ {
      count += 1
    }
    END { print count + 0 }
  ' "${sources[@]}"
}

for type_limit in "${type_limits[@]}"; do
  IFS='|' read -r type maximum <<< "$type_limit"
  guard_exact \
    "one concrete ${type}" \
    "$(guard_count_matches "^(final[[:space:]]+class|struct)[[:space:]]+${type}\\b" "${sources[@]}")" \
    1
  guard_max \
    "${type} collaborators" \
    "$(count_type_collaborators "$type")" \
    "$maximum"
done

guard_finish 'split-shortcut lifecycle boundary'
