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

composition='Sumi/Managers/BrowserManager/BrowserExtensionBridgeComposition.swift'
runtime_publication_composition='Sumi/Managers/ExtensionManager/ExtensionManager+RuntimePublicationComposition.swift'
runtime_publication='Sumi/Managers/ExtensionManager/ExtensionManager+RuntimePublication.swift'
auxiliary_publication='Sumi/Managers/ExtensionManager/ExtensionManager+AuxiliaryWindowPublication.swift'
runtime_publication_gate='Sumi/Managers/ExtensionManager/ExtensionRuntimePublicationGate.swift'
runtime_publication_reconciler='Sumi/Managers/ExtensionManager/ExtensionRuntimePublicationReconciler.swift'
runtime_publication_replay_scheduler='Sumi/Managers/ExtensionManager/ExtensionRuntimePublicationReplayScheduler.swift'
deferred_tab_closures='Sumi/Managers/ExtensionManager/ExtensionDeferredTabClosures.swift'
browser_content_inventory='Sumi/Managers/ExtensionManager/ExtensionBrowserContentInventory.swift'
runtime_reload_transaction='Sumi/Managers/ExtensionManager/ExtensionRuntimeReloadTransaction.swift'
runtime_teardown='Sumi/Managers/ExtensionManager/ExtensionRuntimeTeardownOwner.swift'
runtime_gate_tests='SumiTests/ExtensionRuntimePublicationGateTests.swift'
content_inventory_tests='SumiTests/ExtensionBrowserContentInventoryTests.swift'
auxiliary_window_lifecycle='Sumi/Managers/ExtensionManager/ExtensionAuxiliaryWindowLifecycle.swift'
auxiliary_publication_query='Sumi/Managers/ExtensionManager/ExtensionAuxiliaryWindowPublicationQuery.swift'
auxiliary_publication_resolver='Sumi/Managers/ExtensionManager/ExtensionAuxiliaryWindowPublicationResolver.swift'
auxiliary_opening_transaction='Sumi/Managers/ExtensionManager/ExtensionAuxiliaryWindowOpeningTransaction.swift'
auxiliary_publication_ledger='Sumi/Managers/ExtensionManager/ExtensionAuxiliaryWindowPublicationLedger.swift'
auxiliary_publication_retirement='Sumi/Managers/ExtensionManager/ExtensionAuxiliaryWindowPublicationRetirement.swift'
auxiliary_tab_preparer='Sumi/Managers/ExtensionManager/ExtensionAuxiliaryTabPublicationPreparer.swift'
auxiliary_tab_receipt='Sumi/Managers/ExtensionManager/ExtensionAuxiliaryTabPublicationReceipt.swift'
window_publication_query='Sumi/Managers/ExtensionManager/ExtensionWindowPublicationQuery.swift'
tab_publication_admission='Sumi/Managers/ExtensionManager/ExtensionTabPublicationAdmission.swift'
adapter_store='Sumi/Managers/ExtensionManager/ExtensionBrowserAdapterStore.swift'
auxiliary_events='Sumi/AuxiliaryWindows/AuxiliaryWindowCapabilities.swift'
auxiliary_teardown='Sumi/AuxiliaryWindows/AuxiliaryWindowTeardownService.swift'
auxiliary_composition='Sumi/AuxiliaryWindows/BrowserAuxiliaryWindowComposition.swift'
auxiliary_popup_opening='Sumi/AuxiliaryWindows/AuxiliaryPopupOpeningService.swift'
extension_window_opening='Sumi/AuxiliaryWindows/ExtensionAuxiliaryWindowOpeningService.swift'
auxiliary_tests='SumiTests/AuxiliaryWindowLifecycleTests.swift'
auxiliary_publication_tests='SumiTests/AuxiliaryWindowPublicationLifecycleTests.swift'
auxiliary_identity_tests='SumiTests/AuxiliaryWindowAdapterIdentityTests.swift'
normal_window_lifecycle='Sumi/Managers/ExtensionManager/ExtensionNormalWindowLifecycle.swift'
normal_window_projection='Sumi/Managers/ExtensionManager/ExtensionNormalWindowProjectionResolver.swift'
context_publication_query='Sumi/Managers/ExtensionManager/ExtensionContextPublicationQuery.swift'
controller_attachment='Sumi/Managers/ExtensionManager/ExtensionControllerRuntimeAssembler.swift'
extension_tab_shell='Sumi/Managers/ExtensionManager/ExtensionTabAdapter.swift'
extension_tab_evidence='Sumi/Managers/ExtensionManager/ExtensionTabCurrentPublicationEvidence.swift'
extension_tab_projection='Sumi/Managers/ExtensionManager/ExtensionTabReadProjection.swift'
extension_tab_commands='Sumi/Managers/ExtensionManager/ExtensionTabCommandMutation.swift'
extension_tab_webview='Sumi/Managers/ExtensionManager/ExtensionTabWebViewResolver.swift'
extension_tab_roles=(
  "$extension_tab_shell"
  "$extension_tab_evidence"
  "$extension_tab_projection"
  "$extension_tab_commands"
  "$extension_tab_webview"
)
normal_tab_open='Sumi/Managers/ExtensionManager/ExtensionNormalTabOpenTransaction.swift'
normal_tab_queries='Sumi/Managers/ExtensionManager/ExtensionNormalTabPublicationQueries.swift'
normal_tab_registration='Sumi/Managers/ExtensionManager/ExtensionNormalTabRegistration.swift'
normal_tab_properties='Sumi/Managers/ExtensionManager/ExtensionTabPropertyPublisher.swift'
normal_tab_rebind='Sumi/Managers/ExtensionManager/ExtensionTabLifecycleRebindTransaction.swift'
normal_tab_deferred='Sumi/Managers/ExtensionManager/ExtensionDeferredTabRegistration.swift'
normal_tab_events='Sumi/Managers/ExtensionManager/ExtensionTabLifecycleEmitter.swift'
window_request_router='Sumi/Managers/ExtensionManager/ExtensionWindowRequestRouter.swift'
requested_tab_opening='Sumi/Managers/ExtensionManager/ExtensionRequestedTabOpeningService.swift'
requested_tab_registrar='Sumi/Managers/ExtensionManager/ExtensionCreatedTabRuntimeRegistrar.swift'
requested_tab_receipt='Sumi/Managers/ExtensionManager/ExtensionCreatedTabPublicationReceipt.swift'
requested_tab_validator='Sumi/Managers/ExtensionManager/ExtensionCreatedTabPublicationValidator.swift'
requested_tab_target_resolver='Sumi/Managers/ExtensionManager/ExtensionRequestedTabTargetResolver.swift'
requested_tab_discard='Sumi/Managers/BrowserManager/ExtensionRequestedTabDiscardService.swift'
requested_tab_mutation_factory='Sumi/Managers/BrowserManager/BrowserExtensionTabMutationComposition.swift'
requested_tab_tests='SumiTests/ExtensionRequestedTabServicesTests.swift'
initial_tab_contract='Sumi/Managers/ExtensionManager/InitialTabExtensionPublication.swift'
initial_tab_evidence='Sumi/Managers/ExtensionManager/ExtensionInitialTabPublicationEvidence.swift'
initial_tab_preparer='Sumi/Managers/ExtensionManager/ExtensionInitialTabPublicationPreparer.swift'
initial_tab_receipt='Sumi/Managers/ExtensionManager/ExtensionInitialTabPublicationReceipt.swift'
initial_tab_retirement='Sumi/Managers/ExtensionManager/ExtensionInitialTabPublicationRetirement.swift'
initial_tab_validator='Sumi/Managers/ExtensionManager/ExtensionInitialTabPublicationValidator.swift'
initial_tab_tests='SumiTests/ExtensionInitialTabPublicationReceiptTests.swift'
adapter_files=(
  Sumi/Managers/ExtensionManager/BrowserExtensionAuxiliaryWindowAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionTabMutationAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionTabQueryAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionWebViewAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionWindowActivationAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionWindowPresentationAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionWindowQueryAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserRequestedTabTargetAdapter.swift
)
required_files=(
  "$composition"
  Sumi/Managers/ExtensionManager/ExtensionBridge.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupPresentation.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupSourceReceipt.swift
  "$runtime_publication_composition"
  "$runtime_publication"
  "$auxiliary_publication"
  "$runtime_publication_gate"
  "$runtime_publication_reconciler"
  "$deferred_tab_closures"
  "$browser_content_inventory"
  "$runtime_reload_transaction"
  "$runtime_teardown"
  "$runtime_gate_tests"
  "$content_inventory_tests"
  "$auxiliary_window_lifecycle"
  "$auxiliary_publication_query"
  "$auxiliary_publication_resolver"
  "$auxiliary_opening_transaction"
  "$auxiliary_publication_ledger"
  "$auxiliary_publication_retirement"
  "$auxiliary_tab_preparer"
  "$auxiliary_tab_receipt"
  "$window_publication_query"
  "$tab_publication_admission"
  "$adapter_store"
  "$normal_tab_open"
  "$normal_tab_queries"
  "$normal_tab_registration"
  "$normal_tab_properties"
  "$normal_tab_rebind"
  "$normal_tab_deferred"
  "$normal_tab_events"
  "$auxiliary_events"
  "$auxiliary_popup_opening"
  "$extension_window_opening"
  "$auxiliary_tests"
  "$auxiliary_publication_tests"
  "$auxiliary_identity_tests"
  "$normal_window_lifecycle"
  "$normal_window_projection"
  "$context_publication_query"
  "$controller_attachment"
  "${extension_tab_roles[@]}"
  "$window_request_router"
  "$requested_tab_opening"
  "$requested_tab_registrar"
  "$requested_tab_receipt"
  "$requested_tab_validator"
  "$requested_tab_target_resolver"
  "$requested_tab_discard"
  "$initial_tab_contract"
  "$initial_tab_evidence"
  "$initial_tab_preparer"
  "$initial_tab_receipt"
  "$initial_tab_retirement"
  "$initial_tab_validator"
  "$initial_tab_tests"
  "$requested_tab_mutation_factory"
  "$requested_tab_tests"
  "${adapter_files[@]}"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: extension browser bridge boundary missing: %s\n' "$file" >&2
    status=1
  fi
done

removed_files=(
  Sumi/Managers/BrowserManager/BrowserExtensionBridgeBundle.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionBridgeAdapter.swift
  Sumi/Managers/ExtensionManager/ExtensionBrowserRuntimeBridgeOwner.swift
  Sumi/Managers/ExtensionManager/ExtensionManager+BrowserRuntimeEvents.swift
)

for file in "${removed_files[@]}"; do
  if [[ -e "$file" ]]; then
    printf 'error: retired extension bridge god surface returned: %s\n' \
      "$file" >&2
    status=1
  fi
done

legacy_hits="$(
  rg -n '\b(ExtensionBrowserBridgeContext|BrowserExtensionBridgeAdapter|BrowserExtensionBridgeBundle|ExtensionBrowserRuntimeBridgeOwner|browserBridgeContext|extensionBridgeBundle|browserRuntimeBridgeOwner|browserRuntimeBridgeOwnerStorage|loadedBrowserRuntimeBridgeOwner)\b' \
    App Sumi SumiTests -g '*.swift' || true
)"
fail_matches "retired aggregate extension bridge returned" "$legacy_hits"

for required_runtime_composition_boundary in \
  'var runtimePublicationGate: ExtensionRuntimePublicationGate' \
  'var normalWindowLifecycle: ExtensionNormalWindowLifecycle' \
  'var auxiliaryWindowLifecycle: ExtensionAuxiliaryWindowLifecycle' \
  'var windowPublications: ExtensionWindowPublicationQuery' \
  'var tabPublicationAdmission: ExtensionTabPublicationAdmission' \
  'var normalTabActivation: ExtensionNormalTabActivationTransaction' \
  'var normalTabClosure: ExtensionNormalTabCloseTransaction' \
  'var runtimeReloadTransaction: ExtensionRuntimeReloadTransaction' \
  'var runtimePublicationReconciler: ExtensionRuntimePublicationReconciler' \
  'var loadedRuntimePublicationReconciler:' \
  'struct ExtensionRuntimePublicationComposition' \
  'private func prepareRuntimePublicationComposition()' \
  'guard runtimePublicationComposition == nil else { return }' \
  'gate: gate' \
  'runtimePublicationComposition = ExtensionRuntimePublicationComposition('; do
  if ! rg -Fq "$required_runtime_composition_boundary" \
      "$runtime_publication_composition"; then
    printf 'error: exact runtime publication composition missing: %s\n' \
      "$required_runtime_composition_boundary" >&2
    status=1
  fi
done

if ! rg -Uq \
    'var runtimePublicationComposition:[[:space:]]*ExtensionRuntimePublicationComposition\?' \
    Sumi/Managers/ExtensionManager/ExtensionManager.swift; then
  printf 'error: ExtensionManager lacks one atomic runtime composition state\n' >&2
  status=1
fi
partial_runtime_storage_hits="$(
  rg -n \
    'runtimePublicationGateStorage|normalWindowLifecycleStorage|auxiliaryWindowLifecycleStorage|windowPublicationsStorage|tabPublicationAdmissionStorage|normalTabActivationStorage|normalTabClosureStorage|runtimeReloadTransactionStorage|runtimePublicationReconcilerStorage' \
    App Sumi SumiTests -g '*.swift' || true
)"
fail_matches \
  "runtime publication graph can be represented as partially assembled state" \
  "$partial_runtime_storage_hits"

replacement_facade_files=(
  "$runtime_publication_composition"
  "$runtime_publication"
  "$auxiliary_publication"
  "$runtime_publication_gate"
  "$runtime_publication_reconciler"
  "$deferred_tab_closures"
  "$browser_content_inventory"
)
replacement_facade_hits="$(
  rg -n \
    '^[[:space:]]*(private[[:space:]]+)?(final[[:space:]]+)?(class|struct|enum|protocol)[[:space:]]+[A-Za-z0-9_]*(Owner|Bundle|Services|Bridge)\b|^[[:space:]]*(private[[:space:]]+)?struct[[:space:]]+(Dependencies|Actions)\b' \
    "${replacement_facade_files[@]}" || true
)"
fail_matches \
  "deleted runtime bridge was replaced by another owner/bundle/closure-bag facade" \
  "$replacement_facade_hits"

exact_runtime_root_storage_hits="$(
  rg -n \
    '^[[:space:]]+private[[:space:]]+(weak[[:space:]]+)?(let|var)[[:space:]]+(manager|extensionManager)\b|^[[:space:]]+private[[:space:]]+(weak[[:space:]]+)?(let|var)[^:]*:[[:space:]]*ExtensionManager\b' \
    "$runtime_publication_gate" \
    "$runtime_publication_reconciler" \
    "$browser_content_inventory" || true
)"
fail_matches \
  "exact runtime publication capability retained ExtensionManager" \
  "$exact_runtime_root_storage_hits"

composition_forwarders="$(
  rg -n '^[[:space:]]+func[[:space:]]+' \
    "$runtime_publication_composition" || true
)"
fail_matches \
  "runtime publication composition grew behavior forwarders" \
  "$composition_forwarders"

loaded_reconciler_source="$(
  sed -n \
    '/var loadedRuntimePublicationReconciler:/,/^    }/p' \
    "$runtime_publication_composition"
)"
if ! printf '%s\n' "$loaded_reconciler_source" \
    | rg -Fq 'runtimePublicationComposition?.reconciler'; then
  printf 'error: loaded-only runtime reconciler does not return existing storage\n' >&2
  status=1
fi
loaded_reconciler_materialization_hits="$(
  printf '%s\n' "$loaded_reconciler_source" \
    | rg -n 'prepareRuntimePublicationComposition|runtimePublicationReconciler[[:space:]]*$' || true
)"
fail_matches \
  "loaded-only runtime reconciler materializes the cold publication graph" \
  "$loaded_reconciler_materialization_hits"

if ! rg -Uq \
    'manager\.loadedRuntimePublicationReconciler\?\.retire\([[:space:]]*runtime:[[:space:]]*manager\.runtime,[[:space:]]*auxiliaryControl:[[:space:]]*manager\.extensionAuxiliaryWindows' \
    "$runtime_teardown"; then
  printf 'error: runtime teardown does not use the loaded-only reconciler\n' >&2
  status=1
fi
cold_teardown_materialization_hits="$(
  rg -n 'manager\.runtimePublicationReconciler\.retire|prepareRuntimePublicationComposition' \
    "$runtime_teardown" || true
)"
fail_matches \
  "cold runtime teardown materializes the publication graph" \
  "$cold_teardown_materialization_hits"

for required_gate_boundary in \
  'var acceptsBrowserEvents: Bool' \
  'func beginReload() -> ReloadClaim?' \
  'func reloadIsCurrent(_ claim: ReloadClaim) -> Bool' \
  'func beginBrowserEventHandoff(_ claim: ReloadClaim) -> Bool' \
  'func exactTabCloseDisposition() -> ExactTabCloseDisposition' \
  'func finishReload(' \
  'func beginTerminalRetirement() -> Bool' \
  'func finishTerminalRetirement()'; do
  if ! rg -Fq "$required_gate_boundary" "$runtime_publication_gate"; then
    printf 'error: runtime publication gate boundary missing: %s\n' \
      "$required_gate_boundary" >&2
    status=1
  fi
done

for required_gate_usage in \
  'gate.beginReload()' \
  'gate.reloadIsCurrent(claim)' \
  'gate.finishReload(' \
  'gate.beginTerminalRetirement()' \
  'gate.finishTerminalRetirement()'; do
  if ! rg -Fq "$required_gate_usage" \
      "$runtime_publication_reconciler"; then
    printf 'error: runtime publication reconciler bypasses gate phase: %s\n' \
      "$required_gate_usage" >&2
    status=1
  fi
done

for required_reload_claim_route in \
  'publicationClaim: claim' \
  'publicationClaim: ExtensionRuntimePublicationGate.ReloadClaim' \
  'publicationGate.beginBrowserEventHandoff(publicationClaim)' \
  'during: publicationClaim' \
  'during claim: ExtensionRuntimePublicationGate.ReloadClaim' \
  'gate.reloadIsCurrent(claim)'; do
  if ! rg -Fq "$required_reload_claim_route" \
      "$runtime_publication_reconciler" \
      "$runtime_reload_transaction" \
      "$normal_tab_open" \
      "$tab_publication_admission"; then
    printf 'error: reload-internal Tab publication lost its exact claim: %s\n' \
      "$required_reload_claim_route" >&2
    status=1
  fi
done

if ! rg -Fq 'guard gate.admitStructuralBrowserEvent() else { return false }' \
    "$tab_publication_admission"; then
  printf 'error: normal Tab publication admission bypasses the runtime gate\n' >&2
  status=1
fi

for required_coalesced_reload_boundary in \
  'var canCoalesceReloadRequest: Bool' \
  'private var pendingReload: ReloadWork?' \
  'pendingReload = work' \
  'pendingReload = nil' \
  'replayScheduler.replaceScheduledReplay' \
  'replayScheduler.canScheduleReplay' \
  'takeDeferredStructuralEvent('; do
  if ! rg -Fq "$required_coalesced_reload_boundary" \
      "$runtime_publication_gate" \
      "$runtime_publication_reconciler" \
      "$runtime_publication_replay_scheduler"; then
    printf 'error: callback-triggered reload/event reconciliation is lost: %s\n' \
      "$required_coalesced_reload_boundary" >&2
    status=1
  fi
done

for required_deferred_reload_settlement in \
  'self.settleDeferredCommit(commit)' \
  'self?.settleRuntimePublicationCommit(commit)' \
  'settleRuntimePublicationCommit(commit)'; do
  if ! rg -Fq "$required_deferred_reload_settlement" \
      "$runtime_publication_reconciler" \
      "$runtime_publication_composition" \
      "$runtime_publication"; then
    printf 'error: deferred runtime reload loses focus/activation settlement: %s\n' \
      "$required_deferred_reload_settlement" >&2
    status=1
  fi
done

for required_post_callback_open_authority in \
  'publicationGate.reloadIsCurrent(reloadClaim)' \
  'profileRuntime.contextBindingGeneration(for: profileID)' \
  'profileRuntime.controller(for: profileID) === controller' \
  'adapters.existingTabAdapter(for: tab.id) === adapter' \
  'liveWebViews?.extensionLiveWebView(for: tab) === webView' \
  'tabs?.extensionTab(for: tab.id) === tab' \
  'claimDidOpenTabNotificationForClose(' \
  'windowPublications?.tabPublicationIsCurrent('; do
  if ! rg -Fq "$required_post_callback_open_authority" \
      "$normal_tab_open"; then
    printf 'error: didOpenTab lost exact post-callback authority: %s\n' \
      "$required_post_callback_open_authority" >&2
    status=1
  fi
done

open_authority_validation_count="$(rg -Fc 'remainsCurrent(' \
  "$normal_tab_open")"
if (( open_authority_validation_count < 3 )); then
  printf 'error: didOpenTab authority is not validated before and after callback\n' >&2
  status=1
fi

for required_exact_close_boundary in \
  'private let deferredTabClosures: ExtensionDeferredTabClosures' \
  'struct ExtensionNormalTabCloseReceipt' \
  'func deferTabClose(_ tab: Tab) -> Bool' \
  'drainDeferredTabClosures()' \
  'manager.runtimePublicationReconciler.deferTabClose(tab)' \
  'adapter.hasExactTabIdentity(tab)' \
  'adapterStore.removeTabAdapter('; do
  if ! rg -Fq "$required_exact_close_boundary" \
      "$runtime_publication_reconciler" \
      Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift \
      Sumi/Managers/ExtensionManager/ExtensionNormalTabCloseTransaction.swift; then
    printf 'error: exact pre-handoff Tab closure is lost: %s\n' \
      "$required_exact_close_boundary" >&2
    status=1
  fi
done

detached_close_membership_hits="$(
  rg -n 'adapter(Resolution)?\.(stableAdapter|represents)|receipt\.adapter\.represents' \
    Sumi/Managers/ExtensionManager/ExtensionNormalTabCloseTransaction.swift \
    || true
)"
fail_matches \
  "detached Tab close receipt depends on live collection membership" \
  "$detached_close_membership_hits"

for requested_tab_single_publisher_boundary in \
  'registerTabWithExtensionRuntime: false' \
  'registerTabWithExtensionRuntime: Bool = true'; do
  if ! rg -Fq "$requested_tab_single_publisher_boundary" \
      Sumi/Managers/ExtensionManager/ExtensionRequestedTabWebViewMaterializer.swift \
      Sumi/Models/Tab/TabNormalWebViewSetupService.swift; then
    printf 'error: requested Tab WebView provisioning can publish outside its receipt: %s\n' \
      "$requested_tab_single_publisher_boundary" >&2
    status=1
  fi
done

unbounded_reload_drain_hits="$(
  rg -n 'while[[:space:]]+true' "$runtime_publication_reconciler" || true
)"
fail_matches \
  "runtime publication reconciliation can monopolize the main thread" \
  "$unbounded_reload_drain_hits"

window_batch_finish_line="$(
  rg -n -m1 'normalWindows\.finishRuntimeReconciliation\(' \
    "$runtime_reload_transaction" | cut -d: -f1 || true
)"
browser_handoff_line="$(
  rg -n -m1 'publicationGate\.beginBrowserEventHandoff\(' \
    "$runtime_reload_transaction" | cut -d: -f1 || true
)"
if [[ -z "$window_batch_finish_line" || -z "$browser_handoff_line" \
      || "$window_batch_finish_line" -ge "$browser_handoff_line" ]]; then
  printf 'error: browser events must remain deferred until every window callback completes\n' >&2
  status=1
fi

reload_claim_line="$(
  rg -n -m1 'gate\.beginReload\(' "$runtime_publication_reconciler" \
    | cut -d: -f1 || true
)"
reload_suspend_line="$(
  rg -n -m1 'suspendForRuntimeReload\(' "$runtime_publication_reconciler" \
    | cut -d: -f1 || true
)"
retirement_claim_line="$(
  rg -n -m1 'gate\.beginTerminalRetirement\(' \
    "$runtime_publication_reconciler" | cut -d: -f1 || true
)"
retirement_close_line="$(
  rg -n -m1 'closeAllForRuntimeTeardown\(' \
    "$runtime_publication_reconciler" | cut -d: -f1 || true
)"
if [[ -z "$reload_claim_line" || -z "$reload_suspend_line" \
      || "$reload_claim_line" -ge "$reload_suspend_line" ]]; then
  printf 'error: reload must claim the publication gate before suspending sessions\n' >&2
  status=1
fi
if [[ -z "$retirement_claim_line" || -z "$retirement_close_line" \
      || "$retirement_claim_line" -ge "$retirement_close_line" ]]; then
  printf 'error: terminal retirement must claim the gate before close callbacks\n' >&2
  status=1
fi

for required_inventory_boundary in \
  'struct ExtensionBrowserContentInventory' \
  'func tabs(in runtime: ExtensionManagerRuntime) -> [Tab]' \
  'func liveWebViews(' \
  'guard runtime.browserRuntimeAvailable() else { return [] }' \
  'runtime.primaryTrackedWindowId(tab.id)' \
  'runtime.untrackedOwnedWebView(tab)' \
  'runtime.trackedWebViews(tab.id)' \
  'seen.insert(ObjectIdentifier(webView)).inserted' \
  'var browserContentInventory: ExtensionBrowserContentInventory { .init() }'; do
  if ! rg -Fq "$required_inventory_boundary" \
      "$browser_content_inventory"; then
    printf 'error: exact browser-content inventory boundary missing: %s\n' \
      "$required_inventory_boundary" >&2
    status=1
  fi
done

inventory_storage_hits="$(
  rg -n '^[[:space:]]+private[[:space:]]+(let|var)[[:space:]]+' \
    "$browser_content_inventory" || true
)"
fail_matches "stateless browser-content inventory gained stored state" \
  "$inventory_storage_hits"
inventory_materialization_hits="$(
  rg -n 'prepareRuntimePublicationComposition|runtimePublication(Reconciler|Gate|Lifecycle)' \
    "$browser_content_inventory" || true
)"
fail_matches \
  "read-only browser-content inventory materializes publication lifecycle" \
  "$inventory_materialization_hits"

duplicated_inventory_algorithm_hits="$(
  rg -n 'func[[:space:]]+(allKnownTabs|liveWebViews)\b' \
    App Sumi -g '*.swift' \
    -g '!ExtensionBrowserContentInventory.swift' || true
)"
fail_matches \
  "browser-content inventory algorithm was duplicated outside its capability" \
  "$duplicated_inventory_algorithm_hits"

for required_inventory_consumer in \
  'contentInventory.tabs(in: runtime)' \
  'contentInventory.liveWebViews(for: tab, in: runtime)'; do
  if ! rg -Fq "$required_inventory_consumer" \
      "$runtime_reload_transaction"; then
    printf 'error: runtime reload bypasses browser-content inventory: %s\n' \
      "$required_inventory_consumer" >&2
    status=1
  fi
done

for required_gate_regression in \
  testActiveGateAcceptsOrdinaryBrowserEvents \
  testReloadClaimIsExclusiveUntilFinished \
  testTerminalRetirementInvalidatesInFlightReload \
  testReloadHandoffAcceptsEventsWithoutAllowingNestedReload \
  testPreHandoffStructuralEventRequestsFollowUpWithoutAdmission \
  testAuxiliaryEventRemainsSynchronousAndRequestsFollowUp \
  testReloadClaimCannotAuthorizeAnotherGate \
  testInactiveGateBlocksOrdinaryBrowserEvents \
  testReloadCanReactivateInactiveGate; do
  if ! rg -Fq "func $required_gate_regression" "$runtime_gate_tests"; then
    printf 'error: runtime publication gate regression missing: %s\n' \
      "$required_gate_regression" >&2
    status=1
  fi
done

for required_reentrancy_regression in \
  testExactTabCloseIsDeferredOnlyBeforeReloadHandoff \
  testExactTabCloseIsRejectedDuringTerminalRetirement \
  testRepeatedCallbackReloadIsBoundedToOneCoalescedReplay \
  testSecondReplayRequestContinuesOnLaterMainActorTurn \
  testDidOpenDoesNotSettleAfterAdapterAuthorityChangesInCallback \
  testDidOpenDoesNotSettleAfterContextBindingChangesInCallback \
  testDidOpenIsNotEmittedWhenWindowAdmissionLosesTabAuthority \
  testPreHandoffPhysicalTabCloseRetiresExactAdapter; do
  if ! rg -Fq "func $required_reentrancy_regression" \
      "$runtime_gate_tests" \
      SumiTests/ExtensionActionPopupSourceReceiptTests.swift; then
    printf 'error: runtime reentrancy regression missing: %s\n' \
      "$required_reentrancy_regression" >&2
    status=1
  fi
done

for required_inventory_regression in \
  testTabsPreserveRuntimeThenWindowEphemeralOrder \
  testLiveWebViewsOrderPrimaryThenUntrackedThenRemainingTracked \
  testTrackedOrderRemainsStableWithoutPrimaryResidence \
  testUnavailableRuntimeDoesNotReadWebViewProviders; do
  if ! rg -Fq "func $required_inventory_regression" \
      "$content_inventory_tests"; then
    printf 'error: browser-content inventory regression missing: %s\n' \
      "$required_inventory_regression" >&2
    status=1
  fi
done

if ! rg -Fq \
    'func testRejectedInvocationDoesNotMaterializeLazyRuntimeSystems' \
    SumiTests/ExtensionActionInvocationAdmissionTests.swift; then
  printf 'error: cold rejected-invocation composition regression missing\n' >&2
  status=1
fi

for required_publication_lifetime_regression in \
  testColdRuntimeTeardownDoesNotMaterializePublicationLifecycle \
  testRetainedPublicationCollaboratorsDoNotRetainExtensionManager \
  testTerminalRuntimeRetirementRejectsReloadFromAuxiliaryCloseCallback \
  testStaleNormalWindowCloseCannotRetireReplacementWithSameUUID \
  testCallbackReloadIsCoalescedAfterCurrentGeneration \
  testTabPropertyEventRequiresCurrentOpenPublication; do
  if ! rg -Fq "func $required_publication_lifetime_regression" \
      SumiTests/ExtensionRuntimeTeardownOwnerTests.swift \
      "$auxiliary_identity_tests" \
      SumiTests/ExtensionActionPopupSourceReceiptTests.swift; then
    printf 'error: runtime publication lifetime regression missing: %s\n' \
      "$required_publication_lifetime_regression" >&2
    status=1
  fi
done

for required_current_tab_property_boundary in \
  'publicationGate?.acceptsBrowserEvents' \
  '.hasSettledDidOpenTabNotification(for: generation)' \
  'windows?.tabPublicationIsCurrent(' \
  'publishedTabs?.containsPublishedTab(tab) == true'; do
  if ! rg -Fq "$required_current_tab_property_boundary" \
      "$normal_tab_queries" "$normal_tab_properties"; then
    printf 'error: Tab property event lacks current open-publication proof: %s\n' \
      "$required_current_tab_property_boundary" >&2
    status=1
  fi
done

if (( $(rg -c 'runtimePublicationGate\.admitStructuralBrowserEvent\(\)' \
      Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift || true) < 2 )); then
  printf 'error: normal open/close routes bypass structural reload admission\n' >&2
  status=1
fi
if ! rg -Fq 'runtimePublicationGate.exactTabCloseDisposition()' \
    Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift; then
  printf 'error: normal Tab close bypasses exact reload disposition\n' >&2
  status=1
fi
if ! rg -Fq 'guard case .active = phase else { return }' \
    "$normal_window_lifecycle"; then
  printf 'error: normal-window close can interleave with lifecycle batches\n' >&2
  status=1
fi

popup_active_lookup_hits="$(
  rg -n '\b(currentExtensionTabForPopup|currentExtensionTabForActiveWindow|activeExtensionWindowState)\b' \
    Sumi/Managers/ExtensionManager/ExtensionActionPopupPresentation.swift || true
)"
fail_matches \
  "extension action popup routing rediscovered its opener through active-window state" \
  "$popup_active_lookup_hits"

legacy_popup_lookup_hits="$(
  rg -n '\bcurrentExtensionTabForPopup\b' App Sumi -g '*.swift' || true
)"
fail_matches "ambiguous action-popup active-tab lookup returned" "$legacy_popup_lookup_hits"

for required_popup_boundary in \
  'sourceReceipt.resolve(' \
  'openerProfileID: sourceReceipt.profileID'; do
  if ! rg -Fq "$required_popup_boundary" \
      Sumi/Managers/ExtensionManager/ExtensionActionPopupPresentation.swift; then
    printf 'error: exact action-popup source boundary missing: %s\n' \
      "$required_popup_boundary" >&2
    status=1
  fi
done

if ! rg -Fq 'childConfiguration.websiteDataStore === profile.dataStore' \
    Sumi/Managers/ExtensionManager/ExtensionActionPopupSourceReceipt.swift; then
  printf 'error: exact action-popup child data-store check missing\n' >&2
    status=1
fi

normal_window_lookup_consumers=(
  "$extension_tab_projection"
  Sumi/Managers/ExtensionManager/ExtensionActionPopupPresentation.swift
)
raw_normal_window_lookup_hits="$(
  rg -n '\b(browserRuntimeBridgeOwner\.publishedWindowAdapter|adapterCatalog\.windowAdapter)\b' \
    "${normal_window_lookup_consumers[@]}" || true
)"
fail_matches \
  "normal-window consumer bypassed context-bound published projection" \
  "$raw_normal_window_lookup_hits"

if ! rg -Fq 'publishedNormalWindowAdapter(' \
    Sumi/Managers/ExtensionManager/ExtensionActionPopupPresentation.swift; then
  printf 'error: context-bound action-popup window projection missing\n' >&2
  status=1
fi
for boundary in 'publishedWindowAdapter(' 'adapter.represents(window)'; do
  if ! rg -Fq "$boundary" "$extension_tab_projection"; then
    printf 'error: exact Tab window projection missing: %s\n' "$boundary" >&2
    status=1
  fi
done

for required_projection_boundary in \
  'func publishedNormalWindowAdapter(' \
  'extensionContext: WKWebExtensionContext' \
  'adapter.represents(windowState)'; do
  if ! rg -Fq "$required_projection_boundary" \
      Sumi/Managers/ExtensionManager/ExtensionAdapterCatalog.swift; then
    printf 'error: published normal-window projection boundary missing: %s\n' \
      "$required_projection_boundary" >&2
    status=1
  fi
done

for required_adapter_lease in \
  'private weak var exactWindowState: BrowserWindowState?' \
  'func publishedWindowState(' \
  '.publishedWindowAdapter(' \
  ') === self'; do
  if ! rg -Fq "$required_adapter_lease" \
      Sumi/Managers/ExtensionManager/ExtensionBridge.swift; then
    printf 'error: normal-window adapter publication lease missing: %s\n' \
      "$required_adapter_lease" >&2
    status=1
  fi
done

for required_exact_context_boundary in \
  'profileRuntime?.exactContextIdentity(for: context)' \
  'private weak var contextPublications: ExtensionContextPublicationQuery?' \
  'contextPublications?.currentIdentity(' \
  'profileRuntime.exactContextIdentity('; do
  if ! rg -Fq "$required_exact_context_boundary" \
      "$context_publication_query" \
      Sumi/Managers/ExtensionManager/ExtensionBridge.swift \
      "$extension_tab_evidence" \
      "$controller_attachment" \
      "$window_request_router"; then
    printf 'error: exact current-context capability boundary missing: %s\n' \
      "$required_exact_context_boundary" >&2
    status=1
  fi
done

fuzzy_context_capability_hits="$(
  rg -U -n \
    'profileRuntime\??\.(contextIdentity|profileId)\([[:space:]]*for:[[:space:]]*(extensionContext|context)' \
    "$context_publication_query" \
    Sumi/Managers/ExtensionManager/ExtensionBridge.swift \
    "$extension_tab_evidence" \
    "$controller_attachment" \
    "$window_request_router" || true
)"
fail_matches \
  "extension capability accepts a fuzzy/replaced context binding" \
  "$fuzzy_context_capability_hits"

window_adapter_store_escape_hits="$(
  rg -n '\.windowAdapters\b' App Sumi SumiTests -g '*.swift' \
    -g '!ExtensionBrowserAdapterStore.swift' || true
)"
fail_matches \
  "raw normal-window adapter store escaped its materialization boundary" \
  "$window_adapter_store_escape_hits"

unused_mutation_hits="$(
  rg -n '\b(assignExtensionWebView|replaceUntrackedExtensionWebView)\b' \
    App Sumi SumiTests -g '*.swift' || true
)"
fail_matches "unused broad WebView mutation escaped the bridge split" "$unused_mutation_hits"

direct_auxiliary_window_callbacks="$(
  rg -n '\b(extensionContext|context)\.did(Open|Close|Focus)(Window|Tab)\b|auxiliaryOwnerExtensionContext' \
    "$runtime_publication_composition" \
    "$runtime_publication" \
    "$auxiliary_publication" \
    "$runtime_publication_reconciler" || true
)"
fail_matches \
  "WebKit callbacks escaped the exact normal/auxiliary lifecycle transactions" \
  "$direct_auxiliary_window_callbacks"

auxiliary_lifecycle_aggregate_hits="$(
  rg -n '\bExtensionManager\b|\bstruct Dependencies\b' \
    "$auxiliary_window_lifecycle" \
    "$auxiliary_publication_query" \
    "$auxiliary_publication_resolver" \
    "$auxiliary_opening_transaction" \
    "$auxiliary_publication_ledger" \
    "$auxiliary_publication_retirement" \
    "$auxiliary_tab_preparer" \
    "$auxiliary_tab_receipt" || true
)"
fail_matches \
  "auxiliary window lifecycle reached through an aggregate manager/dependency bag" \
  "$auxiliary_lifecycle_aggregate_hits"

raw_mini_window_adapter_store_hits="$(
  rg -n 'adapterStore\.miniWindowAdapters\b' App Sumi SumiTests \
    -g '*.swift' || true
)"
fail_matches \
  "raw mini-window adapter storage escaped its lifecycle boundary" \
  "$raw_mini_window_adapter_store_hits"

mini_window_adapter_source="$(
  sed -n '/final class ExtensionMiniWindowAdapter/,/^}/p' \
    Sumi/Managers/ExtensionManager/ExtensionBridge.swift
)"
mini_window_aggregate_hits="$(
  printf '%s\n' "$mini_window_adapter_source" \
    | rg -n '\bExtensionManager\b|adapterCatalog|\btabQuery\b' || true
)"
fail_matches \
  "mini-window capability reaches through an aggregate or UUID tab query" \
  "$mini_window_aggregate_hits"

raw_mini_window_snapshot_consumers="$(
  rg -n 'adapterStore\.miniWindowAdaptersSnapshot\(' App Sumi \
    -g '*.swift' -g '!ExtensionBrowserAdapterStore.swift' || true
)"
fail_matches \
  "mini-window query bypassed the exact publication ledger" \
  "$raw_mini_window_snapshot_consumers"

unconditional_mini_window_adapter_removal="$(
  rg -n 'func removeMiniWindowAdapter\(for sessionId: UUID\)' \
    "$adapter_store" || true
)"
fail_matches \
  "unconditional mini-window adapter removal can evict a replacement" \
  "$unconditional_mini_window_adapter_removal"

for required_mini_adapter_store_boundary in \
  'private var miniWindowAdapters' \
  'func existingMiniWindowAdapter(' \
  'func miniWindowAdaptersSnapshot()' \
  'ifIdenticalTo expectedAdapter: ExtensionMiniWindowAdapter'; do
  if ! rg -Fq "$required_mini_adapter_store_boundary" "$adapter_store"; then
    printf 'error: exact mini-window adapter store boundary missing: %s\n' \
      "$required_mini_adapter_store_boundary" >&2
    status=1
  fi
done

for required_exact_tab_adapter_boundary in \
  'private weak var exactTab: Tab?' \
  'func represents(_ tab: Tab) -> Bool' \
  'func canBeReplaced(by tab: Tab) -> Bool' \
  'func prune(liveTabs: [Tab]' \
  'adapter.represents(liveTab)'; do
  if ! rg -Fq "$required_exact_tab_adapter_boundary" \
      "${extension_tab_roles[@]}" \
      "$adapter_store"; then
    printf 'error: exact Tab adapter identity boundary missing: %s\n' \
      "$required_exact_tab_adapter_boundary" >&2
    status=1
  fi
done

for required_ledger_boundary in \
  'private var publicationsBySessionID' \
  'private var closingSessionIdentityByID' \
  'func insertPrepared(' \
  'func claimForRetirement(' \
  'publicationsBySessionID.removeValue(forKey: session.id)'; do
  if ! rg -Fq "$required_ledger_boundary" "$auxiliary_publication_ledger"; then
    printf 'error: exact auxiliary publication ledger boundary missing: %s\n' \
      "$required_ledger_boundary" >&2
    status=1
  fi
done

for required_auxiliary_lifecycle_boundary in \
  'opening.open(' \
  'retirement.retire(' \
  'func suspendForRuntimeReload(' \
  'func republishAfterRuntimeReload(' \
  'func closeAllForRuntimeTeardown('; do
  if ! rg -Fq "$required_auxiliary_lifecycle_boundary" \
      "$auxiliary_window_lifecycle"; then
    printf 'error: auxiliary session lifecycle boundary missing: %s\n' \
      "$required_auxiliary_lifecycle_boundary" >&2
    status=1
  fi
done

for required_opening_boundary in \
  'resolver.resolvePublication(' \
  'ledger.insertPrepared(publication, for: session)' \
  'publication.context.didOpenWindow(publication.adapter)' \
  'publication.tabReceipt.commitOpen(runtime: runtime)' \
  'publication.context.didFocusWindow(publication.adapter)' \
  'resolver.publicationIsCurrent('; do
  if ! rg -Fq "$required_opening_boundary" \
      "$auxiliary_opening_transaction"; then
    printf 'error: two-phase auxiliary opening boundary missing: %s\n' \
      "$required_opening_boundary" >&2
    status=1
  fi
done

for required_tab_receipt_boundary in \
  'prepareForWindowPrepublication(generation: generation)' \
  'runtime.profile(profileID)?.dataStore' \
  'webView.configuration.websiteDataStore === dataStore' \
  'ownerContext.didOpenTab(adapter)' \
  'ownerContext.didCloseTab(adapter, windowIsClosing: true)'; do
  if ! rg -Fq "$required_tab_receipt_boundary" \
      "$auxiliary_tab_preparer" "$auxiliary_tab_receipt"; then
    printf 'error: exact owner-context auxiliary Tab receipt missing: %s\n' \
      "$required_tab_receipt_boundary" >&2
    status=1
  fi
done

for required_auxiliary_visibility_boundary in \
  'private weak var windowPublications:' \
  'windowPublications?.isCommittedAuxiliaryTabAdapter(' \
  'publishedAuxiliaryTabAdapter(' \
  'if tab.isAuxiliaryMiniWindow' \
  'return .unavailable' \
  'adapters.sort {' \
  'focusedExtensionMiniWindowAdapter('; do
  if ! rg -Fq "$required_auxiliary_visibility_boundary" \
      "${extension_tab_roles[@]}" \
      "$window_publication_query" "$auxiliary_publication_query"; then
    printf 'error: auxiliary owner-context visibility/query boundary missing: %s\n' \
      "$required_auxiliary_visibility_boundary" >&2
    status=1
  fi
done

tab_role_aggregate_lines="$({ cat "${extension_tab_roles[@]}"; } | wc -l | tr -d ' ')"
if (( tab_role_aggregate_lines > 780 )); then
  printf 'error: Extension Tab shell/evidence/projection/command/WebView aggregate grew beyond 780 LOC (%s)\n' \
    "$tab_role_aggregate_lines" >&2
  status=1
fi

tab_shell_lines="$(wc -l < "$extension_tab_shell" | tr -d ' ')"
if (( tab_shell_lines > 140 )); then
  printf 'error: WKWebExtensionTab protocol shell grew beyond 140 LOC (%s)\n' \
    "$tab_shell_lines" >&2
  status=1
fi

tab_role_aggregate_hits="$(
  rg -n '\bExtensionManager(Runtime)?\b|\bBrowserManager\b|\bstruct (Dependencies|Actions)\b|\bclass [A-Za-z0-9_]*Owner\b|ExtensionNormalTabRuntimeBindingOwner|ExtensionControllerAttachmentOwner' \
    "${extension_tab_roles[@]}" || true
)"
fail_matches \
  "Extension Tab roles reached through a manager root or aggregate bag" \
  "$tab_role_aggregate_hits"

if (( $(rg -Fc 'webViews?.isCanonical(tab) == true' "$extension_tab_webview") < 2 )); then
  printf 'error: Extension Tab WebView resolver must revalidate exact Tab identity before and after attachment\n' >&2
  status=1
fi

for required_exact_webview_boundary in \
  'tabs.extensionTab(for: tab.id) === tab' \
  '(webView as? FocusableWKWebView)?.owningTab === tab'; do
  if ! rg -Fq "$required_exact_webview_boundary" "$composition"; then
    printf 'error: exact physical Extension Tab WebView boundary missing: %s\n' \
      "$required_exact_webview_boundary" >&2
    status=1
  fi
done

for required_retirement_boundary in \
  'ledger.claimForRetirement(' \
  '.closePublishedTabForWindowRetirement()' \
  'publication.context.didCloseWindow(publication.adapter)' \
  'ifIdenticalTo: publication.adapter'; do
  if ! rg -Fq "$required_retirement_boundary" \
      "$auxiliary_publication_retirement"; then
    printf 'error: exact auxiliary retirement boundary missing: %s\n' \
      "$required_retirement_boundary" >&2
    status=1
  fi
done

auxiliary_tab_close_line="$(
  rg -n -m1 'closePublishedTabForWindowRetirement\(\)' \
    "$auxiliary_publication_retirement" | cut -d: -f1 || true
)"
auxiliary_window_close_line="$(
  rg -n -m1 'publication\.context\.didCloseWindow' \
    "$auxiliary_publication_retirement" | cut -d: -f1 || true
)"
if [[ -z "$auxiliary_tab_close_line" \
      || -z "$auxiliary_window_close_line" \
      || "$auxiliary_tab_close_line" -ge "$auxiliary_window_close_line" ]]; then
  printf 'error: auxiliary retirement must close owner Tab before owner Window\n' >&2
  status=1
fi

debug_hook_bag_hits="$(
  rg -n 'ExtensionAuxiliaryPublicationDebugHooks|installDebugHooks' \
    "$auxiliary_window_lifecycle" "$auxiliary_opening_transaction" \
    "$auxiliary_tab_preparer" "$auxiliary_tab_receipt" || true
)"
fail_matches "auxiliary publication reintroduced a DEBUG closure bag" \
  "$debug_hook_bag_hits"

for forbidden_auxiliary_tab_route in \
  'registerExtensionCreatedTab|extensionCreatedTabRegistrar\.register' \
  'notifyTabClosed'; do
  forbidden_hits="$(
    if [[ "$forbidden_auxiliary_tab_route" == notifyTabClosed ]]; then
      rg -n "$forbidden_auxiliary_tab_route" \
        "$auxiliary_events" "$auxiliary_teardown" \
        "$auxiliary_composition" || true
    else
      rg -n "$forbidden_auxiliary_tab_route" \
        "$auxiliary_popup_opening" "$extension_window_opening" || true
    fi
  )"
  fail_matches "generic auxiliary Tab publication/close route returned" \
    "$forbidden_hits"
done

for required_publication_validation in \
  'func resolvePublication(' \
  'func publicationIsCurrent(' \
  'control.auxiliaryWindowSession(for: session.id) === session' \
  'adapterStore.existingMiniWindowAdapter(for: session.id)' \
  'profileRuntime.extensionId(for: override)' \
  '== ownerExtensionID'; do
  if ! rg -Fq "$required_publication_validation" \
      "$auxiliary_publication_resolver"; then
    printf 'error: exact auxiliary publication validation missing: %s\n' \
      "$required_publication_validation" >&2
    status=1
  fi
done

for required_auxiliary_event_delegation in \
  'auxiliaryWindowLifecycle.opened(' \
  'auxiliaryWindowLifecycle.focused(' \
  'auxiliaryWindowLifecycle.closed('; do
  if ! rg -Fq "$required_auxiliary_event_delegation" \
      "$auxiliary_publication"; then
    printf 'error: exact auxiliary event delegation missing: %s\n' \
      "$required_auxiliary_event_delegation" >&2
    status=1
  fi
done

for required_reconciliation_delegation in \
  'suspendForRuntimeReload(' \
  'republishAfterRuntimeReload(' \
  'closeAllForRuntimeTeardown('; do
  if ! rg -Fq "$required_reconciliation_delegation" \
      "$runtime_publication_reconciler"; then
    printf 'error: runtime publication reconciliation delegation missing: %s\n' \
      "$required_reconciliation_delegation" >&2
    status=1
  fi
done

for opening_file in "$auxiliary_popup_opening" "$extension_window_opening"; do
  if ! rg -Uq \
      'notifyAuxiliaryWindowOpened\(session\)[[:space:]]*==[[:space:]]*true' \
      "$opening_file"; then
    printf 'error: auxiliary publication rejection is not propagated: %s\n' \
      "$opening_file" >&2
    status=1
  fi
  if ! rg -Fq 'reason: .presentationFailure' "$opening_file"; then
    printf 'error: rejected auxiliary publication is not rolled back: %s\n' \
      "$opening_file" >&2
    status=1
  fi
done

if ! rg -Uq \
    'func notifyAuxiliaryWindowOpened\([[:space:]]*_ session: AuxiliaryWindowSession[[:space:]]*\) -> Bool' \
    "$auxiliary_events"; then
  printf 'error: auxiliary open acceptance is not part of the event contract\n' >&2
  status=1
fi

for required_test in \
  testRejectedAuxiliaryPublicationRollsBackPresentedPopup \
  testRejectedExtensionWindowPublicationReturnsNoAdapter \
  testStaleAuxiliaryCloseCannotEvictDifferentPublishedSession \
  testAuxiliaryPublicationOpensOwnerWindowBeforeOwnerTab \
  testAuxiliaryPublicationRejectsContextReplacementDuringDidOpenWindow \
  testAuxiliaryPublicationBalancesReentrantTeardownDuringDidOpenTab \
  testAuxiliaryPublicationBalancesReentrantTeardownDuringFocus \
  testWrongDataStoreRejectsAuxiliaryPublicationWithoutCallbacks \
  testGenericPopupTeardownEmitsNoExtensionTabClose \
  testAuxiliaryTabAdapterIsInvisibleToUnrelatedSameProfileContext \
  testRetiredAuxiliaryTabAdapterCannotRebindToNormalTabWithSameID \
  testAuxiliaryTabCannotFallBackToNormalPublicationWithoutControl \
  testPublishedAuxiliaryAdaptersPlaceExactFocusedSessionFirst \
  testRuntimeTeardownClosesAuxiliaryTabOnce \
  testRuntimeReloadReopensAuxiliaryPublicationForNewGeneration \
  testRequestedTabRejectsForgedMiniWindowWithLiveIdentifiers; do
  if ! rg -Fq "func $required_test" \
      "$auxiliary_tests" \
      "$auxiliary_publication_tests" \
      "$auxiliary_identity_tests"; then
    printf 'error: auxiliary exactness regression missing: %s\n' \
      "$required_test" >&2
    status=1
  fi
done

for required_stable_window_publication_boundary in \
  'belongsToSameWindowPublication(' \
  'let refreshedProjection = resolver.resolve(' \
  'projection: refreshedProjection'; do
  if ! rg -Fq \
      "$required_stable_window_publication_boundary" \
      "$normal_window_lifecycle" "$normal_window_projection"; then
    printf 'error: stable normal-window publication boundary missing: %s\n' \
      "$required_stable_window_publication_boundary" >&2
    status=1
  fi
done

published_adapter_source="$(
  sed -n '/func publishedAdapter(/,/^    }/p' "$normal_window_lifecycle"
)"
published_adapter_mutation_hits="$(
  printf '%s\n' "$published_adapter_source" \
    | rg -n '\b(close|reconcile)[A-Za-z0-9_]*\(' || true
)"
fail_matches \
  "normal-window publication query mutates or reconciles lifecycle state" \
  "$published_adapter_mutation_hits"

requested_tab_early_activation_hits="$(
  rg -n 'activateDuringCreation|activate:[[:space:]]*shouldBeActive|activate:[[:space:]]*true' \
    "$requested_tab_opening" || true
)"
if [[ -n "$requested_tab_early_activation_hits" ]]; then
  printf 'error: requested Tab can activate during creation before exact publication\n' >&2
  status=1
fi

inactive_creation_count="$(
  rg -c 'activate:[[:space:]]*false' "$requested_tab_opening" || true
)"
if (( inactive_creation_count < 2 )); then
  printf 'error: every regular requested Tab must be created inactive\n' >&2
  status=1
fi

requested_tab_register_line="$(
  rg -n -m1 'guard registrar\.register\(' "$requested_tab_opening" \
    | cut -d: -f1 || true
)"
requested_tab_select_line="$(
  rg -n -m1 'browserContext\.selectExtensionTab\(' \
    "$requested_tab_opening" | cut -d: -f1 || true
)"
if [[ -z "$requested_tab_register_line" \
      || -z "$requested_tab_select_line" \
      || "$requested_tab_register_line" -ge "$requested_tab_select_line" ]]; then
  printf 'error: requested Tab must cross didOpenTab before didActivateTab\n' >&2
  status=1
fi

for required_requested_transaction_boundary in \
  'discardExtensionRequestedTab(' \
  'restoringSelectionTo: rollbackSelectionID' \
  'try placement.publishedResidence(' \
  'guard registrar.register(' \
  'runtime: runtime()' \
  'guard browserContext.pinExtensionTab(' \
  'browserContext.selectExtensionTab('; do
  if ! rg -Fq "$required_requested_transaction_boundary" \
      "$requested_tab_opening"; then
    printf 'error: requested Tab transaction boundary missing: %s\n' \
      "$required_requested_transaction_boundary" >&2
    status=1
  fi
done

captured_target_revalidation_count="$(
  rg -c 'target:[[:space:]]*target' "$requested_tab_opening" || true
)"
if (( captured_target_revalidation_count < 2 )); then
  printf 'error: requested Tab residence does not revalidate the captured target twice\n' >&2
  status=1
fi
requested_window_reresolution_hits="$(
  rg -U -n 'func publishedResidence\([^)]*requestedWindow' \
    "$requested_tab_target_resolver" || true
)"
fail_matches \
  "requested Tab residence can re-resolve a different Window after callbacks" \
  "$requested_window_reresolution_hits"

post_callback_admission_hits="$(
  rg -n 'publicationAdmission\.prepareTabOpen' \
    "$requested_tab_receipt" "$requested_tab_validator" || true
)"
fail_matches \
  "requested Tab post-callback validation mutates publication state" \
  "$post_callback_admission_hits"

if ! rg -Fq 'publications.tabPublicationIsCurrent(' \
    "$requested_tab_validator"; then
  printf 'error: requested Tab receipt lacks read-only publication proof\n' >&2
  status=1
fi

tab_removal_requested_hits="$(
  rg -n 'discardExtensionRequestedTab|ExtensionRequestedTabDiscard' \
    Sumi/Managers/TabManager/TabClosureService.swift || true
)"
fail_matches \
  "requested Tab rollback grew the TabClosureService dependency god" \
  "$tab_removal_requested_hits"

receipt_lines="$(wc -l < "$requested_tab_receipt" | tr -d ' ')"
if (( receipt_lines > 150 )); then
  printf 'error: requested Tab receipt regained transaction-god scope (%s > 150 LOC)\n' \
    "$receipt_lines" >&2
  status=1
fi
receipt_collaborators="$(
  rg -c '^[[:space:]]+private let (validator|retirement|diagnostics):' \
    "$requested_tab_receipt" || true
)"
if (( receipt_collaborators != 3 )); then
  printf 'error: requested Tab receipt must retain exactly three narrow collaborators\n' >&2
  status=1
fi

initial_receipt_collaborators="$(
  rg -c '^[[:space:]]+private let (validator|retirement|diagnostics|evidence):' \
    "$initial_tab_receipt" || true
)"
if (( initial_receipt_collaborators != 4 )); then
  printf 'error: initial Tab receipt must retain exactly four narrow collaborators\n' >&2
  status=1
fi
initial_receipt_runtime_leaks="$(
  rg -n 'private (weak )?var manager|private let (runtimeSession|profileRuntime|adapterStore|controllerBinding|windowRegistry|windowPublications):' \
    "$initial_tab_receipt" || true
)"
fail_matches "initial Tab receipt regained runtime-root state" \
  "$initial_receipt_runtime_leaks"

initial_slice_runtime_leaks="$(
  rg -n 'let runtime: ExtensionManagerRuntime|controllerBinding: ExtensionControllerAttachmentOwner|static func prepare\([[:space:]]*manager: ExtensionManager' \
    "$initial_tab_evidence" \
    "$initial_tab_preparer" \
    "$initial_tab_validator" \
    "$initial_tab_receipt" || true
)"
fail_matches "initial Tab collaborators hid aggregate runtime state" \
  "$initial_slice_runtime_leaks"

for required_initial_regression in \
  testDidOpenReentrancyWithRegistryRemovalBalancesExactOpenOnce \
  testDidOpenReentrancyWithContextReplacementBalancesExactOpenOnce \
  testOldReceiptCannotCloseNewGenerationUsingSameAdapter \
  testDidOpenWindowHandoffBalancesDelegatedOpenOnRollback; do
  if ! rg -Fq "func $required_initial_regression" "$initial_tab_tests"; then
    printf 'error: initial Tab reentrancy regression missing: %s\n' \
      "$required_initial_regression" >&2
    status=1
  fi
done

for required_token_regression in \
  testCommittedTokenPageMutationCannotRestoreStaleSnapshot \
  testNewSameGenerationPreparationSupersedesOldCommittedRollbackRight \
  testDelegatedClaimCannotCloseLaterSameGenerationOpen \
  testSupersededPreparationHandsOffToExactOrdinaryOpen \
  testCommittedReceiptHandsOffToExactReentrantReplacementOpen \
  testOpenPublicationRequiresExactSettlement \
  testStaleOpenSettlementCannotSettleReplacement \
  testRetiredOpenAdmissionCannotPublishAnotherGeneration \
  testWindowPrepublicationRollbackRestoresSettledOpenClaim; do
  if ! rg -Fq "func $required_token_regression" \
      SumiTests/TabExtensionPageRuntimeOwnerTests.swift; then
    printf 'error: exact open-publication token regression missing: %s\n' \
      "$required_token_regression" >&2
    status=1
  fi
done

for required_prepublication_claim in \
  'preparedWindowPrepublicationToken' \
  'state.preparedWindowPrepublicationToken === token' \
  'invalidatePreparedWindowPrepublication()' \
  'TabExtensionOpenPublicationClaim' \
  'settledOpenPublicationClaimIdentity' \
  'settleDidOpenTabNotification(' \
  'retireFutureOpenPublications()' \
  'committedMutationRevision' \
  'supersedingOpenPublicationClaimIdentity'; do
  if ! rg -Fq "$required_prepublication_claim" \
      Sumi/Models/Tab/TabExtensionPageRuntimeOwner.swift; then
    printf 'error: exact prepared Tab prepublication claim missing: %s\n' \
      "$required_prepublication_claim" >&2
    status=1
  fi
done

for required_requested_regression in \
  testTargetlessActivePinnedRequestCommitsOpenBeforeSelection \
  testDidOpenReentrancyFailureDiscardsTabAdapterAndEligibilityWithoutSelection \
  testTransientDidOpenFailureBalancesCloseExactlyOnce \
  testCurrentWindowRejectsReplacedExtensionContextWithoutFallback \
  testExplicitStaleNormalWindowAdapterWithSameUUIDIsRejectedWithoutFallback \
  testReplacedNormalContextLosesEveryTabAndWindowCapability \
  testNormalTabAdapterNeverRebindsToReplacementTabWithSameID \
  testContextPublicationQueryFailsClosedAfterRuntimeRelease; do
  if ! rg -Fq "func $required_requested_regression" "$requested_tab_tests"; then
    printf 'error: requested Tab exactness regression missing: %s\n' \
      "$required_requested_regression" >&2
    status=1
  fi
done

if ! rg -Fq 'XCTAssertIdentical(window, publishedMainWindow)' \
    "$auxiliary_tests"; then
  printf 'error: normal-window adapter stability regression missing\n' >&2
  status=1
fi

bounded_runtime_publication_files=(
  "$runtime_publication_composition:220:exact graph assembly"
  "$runtime_publication:140:normal publication routing"
  "$auxiliary_publication:80:auxiliary event routing"
  "$runtime_publication_gate:190:publication phase gate"
  "$runtime_publication_reconciler:205:generation replacement and retirement"
  "$runtime_publication_replay_scheduler:40:one-turn overflow replay scheduling"
  "$deferred_tab_closures:40:exact deferred Tab identities"
  "$browser_content_inventory:90:stateless browser-content inventory"
)
for bounded in "${bounded_runtime_publication_files[@]}"; do
  IFS=: read -r file limit responsibility <<< "$bounded"
  lines="$(wc -l < "$file" | tr -d ' ')"
  if (( lines > limit )); then
    printf 'error: %s grew beyond %s responsibility (%s > %s LOC)\n' \
      "$file" "$responsibility" "$lines" "$limit" >&2
    status=1
  fi
done

auxiliary_lifecycle_lines="$(wc -l < "$auxiliary_window_lifecycle" | tr -d ' ')"
if (( auxiliary_lifecycle_lines > 270 )); then
  printf 'error: auxiliary-window lifecycle grew beyond session orchestration (%s > 270 LOC)\n' \
    "$auxiliary_lifecycle_lines" >&2
  status=1
fi

auxiliary_resolver_lines="$(wc -l < "$auxiliary_publication_resolver" | tr -d ' ')"
if (( auxiliary_resolver_lines > 170 )); then
  printf 'error: auxiliary publication resolver grew beyond exact fact validation (%s > 170 LOC)\n' \
    "$auxiliary_resolver_lines" >&2
  status=1
fi

bounded_auxiliary_files=(
  "$auxiliary_opening_transaction:300:two-phase opening"
  "$auxiliary_publication_ledger:130:publication identity ledger"
  "$auxiliary_publication_retirement:190:ordered retirement"
  "$auxiliary_tab_preparer:190:Tab preparation"
  "$auxiliary_tab_receipt:240:Tab receipt"
  "$auxiliary_publication_query:170:auxiliary publication query"
  "$window_publication_query:180:read-only publication query"
  "$initial_tab_preparer:180:initial Tab evidence preparation"
  "$initial_tab_receipt:205:initial Tab phase transition and exact open handoff"
  "$initial_tab_retirement:100:initial Tab ordered retirement"
  "$initial_tab_validator:240:initial Tab exact validation"
)
for bounded in "${bounded_auxiliary_files[@]}"; do
  IFS=: read -r file limit responsibility <<< "$bounded"
  lines="$(wc -l < "$file" | tr -d ' ')"
  if (( lines > limit )); then
    printf 'error: %s grew beyond %s responsibility (%s: %s > %s LOC)\n' \
      "$file" "$responsibility" "$file" "$lines" "$limit" >&2
    status=1
  fi
done

if (( ${#adapter_files[@]} > 0 )); then
  manager_hits="$(
    rg -n '\bBrowserManager\b|\bbrowserManager\b' \
      "${adapter_files[@]}" || true
  )"
  fail_matches "concrete extension adapter reaches back into BrowserManager" "$manager_hits"

  owner_declarations="$(
    rg -n '^(private )?(final )?(class|struct|enum|protocol) [A-Za-z0-9_]*Owner\b' \
      "${adapter_files[@]}" || true
  )"
  fail_matches "extension bridge responsibility hidden behind an Owner type" "$owner_declarations"

  for file in "${adapter_files[@]}"; do
    [[ -f "$file" ]] || continue
    lines="$(wc -l < "$file" | tr -d ' ')"
    if (( lines > 160 )); then
      printf 'error: extension capability adapter grew beyond one responsibility (%s: %s > 160 LOC)\n' \
        "$file" "$lines" >&2
      status=1
    fi
  done
fi

if [[ -f "$composition" ]]; then
  stored_manager_hits="$(
    rg -n '^[[:space:]]+(private[[:space:]]+)?(weak[[:space:]]+)?(let|var)[[:space:]]+browserManager\b' \
      "$composition" || true
  )"
  fail_matches "extension bridge composition stores BrowserManager" "$stored_manager_hits"

  composition_forwarders="$(
    awk '
      /final class BrowserExtensionBridgeComposition/ { in_composition = 1 }
      in_composition && /^[[:space:]]+func[[:space:]]/ { print NR ":" $0 }
    ' "$composition"
  )"
  fail_matches "extension bridge composition grew forwarding methods" "$composition_forwarders"

  composition_lines="$(wc -l < "$composition" | tr -d ' ')"
  if (( composition_lines > 320 )); then
    printf 'error: extension bridge composition grew beyond assembly duties (%s > 320 LOC)\n' \
      "$composition_lines" >&2
    status=1
  fi
fi

mutation_factory_lines="$(wc -l < "$requested_tab_mutation_factory" | tr -d ' ')"
if (( mutation_factory_lines > 150 )); then
  printf 'error: requested Tab mutation factory grew beyond assembly duties (%s > 150 LOC)\n' \
    "$mutation_factory_lines" >&2
  status=1
fi

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo "extension browser bridge architecture boundary passed"
