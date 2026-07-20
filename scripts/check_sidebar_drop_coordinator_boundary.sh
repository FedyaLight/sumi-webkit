#!/usr/bin/env bash
# Sidebar drop commit must not reach BrowserManager/TabManager through
# SidebarDropCoordinator. Source projection lives in SidebarDragSourceInventory;
# mutation stays on SidebarDragOperationExecuting / the existing router.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

status=0

coordinator='Sumi/Components/DragDrop/SidebarDropCoordinator.swift'
inventory='Sumi/Components/DragDrop/SidebarDragSourceInventory.swift'
executing='Sumi/Components/DragDrop/SidebarDragOperationExecuting.swift'
projection='Sumi/Components/DragDrop/SidebarDropProjection.swift'
port='Sumi/Components/DragDrop/SidebarDragTransactionPort.swift'
composition='Sumi/Managers/BrowserManager/BrowserManager+WindowSidebarComposition.swift'
router='Sumi/Managers/TabManager/SidebarDragOperationRouter.swift'
router_roles=(
  Sumi/Managers/TabManager/SidebarDragPayloadResolver.swift
  Sumi/Managers/TabManager/SidebarDragContextValidationService.swift
  Sumi/Managers/TabManager/SidebarCanonicalDragMutation.swift
  Sumi/Managers/TabManager/SidebarDragOperationTransaction.swift
  Sumi/Managers/TabManager/SidebarExplicitTabMoveTransaction.swift
  "$router"
)

for file in "$coordinator" "$inventory" "$executing" "$projection" "$port" "$composition" "${router_roles[@]}"; do
  guard_require_file "$file"
done
for role_file in "${router_roles[@]}"; do
  role="$(basename "$role_file" .swift)"
  guard_exact \
    "$role stays in its role-exact file" \
    "$(guard_count_matches "^final[[:space:]]+class[[:space:]]+${role}\\b" "$role_file")" \
    1
  guard_exact \
    "$role file owns one top-level role" \
    "$(guard_count_matches '^final[[:space:]]+class[[:space:]]+' "$role_file")" \
    1
  guard_max \
    "$role stored collaborators" \
    "$(guard_count_matches '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)[[:space:]]' "$role_file")" \
    5
done

# Coordinator must not accept or mention manager roots.
coordinator_manager_hits="$(
  guard_capture_matches '\bBrowserManager\b|\bTabManager\b' "$coordinator"
)"
if [[ -n "$coordinator_manager_hits" ]]; then
  guard_record_failure "SidebarDropCoordinator regained BrowserManager/TabManager reach-through:
$coordinator_manager_hits"
fi

# Read inventory must not hold manager roots or DI bags.
inventory_manager_hits="$(
  guard_capture_matches '\bBrowserManager\b|\bTabManager\b' "$inventory"
)"
if [[ -n "$inventory_manager_hits" ]]; then
  guard_record_failure "SidebarDragSourceInventory contains manager-root:
$inventory_manager_hits"
fi

closure_bag_hits="$(
  guard_capture_matches '\bstruct[[:space:]]+Dependencies\b|\bstruct[[:space:]]+Actions\b' \
    "$coordinator" "$inventory" "$executing" "$projection" "${router_roles[@]}"
)"
if [[ -n "$closure_bag_hits" ]]; then
  guard_record_failure "sidebar drop boundary grew a Dependencies/Actions closure bag:
$closure_bag_hits"
fi

guard_expect_no_matches \
  'sidebar drag roles store no callback dependencies' \
  '^[[:space:]]*private[[:space:]]+(let|var)[[:space:]].*->[[:space:]]*' \
  "${router_roles[@]}"

# Coordinator must not take raw structure owners back as collaborators.
owner_reach_hits="$(
  guard_capture_matches 'ShortcutPinCollectionStateOwner|SplitGroupSidebarOrderingService|RegularTabCollectionOwner|TabFolderCollectionStateOwner|SpacePinnedStructureOwner' \
    "$coordinator"
)"
if [[ -n "$owner_reach_hits" ]]; then
  guard_record_failure "SidebarDropCoordinator received direct owner reach-through:
$owner_reach_hits"
fi

# Coordinator must compose through the narrow inventory + operation seams.
required_contracts=(
  "$coordinator|sourceInventory:[[:space:]]*any[[:space:]]+SidebarDragSourceInventorying|SidebarDropCoordinator lost SidebarDragSourceInventorying collaborator"
  "$coordinator|dragOperations:[[:space:]]*any[[:space:]]+SidebarDragOperationExecuting|SidebarDropCoordinator lost SidebarDragOperationExecuting collaborator"
  "$executing|protocol[[:space:]]+SidebarDragOperationExecuting|SidebarDragOperationExecuting protocol missing"
  "$executing|extension[[:space:]]+SidebarDragOperationRouter:[[:space:]]*SidebarDragOperationExecuting|SidebarDragOperationRouter must remain the live operation authority"
  "$composition|SidebarDragSourceInventory\\(|window-view composition must build SidebarDragSourceInventory"
  "$composition|dragOperations:[[:space:]]*(self\\.)?sidebarDragRouter|window-sidebar composition must pass the eager sidebarDragRouter"
  "$composition|dragTransactions:[[:space:]]*dragTransactions|window-view composition must pass the exact transaction port"
  "$port|windows\\.contains\\(windowState\\)|SidebarDragTransactionPort must validate exact window identity"
)
for contract in "${required_contracts[@]}"; do
  file="${contract%%|*}"
  remainder="${contract#*|}"
  pattern="${remainder%%|*}"
  message="${remainder#*|}"
  match_count="$(guard_count_matches "$pattern" "$file")"
  if (( match_count == 0 )); then
    guard_record_failure "$message"
  fi
done
runtime_router_reach="$(
  awk '
    /func commit\(/ { in_drop = 1 }
    in_drop { print }
    in_drop && /^[[:space:]]*\},?$/ { exit }
  ' "$port" | guard_capture_matches 'tabManager\.|browserManager\.' -
)"
if [[ -n "$runtime_router_reach" ]]; then
  guard_record_failure "sidebar drop transaction resolves manager roots during the operation:
$runtime_router_reach"
fi

# Focused surface size caps keep the inventory from becoming a god-object.
inventory_lines="$(guard_count_lines "$inventory")"
inventory_collaborators="$(
  guard_count_matches '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' "$inventory"
)"
coordinator_lines="$(guard_count_lines "$coordinator")"
executing_lines="$(guard_count_lines "$executing")"

if (( inventory_lines > 200 )); then
  printf 'error: SidebarDragSourceInventory exceeded focused LOC cap (%s > 200)\n' \
    "$inventory_lines" >&2
  status=1
fi
if (( ${inventory_collaborators:-0} > 5 )); then
  printf 'error: SidebarDragSourceInventory became a collaboration hub (%s > 5)\n' \
    "${inventory_collaborators:-0}" >&2
  status=1
fi
if (( coordinator_lines > 160 )); then
  printf 'error: SidebarDropCoordinator exceeded focused LOC cap (%s > 160)\n' \
    "$coordinator_lines" >&2
  status=1
fi
if (( executing_lines > 40 )); then
  printf 'error: SidebarDragOperationExecuting exceeded focused LOC cap (%s > 40)\n' \
    "$executing_lines" >&2
  status=1
fi

composition_manager_recovery="$(
  guard_capture_matches '\btabManager\b|let[[:space:]]+tabs[[:space:]]*=[[:space:]]*(tabManager|self)' \
    "$composition"
)"
if [[ -n "$composition_manager_recovery" ]]; then
  guard_record_failure "window-sidebar drag composition recovered exact roles through TabManager:
$composition_manager_recovery"
fi

if (( status != 0 || guard_failures != 0 )); then
  exit 1
fi

echo "sidebar drop coordinator boundary passed"
