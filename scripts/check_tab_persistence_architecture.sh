#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

required_files=(
  Sumi/Managers/TabManager/TabPersistenceModels.swift
  Sumi/Managers/TabManager/TabPersistenceCodec.swift
  Sumi/Managers/TabManager/TabStoreRecordQueries.swift
  Sumi/Managers/TabManager/TabStoreRecordMutation.swift
  Sumi/Managers/TabManager/TabStructuralStoreMutation.swift
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
  Sumi/Managers/TabManager/TabStartupStateReset.swift
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: tab persistence boundary missing: %s\n' "$file" >&2
    status=1
  fi
done

legacy_files=(
  Sumi/Managers/TabManager/TabSnapshotRepository.swift
  Sumi/Managers/TabManager/TabStructuralPersistenceOwner.swift
  Sumi/Managers/TabManager/TabStoreRestoreOwner.swift
  Sumi/Managers/TabManager/TabLastSessionRestoreOwner.swift
  Sumi/Managers/TabManager/TabPersistenceOwnerBag.swift
)

for file in "${legacy_files[@]}"; do
  if [[ -e "$file" ]]; then
    printf 'error: legacy persistence surface still exists: %s\n' "$file" >&2
    status=1
  fi
done

legacy_hits="$(
  rg -n '\bTabSnapshotRepository\b' Sumi SumiTests -g '*.swift' || true
)"
fail_matches "legacy tab persistence god-object reintroduced" "$legacy_hits"

legacy_composition_hits="$(
  rg -n '\b(TabPersistenceOwnerBag|persistenceOwners|TabStructuralPersistenceOwner|TabStoreRestoreOwner)\b' \
    Sumi SumiTests -g '*.swift' || true
)"
fail_matches "legacy persistence composition surface reintroduced" "$legacy_composition_hits"

persistence_service_reachback_hits="$(
  rg -n '\btabManager\b|\bstruct Dependencies\b' \
    Sumi/Managers/TabManager/TabServiceContracts.swift \
    Sumi/Managers/TabManager/TabStructuralPersistenceService.swift \
    Sumi/Managers/TabManager/TabStoreRestoreService.swift \
    Sumi/Managers/TabManager/TabStartupRestoreLifecycle.swift || true
)"
fail_matches "persistence service reached back through TabManager or a dependency bag" "$persistence_service_reachback_hits"

runtime_store_manager_init_hits="$(
  rg -n '(convenience )?init\(tabManager: TabManager\)' \
    Sumi/Managers/TabManager/TabServiceContracts.swift || true
)"
fail_matches "runtime tab store recovered a TabManager service-locator initializer" "$runtime_store_manager_init_hits"

persistence_forwarder_hits="$(
  rg -n 'var (runtimeStore|structuralPersistence|storeRestore):' \
    Sumi/Managers/TabManager/TabManager+OwnerAccessors.swift || true
)"
fail_matches "persistence component hidden behind a forwarding accessor" "$persistence_forwarder_hits"

startup_restore_forwarder_hits="$(
  rg -n '\b(var|func) (hasLoadedInitialData|didStartPersistedStateLoad|markInitialDataLoadStarted|markInitialDataLoadFinished|startPersistedStateLoadIfNeeded|startPersistedStateLoadAfterRuntimeAttachmentIfConfigured)\b' \
    Sumi/Managers/TabManager/TabManager.swift || true
)"
fail_matches "startup restore lifecycle leaked back onto TabManager" "$startup_restore_forwarder_hits"

direct_component_patterns=(
  'lazy var runtimeStore([:]|[[:space:]])'
  'let structuralPersistence:'
  'lazy var storeRestore([:]|[[:space:]])'
  'lazy var startupStateReset([:]|[[:space:]])'
  'lazy var lastSessionMergeMaterializer([:]|[[:space:]])'
)

for pattern in "${direct_component_patterns[@]}"; do
  if ! rg -q "$pattern" Sumi/Managers/TabManager/TabManager.swift; then
    printf 'error: direct TabManager persistence component missing: %s\n' "$pattern" >&2
    status=1
  fi
done

legacy_last_session_hits="$(
  rg -n '\bTabLastSessionRestoreOwner\b|\blastSessionRestoreOwner\b|resetRegularTabsAndShortcutLiveInstancesForStartup' \
    Sumi SumiTests -g '*.swift' || true
)"
fail_matches "legacy last-session restore god-object reintroduced" "$legacy_last_session_hits"

last_session_manager_hits="$(
  rg -n '\bTabManager\b|\bstruct Dependencies\b' \
    Sumi/Managers/TabManager/TabLastSessionMergePlanner.swift \
    Sumi/Managers/TabManager/TabLastSessionMergeMaterializer.swift \
    Sumi/Managers/TabManager/TabStartupStateReset.swift || true
)"
fail_matches "last-session components reached back through TabManager or a dependency bag" "$last_session_manager_hits"

last_session_planner_mechanism_hits="$(
  rg -n '^import AppKit$|\b(TabStateStore|Space|TabFolder|ShortcutPin|RuntimePortRegistry)\b' \
    Sumi/Managers/TabManager/TabLastSessionMergePlanner.swift || true
)"
fail_matches "pure last-session planning depends on mutable browser mechanisms" "$last_session_planner_mechanism_hits"

loader_mechanism_hits="$(
  rg -n '\b(ModelContext|FetchDescriptor|TabEntity|FolderEntity|SpaceEntity|TabsStateEntity)\b' \
    Sumi/Managers/TabManager/TabRestoreLoader.swift || true
)"
fail_matches "restore loader absorbed SwiftData query or entity mapping" "$loader_mechanism_hits"

planner_store_hits="$(
  rg -n '^import SwiftData$|\b(ModelContainer|ModelContext|FetchDescriptor)\b' \
    Sumi/Managers/TabManager/TabRestorePlanner.swift \
    Sumi/Managers/TabManager/TabRestoreStructurePlanner.swift \
    Sumi/Managers/TabManager/TabRestoreTabPlanner.swift \
    Sumi/Managers/TabManager/TabRestoreSnapshotBuilder.swift || true
)"
fail_matches "pure restore planning depends on the persistence mechanism" "$planner_store_hits"

structural_cross_surface_hits="$(
  rg -n '\b(TabSelectionStore|TabRuntimeStateStore|TabRuntimeStateUpdate)\b' \
    Sumi/Managers/TabManager/TabStructuralSnapshotStore.swift || true
)"
fail_matches "structural store absorbed selection or runtime-state persistence" "$structural_cross_surface_hits"

new_owner_hits="$(
  rg -n '\b(class|actor|struct)\s+Tab(Persistence|Restore|Store|StructuralSnapshot)[A-Za-z0-9_]*Owner\b' \
    "${required_files[@]}" || true
)"
fail_matches "new tab persistence responsibility hidden behind an Owner type" "$new_owner_hits"

bounded_files=(
  Sumi/Managers/TabManager/TabStructuralSnapshotStore.swift:180
  Sumi/Managers/TabManager/TabStoreWriteExecutor.swift:120
  Sumi/Managers/TabManager/TabRestoreLoader.swift:80
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
  Sumi/Managers/TabManager/TabLastSessionMergeMaterializer.swift:360
  Sumi/Managers/TabManager/TabStartupStateReset.swift:120
  Sumi/Managers/TabManager/TabManager.swift:220
)

for specification in "${bounded_files[@]}"; do
  file="${specification%%:*}"
  maximum="${specification##*:}"
  [[ -f "$file" ]] || continue
  lines="$(wc -l < "$file" | tr -d ' ')"
  if (( lines > maximum )); then
    printf 'error: %s grew to %s LOC (maximum %s); split the responsibility instead of rebuilding a monolith\n' \
      "$file" "$lines" "$maximum" >&2
    status=1
  fi
done

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo "tab persistence architecture boundary passed"
