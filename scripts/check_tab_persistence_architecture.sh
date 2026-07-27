#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  guard_record_failure "$message: $matches"
}

required_files=(
  Sumi/Persistence/SumiDatabase.swift
  Sumi/Persistence/BrowserRecords.swift
  Sumi/Managers/TabManager/TabPersistenceModels.swift
  Sumi/Managers/TabManager/TabPersistenceCodec.swift
  Sumi/Managers/TabManager/TabStoreWriteExecutor.swift
  Sumi/Managers/TabManager/TabStructuralSnapshotStore.swift
  Sumi/Managers/TabManager/TabSelectionStore.swift
  Sumi/Managers/TabManager/TabRuntimeStateStore.swift
  Sumi/Managers/TabManager/TabRestoreStoreReader.swift
  Sumi/Managers/TabManager/TabRestorePlanner.swift
  Sumi/Managers/TabManager/TabRestoreSnapshotBuilder.swift
  Sumi/Managers/TabManager/TabRestoreRuntimeStateBuilder.swift
  Sumi/Managers/TabManager/TabStructuralPersistenceService.swift
  Sumi/Managers/TabManager/TabStoreRestoreService.swift
  Sumi/Managers/TabManager/TabStartupRestoreLifecycle.swift
  Sumi/Managers/TabManager/TabLastSessionMergePlan.swift
  Sumi/Managers/TabManager/TabLastSessionMergePlanner.swift
  Sumi/Managers/TabManager/TabLastSessionMergeMaterializer.swift
  Sumi/Managers/TabManager/TabLastSessionLiveStateSnapshotter.swift
  Sumi/Managers/TabManager/TabLastSessionMergePlanningService.swift
  Sumi/Managers/TabManager/TabLastSessionProfileAdmissionTransaction.swift
  Sumi/Managers/TabManager/TabLastSessionSpaceMaterializer.swift
  Sumi/Managers/TabManager/TabLastSessionFolderMaterializer.swift
  Sumi/Managers/TabManager/TabLastSessionShortcutMaterializer.swift
  Sumi/Managers/TabManager/TabLastSessionRegularTabMaterializer.swift
  Sumi/Managers/TabManager/TabLastSessionSelectionMaterializer.swift
  Sumi/Managers/TabManager/TabLastSessionMergeCommitTransaction.swift
  Sumi/Managers/TabManager/TabLastSessionMergeSettlement.swift
  Sumi/Managers/TabManager/TabStartupStateReset.swift
  Sumi/Managers/TabManager/PreparedTabStartupRuntimeReset.swift
  Sumi/Managers/TabManager/TabStartupRuntimeResetTransaction.swift
  Sumi/Managers/TabManager/TabStartupSplitGroupResetTransaction.swift
  Sumi/Managers/TabManager/TabStartupRegularCollectionResetTransaction.swift
  Sumi/Managers/TabManager/TabStartupTransientStateResetTransaction.swift
)

for file in "${required_files[@]}"; do
  guard_require_file "$file"
done

legacy_files=(
  Sumi/Managers/TabManager/TabManager+OwnerAccessors.swift
  Sumi/Managers/TabManager/TabSnapshotRepository.swift
  Sumi/Managers/TabManager/TabStructuralPersistenceOwner.swift
  Sumi/Managers/TabManager/TabStoreRestoreOwner.swift
  Sumi/Managers/TabManager/TabLastSessionRestoreOwner.swift
  Sumi/Managers/TabManager/TabPersistenceOwnerBag.swift
)

for file in "${legacy_files[@]}"; do
  guard_expect_absent_path 'legacy persistence surface' "$file"
done

legacy_hits="$(
  guard_capture_matches '\bTabSnapshotRepository\b' -g '*.swift' Sumi SumiTests
)"
fail_matches "legacy tab persistence god-object reintroduced" "$legacy_hits"

legacy_composition_hits="$(
  guard_capture_matches \
    '\b(TabPersistenceOwnerBag|persistenceOwners|TabStructuralPersistenceOwner|TabStoreRestoreOwner)\b' \
    -g '*.swift' Sumi SumiTests
)"
fail_matches "legacy persistence composition surface reintroduced" "$legacy_composition_hits"

persistence_service_reachback_hits="$(
  guard_capture_matches \
    '\btabManager\b|\bstruct Dependencies\b' \
    Sumi/Managers/TabManager/TabServiceContracts.swift \
    Sumi/Managers/TabManager/TabStructuralPersistenceService.swift \
    Sumi/Managers/TabManager/TabStoreRestoreService.swift \
    Sumi/Managers/TabManager/TabStartupRestoreLifecycle.swift
)"
fail_matches "persistence service reached back through TabManager or a dependency bag" "$persistence_service_reachback_hits"

runtime_store_manager_init_hits="$(
  guard_capture_matches \
    '(convenience )?init\(tabManager: TabManager\)' \
    Sumi/Managers/TabManager/TabServiceContracts.swift
)"
fail_matches "runtime tab store recovered a TabManager service-locator initializer" "$runtime_store_manager_init_hits"

startup_restore_forwarder_hits="$(
  guard_capture_matches \
    '\b(var|func) (hasLoadedInitialData|didStartPersistedStateLoad|markInitialDataLoadStarted|markInitialDataLoadFinished|startPersistedStateLoadIfNeeded|startPersistedStateLoadAfterRuntimeAttachmentIfConfigured)\b' \
    Sumi/Managers/TabManager/TabManager.swift
)"
fail_matches "startup restore lifecycle leaked back onto TabManager" "$startup_restore_forwarder_hits"

tab_manager_persistence_surface_hits="$(
  guard_capture_matches \
    '(lazy[[:space:]]+var|let|var)[[:space:]]+(runtimeStore|storeRestore|startupStateReset|lastSessionMergeMaterializer)\b' \
    Sumi/Managers/TabManager/TabManager.swift
)"
fail_matches "assembled persistence behavior returned to TabManager" "$tab_manager_persistence_surface_hits"

if (( $(
  guard_count_matches \
    'let structuralPersistence:' \
    Sumi/Managers/TabManager/TabManager.swift
) != 1 )); then
  guard_record_failure "TabManager must retain exactly one base structural persistence mechanism"
fi

composition_root='Sumi/BrowserRuntime/BrowserCompositionRoot+TabSession.swift'
guard_require_file "$composition_root"
store_restore_factory='Sumi/BrowserRuntime/BrowserTabStoreRestoreFactory.swift'
startup_reset_factory='Sumi/BrowserRuntime/BrowserTabStartupStateResetFactory.swift'
last_session_merge_factory='Sumi/BrowserRuntime/BrowserLastSessionMergeFactory.swift'
for file in \
  "$store_restore_factory" \
  "$startup_reset_factory" \
  "$last_session_merge_factory"; do
  guard_require_file "$file"
done
eager_persistence_contracts=(
  'let runtimeStore = DefaultTabRuntimeStore\('
  'let storeRestore = BrowserTabStoreRestoreFactory\.make\('
  'let startupStateReset = BrowserTabStartupStateResetFactory\.make\('
  'let lastSessionMergeMaterializer = BrowserLastSessionMergeFactory\.make\('
)
for pattern in "${eager_persistence_contracts[@]}"; do
  count="$(guard_count_matches "$pattern" "$composition_root")"
  if (( count != 1 )); then
    guard_record_failure "eager persistence composition changed: $pattern ($count != 1)"
  fi
done
guard_exact \
  'store-restore factory constructs one service' \
  "$(guard_count_matches 'TabStoreRestoreService\(' "$store_restore_factory")" \
  1
guard_exact \
  'startup-reset factory constructs one transaction' \
  "$(guard_count_matches 'TabStartupStateReset\(' "$startup_reset_factory")" \
  1
guard_exact \
  'last-session factory constructs one materializer' \
  "$(guard_count_matches 'TabLastSessionMergeMaterializer\(' "$last_session_merge_factory")" \
  1

legacy_last_session_hits="$(
  guard_capture_matches \
    '\bTabLastSessionRestoreOwner\b|\blastSessionRestoreOwner\b|resetRegularTabsAndShortcutLiveInstancesForStartup' \
    -g '*.swift' Sumi SumiTests
)"
fail_matches "legacy last-session restore god-object reintroduced" "$legacy_last_session_hits"

last_session_manager_hits="$(
  guard_capture_matches \
    '\bTabManager\b|\bstruct Dependencies\b' \
    Sumi/Managers/TabManager/TabLastSessionMergePlanner.swift \
    Sumi/Managers/TabManager/TabLastSessionMergeMaterializer.swift \
    Sumi/Managers/TabManager/TabStartupStateReset.swift
)"
fail_matches "last-session components reached back through TabManager or a dependency bag" "$last_session_manager_hits"

last_session_planner_mechanism_hits="$(
  guard_capture_matches \
    '^import AppKit$|\b(TabStateStore|Space|TabFolder|ShortcutPin|RuntimePortRegistry)\b' \
    Sumi/Managers/TabManager/TabLastSessionMergePlanner.swift
)"
fail_matches "pure last-session planning depends on mutable browser mechanisms" "$last_session_planner_mechanism_hits"

loader_mechanism_hits="$(
  guard_capture_matches \
    '^import GRDB$|\b(DatabasePool|DatabaseQueue|SQLRequest|FetchDescriptor)\b' \
    Sumi/Managers/TabManager/TabRestoreLoader.swift
)"
fail_matches "restore loader absorbed raw persistence-mechanism queries" "$loader_mechanism_hits"

planner_store_hits="$(
  guard_capture_matches \
    '^import GRDB$|\b(DatabasePool|DatabaseQueue|SQLRequest|FetchDescriptor)\b' \
    Sumi/Managers/TabManager/TabRestorePlanner.swift \
    Sumi/Managers/TabManager/TabRestoreStructurePlanner.swift \
    Sumi/Managers/TabManager/TabRestoreTabPlanner.swift \
    Sumi/Managers/TabManager/TabRestoreSnapshotBuilder.swift
)"
fail_matches "pure restore planning depends on the persistence mechanism" "$planner_store_hits"

structural_cross_surface_hits="$(
  guard_capture_matches \
    '\b(TabSelectionStore|TabRuntimeStateStore|TabRuntimeStateUpdate)\b' \
    Sumi/Managers/TabManager/TabStructuralSnapshotStore.swift
)"
fail_matches "structural store absorbed selection or runtime-state persistence" "$structural_cross_surface_hits"

new_owner_hits="$(
  guard_capture_matches \
    '\b(class|actor|struct)\s+Tab(Persistence|Restore|Store|StructuralSnapshot)[A-Za-z0-9_]*Owner\b' \
    "${required_files[@]}"
)"
fail_matches "new tab persistence responsibility hidden behind an Owner type" "$new_owner_hits"

bounded_files=(
  Sumi/Managers/TabManager/TabStructuralSnapshotStore.swift:180
  Sumi/Managers/TabManager/TabStoreWriteExecutor.swift:150
  Sumi/Managers/TabManager/TabRestoreLoader.swift:140
  Sumi/Managers/TabManager/TabRestorePlanner.swift:140
  Sumi/Managers/TabManager/TabRestoreTabPlanner.swift:280
  Sumi/Managers/TabManager/TabRestoreStructurePlanner.swift:220
  Sumi/Managers/TabManager/TabRestoreSnapshotBuilder.swift:140
  Sumi/Managers/TabManager/TabRestoreRuntimeStateBuilder.swift:180
  Sumi/Managers/TabManager/TabStructuralPersistenceService.swift:420
  Sumi/Managers/TabManager/TabStoreRestoreService.swift:260
  Sumi/Managers/TabManager/TabStartupRestoreLifecycle.swift:100
  Sumi/Managers/TabManager/TabLastSessionMergePlan.swift:160
  Sumi/Managers/TabManager/TabLastSessionMergePlanner.swift:340
  Sumi/Managers/TabManager/TabLastSessionMergeMaterializer.swift:100
  Sumi/Managers/TabManager/TabLastSessionLiveStateSnapshotter.swift:140
  Sumi/Managers/TabManager/TabLastSessionMergePlanningService.swift:50
  Sumi/Managers/TabManager/TabLastSessionProfileAdmissionTransaction.swift:60
  Sumi/Managers/TabManager/TabLastSessionSpaceMaterializer.swift:100
  Sumi/Managers/TabManager/TabLastSessionFolderMaterializer.swift:100
  Sumi/Managers/TabManager/TabLastSessionShortcutMaterializer.swift:100
  Sumi/Managers/TabManager/TabLastSessionRegularTabMaterializer.swift:120
  Sumi/Managers/TabManager/TabLastSessionSelectionMaterializer.swift:60
  Sumi/Managers/TabManager/TabLastSessionMergeCommitTransaction.swift:80
  Sumi/Managers/TabManager/TabLastSessionMergeSettlement.swift:50
  Sumi/Managers/TabManager/TabStartupStateReset.swift:100
  Sumi/Managers/TabManager/PreparedTabStartupRuntimeReset.swift:20
  Sumi/Managers/TabManager/TabStartupRuntimeResetTransaction.swift:100
  Sumi/Managers/TabManager/TabStartupSplitGroupResetTransaction.swift:100
  Sumi/Managers/TabManager/TabStartupRegularCollectionResetTransaction.swift:80
  Sumi/Managers/TabManager/TabStartupTransientStateResetTransaction.swift:60
  Sumi/Managers/TabManager/TabManager.swift:220
)

for specification in "${bounded_files[@]}"; do
  file="${specification%%:*}"
  maximum="${specification##*:}"
  guard_max \
    "$file persistence-role LOC" \
    "$(guard_count_lines "$file")" \
    "$maximum"
done

guard_finish 'tab persistence architecture boundary'
