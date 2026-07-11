#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

ledger="Sumi/Models/Tab/TabConfigurationPolicyLedger.swift"
state="Sumi/Models/Tab/TabConfigurationPolicyState.swift"
tab_boundary="Sumi/Models/Tab/Tab+ConfigurationPolicy.swift"
transaction="Sumi/Models/Tab/TabConfigurationPolicyTransaction.swift"
placement_admission="Sumi/Models/Tab/TabConfigurationPolicyPlacementAdmission.swift"
replacement="Sumi/Models/Tab/TabWebViewReplacementService.swift"
provisioning="Sumi/Models/Tab/TabWebViewProvisioningOwner.swift"
ownership="Sumi/Managers/WebViewRuntime/WebViewOwnershipService.swift"
untracked_installation="Sumi/Managers/WebViewRuntime/UntrackedWebViewInstallationService.swift"
placement="Sumi/Managers/WebViewRuntime/CanonicalWebViewPlacementService.swift"
detached_replacement="Sumi/Managers/WebViewRuntime/DetachedWebViewReplacementService.swift"
detached_cleanup="Sumi/Managers/WebViewRuntime/DetachedWebViewCleanupService.swift"
pipeline="Sumi/Managers/WebViewRuntime/WebViewReplacementPipeline.swift"
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

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if [[ ! -f "$file" ]] || ! rg -q "$pattern" "$file"; then
    printf 'error: %s\n' "$message" >&2
    status=1
  fi
}

require_test() {
  local test_name="$1"
  if ! rg -q "func[[:space:]]+${test_name}\\b" SumiTests -g '*.swift'; then
    printf 'error: required configuration-policy regression missing: %s\n' \
      "$test_name" >&2
    status=1
  fi
}

enforce_max_lines() {
  local file="$1"
  local maximum="$2"
  local count
  count="$(wc -l < "$file" | tr -d ' ')"
  if (( count > maximum )); then
    printf 'error: configuration-policy boundary grew into a hub: %s (%s > %s lines)\n' \
      "$file" "$count" "$maximum" >&2
    status=1
  fi
}

for file in "${policy_files[@]}" "$provisioning" "$ownership" \
  "$placement" "$detached_replacement" "$detached_cleanup" "$pipeline"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: configuration-policy architecture file missing: %s\n' \
      "$file" >&2
    status=1
  fi
done

for retired_path in \
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

retired_hits="$(
  rg -n '\b(TabReloadPolicyStateOwner|TabReloadPolicyRuntime|TabConfigurationPolicyWebViewReplacementOwner|TabWebViewReplacementContextOwner|TabWebViewReplacementContext|previousProtectionState|previousSafariContentBlockerState|restoreReloadPolicy|recordProtectionAttachment|recordSafariContentBlockerAttachment|recordUnknownPhysicalGeneration|noteProtectionAttachmentApplied|noteSafariContentBlockerAttachmentApplied)\b' \
    Sumi SumiTests -g '*.swift' || true
)"
fail_matches "retired mutable/rollback policy surface reintroduced" \
  "$retired_hits"

legacy_placement_hits="$(
  rg -n '\b(canCommitConfigurationPolicy|commitConfigurationPolicy|prepareConfiguration)\b' \
    Sumi Packages/SumiWebRuntime -g '*.swift' || true
)"
fail_matches "legacy bool/hook placement escape hatch reintroduced" \
  "$legacy_placement_hits"

fatal_tracking_rejection_hits="$(
  rg -n 'case \.rejected.*preconditionFailure|registrationFailureMessage' \
    "$tracking_lifecycle" || true
)"
fail_matches "tracked placement rejection became a process-fatal control path" \
  "$fatal_tracking_rejection_hits"

optional_settlement_validation_hits="$(
  rg -n -U 'validateCommitLease:[\s\S]{0,120}\) -> Bool[[:space:]]*=' \
    "$settlement_contract" || true
)"
fail_matches "replacement commit validation became an optional safety hook" \
  "$optional_settlement_validation_hits"

raw_transaction_hits="$(
  rg -n 'func[[:space:]]+(canCommit|commit)\([[:space:]]*$' \
    "$transaction" || true
)"
fail_matches "configuration-policy transaction regained a raw WebView settlement bypass" \
  "$raw_transaction_hits"

root_lookup_hits="$(
  rg -n '\b(BrowserManager|TabManager)\b|\bbrowserManager\b' \
    "${policy_files[@]}" || true
)"
fail_matches "configuration-policy behavior depends on a browser root" \
  "$root_lookup_hits"

owner_wrapper_hits="$(
  rg -n '\b(class|struct|enum)[[:space:]]+[A-Za-z0-9_]*Owner\b|\bstruct[[:space:]]+Dependencies\b' \
    "${policy_files[@]}" || true
)"
fail_matches "configuration-policy behavior was hidden in an owner/dependency bag" \
  "$owner_wrapper_hits"

context_policy_bag_hits="$(
  rg -n '\blet[[:space:]]+(sessionGeneration|canCommitConfigurationPolicy|commitConfigurationPolicy|configurationPolicyLedger)\b' \
    Sumi/Models/Tab/TabNormalWebViewRuntimeContext.swift || true
)"
fail_matches "normal WebView context regained configuration-policy transaction state" \
  "$context_policy_bag_hits"

direct_registration_hits="$(
  rg -n '\.registerTrackedWebView\(' Sumi -g '*.swift' \
    | rg -v 'WebViewTrackedRegistrationOwner\.swift' || true
)"
fail_matches "normal WebView policy admission bypassed through generic registration" \
  "$direct_registration_hits"

require_pattern \
  "$provisioning" \
  'configuration\.websiteDataStore[[:space:]]*===[[:space:]]*profile\.dataStore' \
  "normal WebView provisioning must enforce exact profile data-store identity"
require_pattern \
  "$pipeline" \
  'configurationPolicyChangeSet\?\.belongs' \
  "replacement policy evidence must bind to the exact Tab ledger"
require_pattern \
  "$pipeline" \
  'configurationPolicyChangeSet\?\.profileID[[:space:]]*==[[:space:]]*profileID' \
  "replacement policy evidence must bind to the exact profile"
require_pattern \
  "$pipeline" \
  'configurationPolicyChangeSet\?\.canCommit' \
  "replacement policy evidence must match the exact physical WebViews"
require_pattern \
  "$pipeline" \
  'validateCommitLease:' \
  "asynchronous replacement settlement must revalidate policy evidence before repository commit"
require_pattern \
  "$pipeline" \
  'auxiliaryReplacementsHaveNoPolicyEvidence' \
  "auxiliary generations must reject hidden normal-policy evidence"
require_pattern \
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Transactions/WebViewReplacementSettlementService.swift" \
  'runtime\.validateCommitLease\(transaction\.lease\)' \
  "failed pre-commit evidence must enter typed repository rollback"
require_pattern \
  "Packages/SumiWebRuntime/Tests/SumiWebRuntimeTests/WebViewReplacementSettlementServiceTests.swift" \
  'testFailedCommitValidationRollsBackBeforeRepositoryCommit' \
  "settlement must regress validation failure before repository commit"
require_pattern \
  "$ownership" \
  'func[[:space:]]+registerAuxiliaryTrackedWebView' \
  "auxiliary tracked registration must be an explicit capability"
require_pattern \
  "$placement" \
  'func[[:space:]]+placeAuxiliaryTracked' \
  "auxiliary tracked placement must be an explicit capability"
require_pattern \
  "$placement" \
  'preparePlacementAdmission' \
  "normal canonical placement must carry explicit policy admission"
require_pattern \
  "$placement" \
  'didCommitPlacement:' \
  "tracked policy settlement must happen immediately after repository CAS"
require_pattern \
  "$placement" \
  'Tracked placement changed during registration side effects' \
  "tracked placement must revalidate exact identity after side effects"
require_pattern \
  "Packages/SumiWebRuntime/Tests/SumiWebRuntimeTests/WebViewSessionRepositoryTests.swift" \
  'testSlotRegistrationCommitsOnceBeforeLifecycleSideEffects' \
  "package registration must regress post-CAS/pre-side-effect ordering"
require_pattern \
  "$tracking_lifecycle" \
  'WebViewTrackedRegistrationResult' \
  "tracked registration must return typed non-mutating rejections"
require_pattern \
  "Packages/SumiWebRuntime/Tests/SumiWebRuntimeTests/WebViewSessionRepositoryTests.swift" \
  'testLifecycleRegistrationReturnsChangedPreflightWithoutSideEffects' \
  "changed tracked-registration preflight must reject without lifecycle effects"
require_pattern \
  "$ledger" \
  'Set\(webViews\.map\(ObjectIdentifier\.init\)\)' \
  "policy change sets must reject duplicate physical WebViews"
require_pattern \
  "$state" \
  'Runtime rule-list lookup and hot-swap results remain observable' \
  "configuration plan must not masquerade as actual rule-list diagnostics"
require_pattern \
  "$untracked_installation" \
  'final class UntrackedWebViewInstallationService: UntrackedWebViewInstalling' \
  "detached installation must remain an exact transaction service"

ownership_installation_hits="$(
  rg -n '\b(UntrackedWebViewInstalling|func[[:space:]]+installUntracked)\b' \
    "$ownership" || true
)"
fail_matches \
  "WebViewOwnershipService regained detached installation" \
  "$ownership_installation_hits"

enforce_max_lines "$ledger" 320
enforce_max_lines "$state" 90
enforce_max_lines "$tab_boundary" 120
enforce_max_lines "$transaction" 140
enforce_max_lines "$placement_admission" 140
enforce_max_lines "$replacement" 130
enforce_max_lines "$ownership" 330
enforce_max_lines "$untracked_installation" 130
enforce_max_lines "$placement" 330
enforce_max_lines "$detached_replacement" 140
enforce_max_lines "$detached_cleanup" 110
enforce_max_lines "Sumi/Models/Tab/ProtectionReloadState.swift" 220
enforce_max_lines "Sumi/Models/Tab/SafariContentBlockerReloadState.swift" 180
enforce_max_lines "Sumi/Models/Tab/AutoplayReloadState.swift" 140
enforce_max_lines "Sumi/Models/Tab/TabConfigurationPolicyRebuildService.swift" 140

ownership_collaborators="$(
  rg -c '^[[:space:]]+private let [A-Za-z0-9_]+' "$ownership" || true
)"
if (( ownership_collaborators > 7 )); then
  printf 'error: WebViewOwnershipService regained a god composition surface (%s > 7 collaborators)\n' \
    "$ownership_collaborators" >&2
  status=1
fi

for test_name in \
  testProvisionalWebViewDoesNotChangeCommittedPolicy \
  testStaleReceiptCannotOverwriteNewerCommittedPolicy \
  testPreparedWebViewCannotCommitThroughAnotherTabAtSameGeneration \
  testAdditionalCloneAcceptsSameEffectiveRulesAcrossHosts \
  testMixedClonePolicySetCancelsWithoutLedgerMutation \
  testNewerCloneSettlementMakesOlderCanonicalReceiptStale \
  testRawNormalCanonicalWebViewIsRejectedWithoutMutatingLedger \
  testCommittedReceiptCannotAuthorizeRawNormalSubset \
  testCancellingThroughAnotherTabPreservesForeignReceipt \
  testPlacementAdmissionRejectsNoPlacement \
  testPlacementAdmissionRejectsStalePolicy \
  testPlacementAdmissionRejectsWrongCanonicalWebView \
  testParkedNormalWebViewCannotBeReusedAfterAutoplayPolicyChanges \
  testNormalWebViewKeepsExactResolvedProfileDataStore \
  testCanonicalPlacementRejectsRawNormalWebViewBeforeRepositoryMutation \
  testCanonicalPlacementRejectsPolicyReceiptFromAnotherTab \
  testCanonicalPlacementReturnsProtectedCandidateWithoutMutation \
  testProtectedOccupantRejectsAndCancelsExactPolicyAdmission \
  testCanonicalAuxiliaryPlacementCancelsSameTabPolicyEvidence \
  testMaterializationCommitsAdditionalCloneThroughExactPlacement \
  testDetachedReplacementRejectsCancelledPolicyWithoutPlacement \
  testDetachedReplacementReportsConsumedAfterSynchronousPolicyRollback \
  testDetachedAuxiliaryReplacementRejectsForeignPolicyEvidence \
  testReplacementRejectsPolicyEvidenceFromDifferentWebView \
  testCancelledPolicyEvidenceIsRejectedBeforeReplacementAdmission \
  testPolicyReceiptSubstitutionDuringModelValidationCannotMutatePlacement \
  testPolicyCancellationDuringModelCommitRollsBackRepositoryAdmission \
  testPolicyCancellationWhileAwaitingBindingRollsBackBeforeCommit \
  testCommittedReplacementRetiresWholeGenerationBeforeDestroyingIt \
  testRolledBackReplacementDiscardsOnlyReplacementGeneration; do
  require_test "$test_name"
done

if (( status != 0 )); then
  exit "$status"
fi

echo "tab configuration policy architecture guard passed"
