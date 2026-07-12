#!/usr/bin/env bash
# Sidebar drop commit must not reach BrowserManager/TabManager through
# SidebarDropCoordinator. Source projection lives in SidebarDragSourceInventory;
# mutation stays on SidebarDragOperationExecuting / the existing router.
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

coordinator='Sumi/Components/DragDrop/SidebarDropCoordinator.swift'
inventory='Sumi/Components/DragDrop/SidebarDragSourceInventory.swift'
executing='Sumi/Components/DragDrop/SidebarDragOperationExecuting.swift'
projection='Sumi/Components/DragDrop/SidebarDropProjection.swift'
context='Sumi/Components/Sidebar/SidebarBrowserContext.swift'
router='Sumi/Managers/TabManager/SidebarDragOperationRouter.swift'
inventory_tests='SumiTests/SidebarDragSourceInventoryTests.swift'
coordinator_tests='SumiTests/SidebarDropCoordinatorBoundaryTests.swift'

for file in "$coordinator" "$inventory" "$executing" "$projection" \
  "$inventory_tests" "$coordinator_tests"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: sidebar drop boundary file missing: %s\n' "$file" >&2
    status=1
  fi
done
if (( status != 0 )); then
  exit "$status"
fi

# Coordinator must not accept or mention manager roots.
coordinator_manager_hits="$(
  rg -n '\bBrowserManager\b|\bTabManager\b' "$coordinator" || true
)"
fail_matches \
  "SidebarDropCoordinator regained BrowserManager/TabManager reach-through" \
  "$coordinator_manager_hits"

# Read inventory must not hold manager roots or DI bags.
inventory_manager_hits="$(
  rg -n '\bBrowserManager\b|\bTabManager\b' "$inventory" || true
)"
fail_matches \
  "SidebarDragSourceInventory contains manager-root" \
  "$inventory_manager_hits"

closure_bag_hits="$(
  rg -n '\bstruct[[:space:]]+Dependencies\b|\bstruct[[:space:]]+Actions\b' \
    "$coordinator" "$inventory" "$executing" "$projection" || true
)"
fail_matches \
  "sidebar drop boundary grew a Dependencies/Actions closure bag" \
  "$closure_bag_hits"

# Coordinator must not take raw structure owners back as collaborators.
owner_reach_hits="$(
  rg -n 'ShortcutPinCollectionStateOwner|SplitGroupSidebarOrderingService|RegularTabCollectionOwner|TabFolderCollectionStateOwner|SpacePinnedStructureOwner' \
    "$coordinator" || true
)"
fail_matches \
  "SidebarDropCoordinator received direct owner reach-through" \
  "$owner_reach_hits"

# Coordinator must compose through the narrow inventory + operation seams.
require_pattern() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! rg -q "$pattern" "$file"; then
    printf 'error: %s\n' "$message" >&2
    status=1
  fi
}

require_pattern \
  "$coordinator" \
  'sourceInventory:[[:space:]]*any[[:space:]]+SidebarDragSourceInventorying' \
  "SidebarDropCoordinator lost SidebarDragSourceInventorying collaborator"
require_pattern \
  "$coordinator" \
  'dragOperations:[[:space:]]*any[[:space:]]+SidebarDragOperationExecuting' \
  "SidebarDropCoordinator lost SidebarDragOperationExecuting collaborator"
require_pattern \
  "$executing" \
  'protocol[[:space:]]+SidebarDragOperationExecuting' \
  "SidebarDragOperationExecuting protocol missing"
require_pattern \
  "$executing" \
  'extension[[:space:]]+SidebarDragOperationRouter:[[:space:]]*SidebarDragOperationExecuting' \
  "SidebarDragOperationRouter must remain the live operation authority"
require_pattern \
  "$context" \
  'SidebarDragSourceInventory\(' \
  "SidebarBrowserContext.live must compose SidebarDragSourceInventory"
require_pattern \
  "$context" \
  'let[[:space:]]+dragOperations[[:space:]]*=[[:space:]]*tabManager\.sidebarDragRouter' \
  "SidebarBrowserContext.live must resolve sidebarDragRouter at composition time"
require_pattern \
  "$context" \
  'dragOperations:[[:space:]]*dragOperations' \
  "SidebarBrowserContext.live must pass its composed operation authority"
runtime_router_reach="$(
  awk '
    /performDrop:[[:space:]]*\{/ { in_drop = 1 }
    in_drop { print }
    in_drop && /^[[:space:]]*\},?$/ { exit }
  ' "$context" | rg -n 'tabManager\.' || true
)"
fail_matches \
  "sidebar drop resolves TabManager collaborators during the operation" \
  "$runtime_router_reach"

# Focused surface size caps keep the inventory from becoming a god-object.
line_count() {
  wc -l < "$1" | tr -d ' '
}

collaborator_count() {
  rg -c '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' "$1" || true
}

inventory_lines="$(line_count "$inventory")"
inventory_collaborators="$(collaborator_count "$inventory")"
coordinator_lines="$(line_count "$coordinator")"
executing_lines="$(line_count "$executing")"

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

# Existing router Dependencies bag must not grow as the escape hatch.
router_dependency_lets="$(
  awk '
    /struct Dependencies \{/ { in_deps = 1; next }
    in_deps && /^[[:space:]]*\}/ { in_deps = 0 }
    in_deps && /^[[:space:]]*let[[:space:]]+/ { count++ }
    END { print count + 0 }
  ' "$router"
)"
if (( router_dependency_lets > 17 )); then
  printf 'error: SidebarDragOperationRouter.Dependencies grew (%s > 17 lets)\n' \
    "$router_dependency_lets" >&2
  status=1
fi

# Required focused regressions must stay present.
required_tests=(
  testEssentialsSourceIndexAndItemCount
  testSpacePinnedSourceProjection
  testRegularTabSourceProjection
  testFolderChildSourceProjection
  testShortcutSplitFolderIdentityMatching
  testRetainedInventoryDoesNotRetainTabManager
  testSameContainerReorderAdjustsIndexAfterSourceRemoval
  testCrossContainerDropSkipsSameContainerAdjustment
  testInvalidOrStaleScopeDoesNotMutate
  testURLDropDoesNotDependOnDragInventory
  testLiveCoordinatorCompositionExecutesWithoutBrowserManagerReachThrough
)

for test_name in "${required_tests[@]}"; do
  if ! rg -q "func[[:space:]]+${test_name}\\b" \
    "$inventory_tests" "$coordinator_tests"; then
    printf 'error: required sidebar drop regression missing: %s\n' "$test_name" >&2
    status=1
  fi
done
if ! rg -A 45 'func testLiveCoordinatorCompositionExecutesWithoutBrowserManagerReachThrough' \
  "$coordinator_tests" | rg -q 'SidebarBrowserContext\.live'; then
  printf 'error: live sidebar-drop composition regression uses only stubs\n' >&2
  status=1
fi

if (( status != 0 )); then
  exit "$status"
fi

echo "sidebar drop coordinator boundary passed"
