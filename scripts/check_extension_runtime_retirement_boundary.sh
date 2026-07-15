#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

reject_production_pattern() {
  local message="$1"
  local pattern="$2"
  shift 2
  local matches
  matches="$(guard_capture_matches "$pattern" "$@")" || return
  if [[ -n "$matches" ]]; then
    printf '%s\nerror: %s\n' "$matches" "$message" >&2
    return 1
  fi
}

require_production_pattern() {
  local message="$1"
  local pattern="$2"
  shift 2
  local count
  count="$(guard_count_matches "$pattern" "$@")" || return
  if (( count == 0 )); then
    printf 'error: %s\n' "$message" >&2
    return 1
  fi
}

required_files=(
  Sumi/Managers/ExtensionManager/ExtensionRuntimeMutationRegistry.swift
  Sumi/Managers/ExtensionManager/ExtensionBackgroundRuntimeStateOwner.swift
  Sumi/Managers/ExtensionManager/ExtensionContextErrorObservation.swift
  Sumi/Managers/ExtensionManager/ExtensionContextLoadRegistry.swift
  Sumi/Managers/ExtensionManager/ExtensionContextRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionLoadedContextAuthority.swift
  Sumi/Managers/ExtensionManager/ExtensionLoadedContextFinalizer.swift
  Sumi/Managers/ExtensionManager/ExtensionEnabledRuntimeActivation.swift
  Sumi/Managers/ExtensionManager/ExtensionInstallationRuntimeActivation.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRecovery.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRollback.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeLoader.swift
  Sumi/Managers/ExtensionManager/ExtensionScopedRuntimeRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeActivityCancellation.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeBookkeepingReset.swift
  Sumi/Managers/ExtensionManager/ExtensionControllerRuntimeRelease.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeShutdown.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeTabRebuildPlan.swift
)

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || {
    printf 'error: extension runtime retirement boundary missing: %s\n' "$file" >&2
    exit 1
  }
done

for retired in \
  Sumi/Managers/ExtensionManager/ExtensionRuntimeStateResetOwner.swift \
  Sumi/Managers/ExtensionManager/ExtensionRuntimeTeardownOwner.swift \
  Sumi/Managers/ExtensionManager/ExtensionErrorObservationOwner.swift; do
  [[ ! -e "$retired" && ! -L "$retired" ]] || {
    printf 'error: retired extension runtime god surface returned: %s\n' "$retired" >&2
    exit 1
  }
done

core_files=(
  Sumi/Managers/ExtensionManager/ExtensionContextErrorObservation.swift
  Sumi/Managers/ExtensionManager/ExtensionContextLoadRegistry.swift
  Sumi/Managers/ExtensionManager/ExtensionContextRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionLoadedContextAuthority.swift
  Sumi/Managers/ExtensionManager/ExtensionLoadedContextFinalizer.swift
  Sumi/Managers/ExtensionManager/ExtensionEnabledRuntimeActivation.swift
  Sumi/Managers/ExtensionManager/ExtensionInstallationRuntimeActivation.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRecovery.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRollback.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeLoader.swift
  Sumi/Managers/ExtensionManager/ExtensionScopedRuntimeRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeActivityCancellation.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeBookkeepingReset.swift
  Sumi/Managers/ExtensionManager/ExtensionControllerRuntimeRelease.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeMutationRegistry.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeShutdown.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeTabRebuildPlan.swift
  Sumi/Managers/ExtensionManager/ExtensionBackgroundRuntimeStateOwner.swift
)

reject_production_pattern \
  'extension retirement core regained a manager-root or closure bag' \
  'struct (Dependencies|Actions)|\bmanager:[[:space:]]*ExtensionManager\b|init\(manager:' \
  "${core_files[@]}"
reject_production_pattern \
  'retired boolean/reset runtime API returned' \
  'tearDownExtensionRuntime\(|resetRuntimeState\(|removeUIState:|releaseController:' \
  Sumi

for required_symbol in \
  'func beginTerminal() -> ExtensionRuntimeTerminalLease?' \
  'func beginTerminalIfNoScopedMutations()' \
  'func enterIrreversiblePhase(' \
  'func runWhenTerminalAdmissionAvailable(' \
  'func admitsExtensionGlobalRollback(' \
  'func hasCompetingClaim(' \
  'func admitsLoad(' \
  'func hasCompetingScopedMutation(' \
  'case mutation(ExtensionRuntimeMutationLease)' \
  'case terminal(ExtensionRuntimeTerminalLease)' \
  'case retirementInProgress' \
  'case mutationInProgress' \
  'case contextsRemaining' \
  'struct ExtensionRuntimeTransactionFailure' \
  'enum ExactRollbackDisposition' \
  'enum SharedCleanupDisposition' \
  'enum SharedCleanupBlocker' \
  'func cleanUpAfterQuiescentRollback(' \
  'func cancelWakePreservingRuntimeState(' \
  'let tabRebuildPlan: ExtensionRuntimeTabRebuildPlan'; do
  require_production_pattern \
    "extension retirement authority missing: $required_symbol" \
    "$required_symbol" "${required_files[@]}" -F
done

reject_production_pattern \
  'enabled runtime loader regained install/retirement/recovery god responsibilities' \
  'ExtensionRuntimeLoader\.Environment|retireRuntimeState\(|finalizeAlreadyLoadedRuntime\(|activateInstalledExtension\(|recoverEnabledRuntime\(' \
  Sumi/Managers/ExtensionManager/ExtensionRuntimeLoader.swift

shutdown_file='Sumi/Managers/ExtensionManager/ExtensionRuntimeShutdown.swift'
require_production_pattern \
  'exact terminal extension runtime shutdown API missing' \
  'func shutDown\([[:space:]]*reason: String,[[:space:]]*browserTabs: \[Tab\],[[:space:]]*liveWebViews: @MainActor \(Tab\) -> \[WKWebView\],[[:space:]]*activityResources: ExtensionRuntimeActivityCancellation\.Resources,[[:space:]]*admission: Admission = \.forced[[:space:]]*\) -> Result' \
  "$shutdown_file" -U
reject_production_pattern \
  'terminal extension runtime shutdown regained a synthetic support flag' \
  'func shutDown\([^)]*isExtensionSupportAvailable:' \
  "$shutdown_file" -U

installation_publish_body="$(
  sed -n \
    '/private func publish(_ record: InstalledExtension)/,/^    }/p' \
    Sumi/Managers/ExtensionManager/ExtensionInstallationService.swift
)"
lifecycle_publish_body="$(
  sed -n \
    '/private func publish(/,/^    }/p' \
    Sumi/Managers/ExtensionManager/InstalledExtensionLifecycleService.swift
)"
publication_yield_hits="$(
  guard_capture_matches 'Task\.yield\(\)' - \
    <<<"${installation_publish_body}"$'\n'"${lifecycle_publish_body}"
)"
if [[ -n "$publication_yield_hits" ]]; then
  printf 'error: extension lifecycle catalog publication regained a yielded lost-update window\n' >&2
  exit 1
fi

deferred_shutdown_body="$(
  sed -n \
    '/private func scheduleRuntimeTeardownRetry(/,/^    }/p' \
    Sumi/Managers/ExtensionManager/SumiExtensionManagerLifetime.swift
)"
deferred_polling_hits="$(
  guard_capture_matches 'Timer|asyncAfter|Task\.sleep' - \
    <<<"$deferred_shutdown_body"
)"
if [[ -n "$deferred_polling_hits" ]]; then
  printf 'error: deferred extension shutdown regained polling or timers\n' >&2
  exit 1
fi

echo 'extension runtime retirement boundary passed'
