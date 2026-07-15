#!/usr/bin/env bash
# Tab closing must stay a role-exact transaction: TabClosureService orchestrates,
# candidate retirement / selection policy / runtime cleanup stay separate, and
# no TabRemovalOwner / Dependencies bag / TabManager retention returns.
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
  if [[ ! -f "$file" ]]; then
    printf 'error: tab closure boundary file missing: %s\n' "$file" >&2
    status=1
  fi
done
if (( status != 0 )); then
  exit "$status"
fi

# Retired god surface must stay deleted.
if [[ -e Sumi/Managers/TabManager/TabRemovalOwner.swift ]]; then
  printf 'error: tombstone violated: TabRemovalOwner.swift must stay deleted\n' >&2
  status=1
fi

retired_hits="$(
  rg -n '\bTabRemovalOwner\b|\btabRemovalOwner\b' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests \
    scripts/check_architecture_guardrails.sh \
    scripts/check_extension_browser_bridge_architecture.sh \
    scripts/check_di_ceremony_debt.sh \
    scripts/check_modernization_debt.sh \
    scripts/check_architecture_hub_metrics.sh \
    || true
)"
# Ignore this guard's own tombstone/alias checks.
retired_hits="$(
  printf '%s\n' "$retired_hits" \
    | rg -v 'scripts/check_tab_closure_service_boundary\.sh:' \
    || true
)"
fail_matches \
  "TabRemovalOwner / tabRemovalOwner reintroduced" \
  "$retired_hits"

# No Dependencies/Actions bags or generic capability bags in the slice.
closure_bag_hits="$(
  rg -n '\bstruct[[:space:]]+Dependencies\b|\bstruct[[:space:]]+Actions\b|\bstruct[[:space:]]+Context\b|\bstruct[[:space:]]+Environment\b|\bstruct[[:space:]]+Capabilities\b' \
    "$service" "$retirement" "$cleanup" "$policy" || true
)"
fail_matches \
  "tab closure slice grew a Dependencies/Actions/Context/Environment/Capabilities bag" \
  "$closure_bag_hits"

# Services must not store or look up TabManager at runtime. Mentions are
# allowed only inside TabClosureService.live composition.
manager_storage_hits="$(
  rg -n '\bTabManager\b' "$service" "$retirement" "$cleanup" "$policy" \
    "$runtime_connection" || true
)"
fail_matches \
  "tab closure collaborators mention TabManager" \
  "$manager_storage_hits"

stored_manager_hits="$(
  rg -n 'private[[:space:]].*\bTabManager\b|unowned[[:space:]].*\bTabManager\b|weak[[:space:]].*\bTabManager\b' \
    "$service" "$retirement" "$cleanup" "$policy" || true
)"
fail_matches \
  "tab closure services retain TabManager storage" \
  "$stored_manager_hits"

runtime_reachthrough_hits="$(
  rg -n '\[weak[[:space:]]+tabManager\]|requireRuntimePorts|->[[:space:]]*RuntimePortRegistry' \
    "$service" "$composition" "$retirement" "$cleanup" "$policy" || true
)"
fail_matches \
  "tab closure slice regained runtime TabManager reach-through/provider closure" \
  "$runtime_reachthrough_hits"

if ! rg -q 'let runtime = runtimePorts\.requireLease\(\)' "$service"; then
  printf 'error: TabClosureService must acquire one explicit runtime lease\n' >&2
  status=1
fi
runtime_lease_count="$(rg -c 'runtimePorts\.requireLease\(\)' "$service" || true)"
if (( ${runtime_lease_count:-0} != 1 )); then
  printf 'error: TabClosureService must acquire exactly one runtime lease (%s != 1)\n' \
    "${runtime_lease_count:-0}" >&2
  status=1
fi

# Composition must resolve collaborators once; no forwarding alias.
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
  "$lifecycle_bag" \
  'lazy var[[:space:]]+tabClosureService[[:space:]]*=[[:space:]]*TabClosureService\.live\(tabManager:[[:space:]]*tm\)' \
  "TabLifecycleOwnerBag must compose TabClosureService.live at bag construction"
require_pattern \
  "$accessors" \
  'var[[:space:]]+tabClosureService:[[:space:]]*TabClosureService' \
  "TabManager must expose tabClosureService"
if rg -q 'tabRemovalOwner' "$accessors" "$lifecycle_bag"; then
  printf 'error: forwarding compatibility alias tabRemovalOwner remains\n' >&2
  status=1
fi

# Focused surface size caps keep the orchestrator from becoming another god.
line_count() {
  wc -l < "$1" | tr -d ' '
}

collaborator_count() {
  rg -c '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' "$1" || true
}

service_lines="$(line_count "$service")"
service_collaborators="$(collaborator_count "$service")"
retirement_lines="$(line_count "$retirement")"
cleanup_lines="$(line_count "$cleanup")"
policy_lines="$(line_count "$policy")"

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

if (( status != 0 )); then
  exit "$status"
fi

echo "tab closure service boundary passed"
