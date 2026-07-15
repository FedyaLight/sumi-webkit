#!/usr/bin/env bash
# Tab closing must stay a role-exact transaction: TabClosureService orchestrates,
# candidate retirement / selection policy / runtime cleanup stay separate, and
# no TabRemovalOwner / Dependencies bag / TabManager retention returns.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

status=0

service='Sumi/Managers/TabManager/TabClosureService.swift'
composition='Sumi/Managers/TabManager/TabClosureService+Live.swift'
retirement='Sumi/Managers/TabManager/TabClosureCandidateRetirement.swift'
cleanup='Sumi/Managers/TabManager/RegularTabClosureRuntimeCleanup.swift'
policy='Sumi/Managers/TabManager/SelectionAfterClosurePolicy.swift'
runtime_connection='Sumi/BrowserRuntime/Ports/TabRuntimePortConnection.swift'
lifecycle_bag='Sumi/Managers/TabManager/TabLifecycleOwnerBag.swift'
accessors='Sumi/Managers/TabManager/TabManager+OwnerAccessors.swift'
for file in "$service" "$composition" "$retirement" "$cleanup" "$policy" \
  "$runtime_connection"; do
  guard_require_file "$file"
done

# Retired god surface must stay deleted.
if [[ -e Sumi/Managers/TabManager/TabRemovalOwner.swift ]]; then
  printf 'error: tombstone violated: TabRemovalOwner.swift must stay deleted\n' >&2
  status=1
fi

retired_hits="$(
  guard_capture_matches '\bTabRemovalOwner\b|\btabRemovalOwner\b' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests \
    scripts/check_architecture_guardrails.sh \
    scripts/check_extension_browser_bridge_architecture.sh \
    scripts/check_di_ceremony_debt.sh \
    scripts/check_modernization_debt.sh
)"
# Ignore this guard's own tombstone/alias checks when the first scan found any.
if [[ -n "$retired_hits" ]]; then
  retired_hits="$(
    printf '%s\n' "$retired_hits" \
      | guard_capture_matches 'scripts/check_tab_closure_service_boundary\.sh:' -v --no-line-number -
  )"
fi
if [[ -n "$retired_hits" ]]; then
  guard_record_failure "TabRemovalOwner / tabRemovalOwner reintroduced:
$retired_hits"
fi

# No Dependencies/Actions bags or generic capability bags in the slice.
closure_bag_hits="$(
  guard_capture_matches '\bstruct[[:space:]]+Dependencies\b|\bstruct[[:space:]]+Actions\b|\bstruct[[:space:]]+Context\b|\bstruct[[:space:]]+Environment\b|\bstruct[[:space:]]+Capabilities\b' \
    "$service" "$retirement" "$cleanup" "$policy"
)"
if [[ -n "$closure_bag_hits" ]]; then
  guard_record_failure "tab closure slice grew a Dependencies/Actions/Context/Environment/Capabilities bag:
$closure_bag_hits"
fi

# Services must not store or look up TabManager at runtime. Mentions are
# allowed only inside TabClosureService.live composition.
manager_storage_hits="$(
  guard_capture_matches '\bTabManager\b' "$service" "$retirement" "$cleanup" "$policy" \
    "$runtime_connection"
)"
if [[ -n "$manager_storage_hits" ]]; then
  guard_record_failure "tab closure collaborators mention TabManager:
$manager_storage_hits"
fi

stored_manager_hits="$(
  guard_capture_matches 'private[[:space:]].*\bTabManager\b|unowned[[:space:]].*\bTabManager\b|weak[[:space:]].*\bTabManager\b' \
    "$service" "$retirement" "$cleanup" "$policy"
)"
if [[ -n "$stored_manager_hits" ]]; then
  guard_record_failure "tab closure services retain TabManager storage:
$stored_manager_hits"
fi

runtime_reachthrough_hits="$(
  guard_capture_matches '\[weak[[:space:]]+tabManager\]|requireRuntimePorts|->[[:space:]]*RuntimePortRegistry' \
    "$service" "$composition" "$retirement" "$cleanup" "$policy"
)"
if [[ -n "$runtime_reachthrough_hits" ]]; then
  guard_record_failure "tab closure slice regained runtime TabManager reach-through/provider closure:
$runtime_reachthrough_hits"
fi

runtime_lease_count="$(guard_count_matches 'runtimePorts\.requireLease\(\)' "$service")"
if (( runtime_lease_count == 0 )); then
  printf 'error: TabClosureService must acquire one explicit runtime lease\n' >&2
  status=1
fi
if (( ${runtime_lease_count:-0} != 1 )); then
  printf 'error: TabClosureService must acquire exactly one runtime lease (%s != 1)\n' \
    "${runtime_lease_count:-0}" >&2
  status=1
fi

# Composition must resolve collaborators once; no forwarding alias.
guard_require_file "$lifecycle_bag"
guard_require_file "$accessors"
required_contracts=(
  "$lifecycle_bag|lazy var[[:space:]]+tabClosureService[[:space:]]*=[[:space:]]*TabClosureService\\.live\\(tabManager:[[:space:]]*tm\\)|TabLifecycleOwnerBag must compose TabClosureService.live at bag construction"
  "$accessors|var[[:space:]]+tabClosureService:[[:space:]]*TabClosureService|TabManager must expose tabClosureService"
)
for contract in "${required_contracts[@]}"; do
  file="${contract%%|*}"
  remainder="${contract#*|}"
  pattern="${remainder%%|*}"
  message="${remainder#*|}"
  contract_count="$(guard_count_matches "$pattern" "$file")"
  if (( contract_count == 0 )); then
    guard_record_failure "$message"
  fi
done
alias_count="$(guard_count_matches 'tabRemovalOwner' "$accessors" "$lifecycle_bag")"
if (( alias_count > 0 )); then
  printf 'error: forwarding compatibility alias tabRemovalOwner remains\n' >&2
  status=1
fi

# Focused surface size caps keep the orchestrator from becoming another god.
service_lines="$(guard_count_lines "$service")"
service_collaborators="$(
  guard_count_matches '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' "$service"
)"
retirement_lines="$(guard_count_lines "$retirement")"
cleanup_lines="$(guard_count_lines "$cleanup")"
policy_lines="$(guard_count_lines "$policy")"

if (( service_lines > 220 )); then
  printf 'error: TabClosureService exceeded focused LOC cap (%s > 220)\n' \
    "$service_lines" >&2
  status=1
fi
if (( ${service_collaborators:-0} > 9 )); then
  printf 'error: TabClosureService became a collaboration hub (%s > 9)\n' \
    "${service_collaborators:-0}" >&2
  status=1
fi
if (( retirement_lines > 120 )); then
  printf 'error: TabClosureCandidateRetirement exceeded focused LOC cap (%s > 120)\n' \
    "$retirement_lines" >&2
  status=1
fi
if (( cleanup_lines > 80 )); then
  printf 'error: RegularTabClosureRuntimeCleanup exceeded focused LOC cap (%s > 80)\n' \
    "$cleanup_lines" >&2
  status=1
fi
if (( policy_lines > 90 )); then
  printf 'error: SelectionAfterClosurePolicy exceeded focused LOC cap (%s > 90)\n' \
    "$policy_lines" >&2
  status=1
fi

if (( status != 0 || guard_failures != 0 )); then
  exit 1
fi

echo "tab closure service boundary passed"
