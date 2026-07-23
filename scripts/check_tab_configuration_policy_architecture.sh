#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

ledger="Sumi/Models/Tab/TabConfigurationPolicyLedger.swift"
state="Sumi/Models/Tab/TabConfigurationPolicyState.swift"
tab_boundary="Sumi/Models/Tab/Tab+ConfigurationPolicy.swift"
transaction="Sumi/Models/Tab/TabConfigurationPolicyTransaction.swift"
placement_admission="Sumi/Models/Tab/TabConfigurationPolicyPlacementAdmission.swift"
replacement="Sumi/Models/Tab/TabWebViewReplacementService.swift"
provisioning="Sumi/Models/Tab/TabWebViewProvisioningOwner.swift"
retired_ownership="Sumi/Managers/WebViewRuntime/WebViewOwnershipService.swift"
tracked_admission="Sumi/Managers/WebViewRuntime/TrackedWebViewAdmissionService.swift"
untracked_materialization="Sumi/Managers/WebViewRuntime/UntrackedWebViewMaterializationService.swift"
extension_replacement="Sumi/Managers/WebViewRuntime/ExtensionTabWebViewReplacementService.swift"
untracked_installation="Sumi/Managers/WebViewRuntime/UntrackedWebViewInstallationService.swift"
placement="Sumi/Managers/WebViewRuntime/CanonicalWebViewPlacementService.swift"
detached_replacement="Sumi/Managers/WebViewRuntime/DetachedWebViewReplacementService.swift"
detached_cleanup="Sumi/Managers/WebViewRuntime/DetachedWebViewCleanupService.swift"
pipeline="Sumi/Managers/WebViewRuntime/WebViewReplacementPipeline.swift"
website_data_cleanup="Sumi/Managers/WebViewRuntime/WebsiteDataCleanupService.swift"
website_data_gate="Sumi/Managers/WebViewRuntime/WebsiteDataMutationGate.swift"
tracking_lifecycle="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Owners/WebViewTrackingLifecycleOwner.swift"
settlement_contract="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Transactions/WebViewReplacementSettlement.swift"
policy_files=(
  "$ledger"
  "$state"
  "$tab_boundary"
  "$transaction"
  "$placement_admission"
  "Sumi/Models/Tab/ProtectionReloadState.swift"
  "Sumi/Models/Tab/SafariContentBlockerReloadState.swift"
  "Sumi/Models/Tab/AutoplayReloadState.swift"
  "Sumi/Models/Tab/TabConfigurationPolicyRebuildService.swift"
  "Sumi/Models/Tab/TabReloadPolicyServices.swift"
  "$replacement"
)
status=0




enforce_max_lines() {
  local file="$1"
  local maximum="$2"
  local count
  count="$(guard_count_lines "$file")"
  if (( count > maximum )); then
    printf 'error: configuration-policy boundary grew into a hub: %s (%s > %s lines)\n' \
      "$file" "$count" "$maximum" >&2
    status=1
  fi
}

enforce_max_collaborators() {
  local file="$1"
  local maximum="$2"
  local count
  count="$(guard_count_matches '^[[:space:]]+private let [A-Za-z0-9_]+' "$file")"
  count="${count:-0}"
  if (( count > maximum )); then
    printf 'error: focused WebView transaction regained a god composition surface: %s (%s > %s collaborators)\n' \
      "$file" "$count" "$maximum" >&2
    status=1
  fi
}

for file in "${policy_files[@]}" "$provisioning" \
  "$tracked_admission" "$untracked_materialization" "$extension_replacement" \
  "$untracked_installation" "$placement" "$detached_replacement" \
  "$detached_cleanup" "$pipeline" "$website_data_cleanup" \
  "$website_data_gate"; do
  guard_require_file "$file"
done

for retired_path in \
  "$retired_ownership" \
  Sumi/Models/Tab/TabReloadPolicyStateOwner.swift \
  Sumi/Models/Tab/TabConfigurationPolicyWebViewReplacementOwner.swift \
  Sumi/Models/Tab/TabWebViewReplacementContext.swift \
  Sumi/Models/Tab/TabWebViewReplacementContextOwner.swift; do
  if [[ -e "$retired_path" ]]; then
    printf 'error: retired configuration-policy path reintroduced: %s\n' \
      "$retired_path" >&2
    status=1
  fi
done

retired_ownership_hits="$(
  guard_capture_matches '\bWebViewOwnershipService\b|\bownershipService\b' \
    App Sumi SidebarChrome CommandPalette Settings UI SumiTests \
    -g '*.swift'
)"
if [[ -n "$retired_ownership_hits" ]]; then
  guard_record_failure "retired WebView ownership facade/type/property reintroduced:
$retired_ownership_hits"
fi

retired_hits="$(
  guard_capture_matches '\b(TabReloadPolicyStateOwner|TabReloadPolicyRuntime|TabConfigurationPolicyWebViewReplacementOwner|TabWebViewReplacementContextOwner|TabWebViewReplacementContext|previousProtectionState|previousSafariContentBlockerState|restoreReloadPolicy|recordProtectionAttachment|recordSafariContentBlockerAttachment|recordUnknownPhysicalGeneration|noteProtectionAttachmentApplied|noteSafariContentBlockerAttachmentApplied)\b' \
    Sumi SumiTests -g '*.swift'
)"
if [[ -n "$retired_hits" ]]; then
  guard_record_failure "retired mutable/rollback policy surface reintroduced:
$retired_hits"
fi

legacy_placement_hits="$(
  guard_capture_matches '\b(canCommitConfigurationPolicy|commitConfigurationPolicy)\b' \
    Sumi Packages/SumiWebRuntime -g '*.swift'
)"
if [[ -n "$legacy_placement_hits" ]]; then
  guard_record_failure "legacy bool/hook placement escape hatch reintroduced:
$legacy_placement_hits"
fi

fatal_tracking_rejection_hits="$(
  guard_capture_matches 'case \.rejected.*preconditionFailure|registrationFailureMessage' \
    "$tracking_lifecycle"
)"
if [[ -n "$fatal_tracking_rejection_hits" ]]; then
  guard_record_failure "tracked placement rejection became a process-fatal control path:
$fatal_tracking_rejection_hits"
fi

optional_settlement_validation_hits="$(
  guard_capture_matches 'validateCommitLease:[\s\S]{0,120}\) -> Bool[[:space:]]*=' \
    -U "$settlement_contract"
)"
if [[ -n "$optional_settlement_validation_hits" ]]; then
  guard_record_failure "replacement commit validation became an optional safety hook:
$optional_settlement_validation_hits"
fi

raw_transaction_hits="$(
  guard_capture_matches 'func[[:space:]]+(canCommit|commit)\([[:space:]]*$' \
    "$transaction"
)"
if [[ -n "$raw_transaction_hits" ]]; then
  guard_record_failure "configuration-policy transaction regained a raw WebView settlement bypass:
$raw_transaction_hits"
fi

root_lookup_hits="$(
  guard_capture_matches '\b(BrowserManager|TabManager)\b|\bbrowserManager\b' \
    "${policy_files[@]}"
)"
if [[ -n "$root_lookup_hits" ]]; then
  guard_record_failure "configuration-policy behavior depends on a browser root:
$root_lookup_hits"
fi

owner_wrapper_hits="$(
  guard_capture_matches '\b(class|struct|enum)[[:space:]]+[A-Za-z0-9_]*Owner\b|\bstruct[[:space:]]+Dependencies\b' \
    "${policy_files[@]}"
)"
if [[ -n "$owner_wrapper_hits" ]]; then
  guard_record_failure "configuration-policy behavior was hidden in an owner/dependency bag:
$owner_wrapper_hits"
fi

setup_stage_policy_bag_hits="$(
  guard_capture_matches '\blet[[:space:]]+(sessionGeneration|canCommitConfigurationPolicy|commitConfigurationPolicy|configurationPolicyLedger)\b' \
    Sumi/Models/Tab/TabNormalWebViewSetupStages.swift
)"
if [[ -n "$setup_stage_policy_bag_hits" ]]; then
  guard_record_failure "normal WebView setup stage regained configuration-policy transaction state:
$setup_stage_policy_bag_hits"
fi

direct_registration_hits="$(
  guard_capture_matches '\.registerTrackedWebView\(' Sumi -g '*.swift' \
    | guard_capture_matches 'WebViewTrackedRegistrationOwner\.swift' -v --no-line-number -
)"
if [[ -n "$direct_registration_hits" ]]; then
  guard_record_failure "normal WebView policy admission bypassed through generic registration:
$direct_registration_hits"
fi

contract_count="$(guard_count_matches 'webViewConfiguration\.websiteDataStore[[:space:]]*===[[:space:]]*profile\.dataStore' "$provisioning")"
if (( contract_count == 0 )); then
  guard_record_failure "normal WebView provisioning must enforce exact profile data-store identity"
fi
contract_count="$(guard_count_matches 'configurationPolicyChangeSet\?\.belongs' "$pipeline")"
if (( contract_count == 0 )); then
  guard_record_failure "replacement policy evidence must bind to the exact Tab ledger"
fi
contract_count="$(guard_count_matches 'configurationPolicyChangeSet\?\.profileID[[:space:]]*==[[:space:]]*profileID' "$pipeline")"
if (( contract_count == 0 )); then
  guard_record_failure "replacement policy evidence must bind to the exact profile"
fi
contract_count="$(guard_count_matches 'configurationPolicyChangeSet\?\.canCommit' "$pipeline")"
if (( contract_count == 0 )); then
  guard_record_failure "replacement policy evidence must match the exact physical WebViews"
fi
contract_count="$(guard_count_matches 'validateCommitLease:' "$pipeline")"
if (( contract_count == 0 )); then
  guard_record_failure "asynchronous replacement settlement must revalidate policy evidence before repository commit"
fi
contract_count="$(guard_count_matches 'auxiliaryReplacementsHaveNoPolicyEvidence' "$pipeline")"
if (( contract_count == 0 )); then
  guard_record_failure "auxiliary generations must reject hidden normal-policy evidence"
fi
contract_count="$(guard_count_matches 'runtime\.validateCommitLease\(transaction\.lease\)' "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Transactions/WebViewReplacementSettlementService.swift")"
if (( contract_count == 0 )); then
  guard_record_failure "failed pre-commit evidence must enter typed repository rollback"
fi
contract_count="$(guard_count_matches 'final class TrackedWebViewAdmissionService: AuxiliaryTrackedWebViewPlacing' "$tracked_admission")"
if (( contract_count == 0 )); then
  guard_record_failure "tracked WebView admission must remain a focused explicit capability"
fi
contract_count="$(guard_count_matches 'func[[:space:]]+registerAuxiliaryTrackedWebView' "$tracked_admission")"
if (( contract_count == 0 )); then
  guard_record_failure "auxiliary tracked registration must be an explicit capability"
fi
contract_count="$(guard_count_matches 'final class UntrackedWebViewMaterializationService' "$untracked_materialization")"
if (( contract_count == 0 )); then
  guard_record_failure "detached WebView materialization must remain a focused service"
fi
contract_count="$(guard_count_matches 'final class ExtensionTabWebViewReplacementService' "$extension_replacement")"
if (( contract_count == 0 )); then
  guard_record_failure "extension-visible WebView replacement must remain a focused transaction"
fi
contract_count="$(guard_count_matches 'func[[:space:]]+placeAuxiliaryTracked' "$placement")"
if (( contract_count == 0 )); then
  guard_record_failure "auxiliary tracked placement must be an explicit capability"
fi
contract_count="$(guard_count_matches 'preparePlacementAdmission' "$placement")"
if (( contract_count == 0 )); then
  guard_record_failure "normal canonical placement must carry explicit policy admission"
fi
contract_count="$(guard_count_matches 'didCommitPlacement:' "$placement")"
if (( contract_count == 0 )); then
  guard_record_failure "tracked policy settlement must happen immediately after repository CAS"
fi
contract_count="$(guard_count_matches 'Tracked placement changed during registration side effects' "$placement")"
if (( contract_count == 0 )); then
  guard_record_failure "tracked placement must revalidate exact identity after side effects"
fi
contract_count="$(guard_count_matches 'WebViewTrackedRegistrationResult' "$tracking_lifecycle")"
if (( contract_count == 0 )); then
  guard_record_failure "tracked registration must return typed non-mutating rejections"
fi
contract_count="$(guard_count_matches 'Set\(webViews\.map\(ObjectIdentifier\.init\)\)' "$ledger")"
if (( contract_count == 0 )); then
  guard_record_failure "policy change sets must reject duplicate physical WebViews"
fi
contract_count="$(guard_count_matches 'Runtime rule-list lookup and hot-swap results remain observable' "$state")"
if (( contract_count == 0 )); then
  guard_record_failure "configuration plan must not masquerade as actual rule-list diagnostics"
fi
contract_count="$(guard_count_matches 'final class UntrackedWebViewInstallationService: UntrackedWebViewInstalling' "$untracked_installation")"
if (( contract_count == 0 )); then
  guard_record_failure "detached installation must remain an exact transaction service"
fi

focused_web_view_services=(
  "$tracked_admission"
  "$untracked_materialization"
  "$extension_replacement"
)
focused_service_escape_hits="$(
  guard_capture_matches '\b(Dependencies|Runtime|Actions|BrowserManager|TabManager|WebViewRuntimeGraph)\b|\.webViewRuntime\b' \
    "${focused_web_view_services[@]}"
)"
if [[ -n "$focused_service_escape_hits" ]]; then
  guard_record_failure "focused WebView transaction regained a dependency bag or composition-root reach-through:
$focused_service_escape_hits"
fi

direct_bound_tab_hits="$(
  guard_capture_matches '\.boundTab\(' App Sumi -g '*.swift' \
    | guard_capture_matches 'WebViewRuntimeTabRegistry\.swift' -v --no-line-number -
)"
if [[ -n "$direct_bound_tab_hits" ]]; then
  guard_record_failure "runtime Tab identity validation bypassed through the weak index:
$direct_bound_tab_hits"
fi

optional_assignment_replay_hits="$(
  guard_capture_matches 'replaySemanticOperation:[^\n]*\([^\n]*\)[^\n]*=' \
    -U "$tracked_admission"
)"
if [[ -n "$optional_assignment_replay_hits" ]]; then
  guard_record_failure "tracked replacement semantic replay became optional:
$optional_assignment_replay_hits"
fi

contract_count="$(guard_count_matches 'func[[:space:]]+removeAllWebViews[\s\S]{0,300}guard runtimeTabs\.bind\(tab\)\.isAccepted' -U "Sumi/Managers/WebViewRuntime/WebViewLifecycleService.swift")"
if (( contract_count == 0 )); then
  guard_record_failure "whole-Tab teardown must validate exact runtime Tab identity before mutation"
fi
contract_count="$(guard_count_matches 'case \.retirement:[\s\S]{0,160}runtimeTabs\.beginRetirement\(tab\)[\s\S]{0,700}runtimeTabs\.finishRetirementIfDrained\(tab\.id\)' -U "Sumi/Managers/WebViewRuntime/WebViewLifecycleService.swift")"
if (( contract_count == 0 )); then
  guard_record_failure "terminal teardown must tombstone the physical Tab before cleanup and finish exact retirement"
fi
contract_count="$(guard_count_matches 'func[[:space:]]+suspendWebViews[\s\S]{0,180}guard runtimeTabs\.bind\(tab\)\.isAccepted' -U "Sumi/Managers/WebViewRuntime/WebViewLifecycleService.swift")"
if (( contract_count == 0 )); then
  guard_record_failure "Tab suspension must validate exact runtime Tab identity before mutation"
fi
contract_count="$(guard_count_matches 'removeAllWebViews[\s\S]{0,220}intent:[[:space:]]*\.retirement' -U "Sumi/Managers/BrowserManager/BrowserTabManagerWebViewLifecycleFactory.swift")"
if (( contract_count == 0 )); then
  guard_record_failure "destructive TabManager cleanup must enter the retirement lifecycle"
fi

contract_count="$(guard_count_matches 'case trackedRegistration\(tabID: UUID, windowID: UUID\)' "$website_data_gate")"
if (( contract_count == 0 )); then
  guard_record_failure "tracked registration deferral must retain its own admission key"
fi
contract_count="$(guard_count_matches 'case trackedReplacement\(tabID: UUID, windowID: UUID\)' "$website_data_gate")"
if (( contract_count == 0 )); then
  guard_record_failure "tracked replacement deferral must retain its own admission key"
fi
contract_count="$(guard_count_matches 'case untrackedReplacement\(tabID: UUID\)' "$website_data_gate")"
if (( contract_count == 0 )); then
  guard_record_failure "detached replacement deferral must retain its own admission key"
fi
contract_count="$(guard_count_matches 'func[[:space:]]+deferTrackedWebViewAdmission[\s\S]{0,900}key:[[:space:]]*\.trackedRegistration' -U "$website_data_cleanup")"
if (( contract_count == 0 )); then
  guard_record_failure "tracked admission must defer under the trackedRegistration key"
fi
contract_count="$(guard_count_matches 'func[[:space:]]+deferTrackedWebViewReplacement[\s\S]{0,900}key:[[:space:]]*\.trackedReplacement' -U "$website_data_cleanup")"
if (( contract_count == 0 )); then
  guard_record_failure "tracked replacement must defer under the trackedReplacement key"
fi
contract_count="$(guard_count_matches 'func[[:space:]]+deferUntrackedWebViewReplacement[\s\S]{0,700}key:[[:space:]]*\.untrackedReplacement' -U "$website_data_cleanup")"
if (( contract_count == 0 )); then
  guard_record_failure "detached replacement must defer under the untrackedReplacement key"
fi
contract_count="$(guard_count_matches 'runtimeTabs\.resetForTerminalShutdown\(\)' "Sumi/Managers/WebViewRuntime/WebViewLifecycleService.swift")"
if (( contract_count == 0 )); then
  guard_record_failure "terminal lifecycle must close Tab identity admission before repository drain"
fi
contract_count="$(guard_count_matches 'rejectedAfterTerminalShutdown' "$website_data_gate")"
if (( contract_count == 0 )); then
  guard_record_failure "terminal website-data admission must reject rather than silently reopen"
fi

enforce_max_lines "$ledger" 320
enforce_max_lines "$state" 90
enforce_max_lines "$tab_boundary" 120
enforce_max_lines "$transaction" 140
enforce_max_lines "$placement_admission" 140
enforce_max_lines "$replacement" 130
enforce_max_lines "$tracked_admission" 170
enforce_max_lines "$untracked_materialization" 90
enforce_max_lines "$extension_replacement" 240
enforce_max_lines "$untracked_installation" 130
enforce_max_lines "$placement" 330
enforce_max_lines "$detached_replacement" 140
enforce_max_lines "$detached_cleanup" 110
enforce_max_lines "Sumi/Models/Tab/ProtectionReloadState.swift" 220
enforce_max_lines "Sumi/Models/Tab/SafariContentBlockerReloadState.swift" 180
enforce_max_lines "Sumi/Models/Tab/AutoplayReloadState.swift" 140
enforce_max_lines "Sumi/Models/Tab/TabConfigurationPolicyRebuildService.swift" 140

enforce_max_collaborators "$tracked_admission" 5
enforce_max_collaborators "$untracked_materialization" 3
# Five exact authorities are intentional: Tab identity, residence query,
# website-data admission, tracked placement, and detached installation.
enforce_max_collaborators "$extension_replacement" 5

if (( status != 0 || guard_failures != 0 )); then
  exit 1
fi

echo "tab configuration policy architecture guard passed"
