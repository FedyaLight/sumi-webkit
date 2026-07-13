#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

old='Sumi/Managers/ExtensionManager/ExtensionControllerAttachmentOwner.swift'
old_runtime_bundle='Sumi/Managers/ExtensionManager/ExtensionRuntimeBundle.swift'
old_window_owner='Sumi/Managers/ExtensionManager/ExtensionWindowFocusResolutionOwner.swift'
query='Sumi/Managers/ExtensionManager/ExtensionNormalTabPublicationQueries.swift'
residence='Sumi/Managers/ExtensionManager/ExtensionExactTabWebViewQuery.swift'
admission='Sumi/Managers/ExtensionManager/ExtensionWebViewControllerAdmission.swift'
repair='Sumi/Managers/ExtensionManager/ExtensionTabWebViewRuntimeRepair.swift'
assembler='Sumi/Managers/ExtensionManager/ExtensionControllerRuntimeAssembler.swift'
resolver='Sumi/Managers/ExtensionManager/ExtensionTabWebViewResolver.swift'
provisioning='Sumi/Managers/ExtensionManager/ExtensionControllerProvisioningOwner.swift'
requested_materializer='Sumi/Managers/ExtensionManager/ExtensionRequestedTabWebViewMaterializer.swift'
cold_preparation='Sumi/Managers/ExtensionManager/ExtensionWebViewConfigurationPreparation.swift'
live_preparation='Sumi/Managers/ExtensionManager/ExtensionLiveWebViewRuntimePreparation.swift'
bridge='Sumi/Managers/ExtensionManager/ExtensionBridge.swift'
browser_composition='Sumi/Managers/BrowserManager/BrowserExtensionBridgeComposition.swift'
browser_runtime_factory='Sumi/Managers/BrowserManager/BrowserExtensionManagerRuntimeFactory.swift'
runtime_demand='Sumi/Managers/ExtensionManager/ExtensionRuntimeDemandCoordinator.swift'
runtime_attachment='Sumi/Managers/ExtensionManager/ExtensionManager+BrowserRuntimeAttachment.swift'
action_surface='Sumi/Managers/ExtensionManager/ExtensionActionSurfacePublisher.swift'
runtime_publication='Sumi/Managers/ExtensionManager/ExtensionManager+RuntimePublication.swift'

status=0

if [[ -e "$old" ]]; then
  echo 'error: extension controller attachment god-object returned' >&2
  status=1
fi
for retired_surface in "$old_runtime_bundle" "$old_window_owner"; do
  if [[ -e "$retired_surface" ]]; then
    echo "error: eager extension runtime aggregate returned: $retired_surface" >&2
    status=1
  fi
done
if rg -n '\bExtensionRuntimeBundle\b|\bExtensionWindowFocusResolutionOwner\b|\bruntimeBundle\b' \
    Sumi/Managers/ExtensionManager SumiTests >/dev/null; then
  echo 'error: eager extension runtime aggregate or Owner surface returned' >&2
  status=1
fi
old_symbol_hits="$(
  rg -n '\bExtensionControllerAttachmentOwner\b' Sumi || true
)"
if [[ -n "$old_symbol_hits" ]]; then
  printf 'error: production still references the deleted controller god-object:\n%s\n' \
    "$old_symbol_hits" >&2
  status=1
fi

roles=("$query" "$residence" "$admission" "$repair" "$assembler" "$resolver")
for role in "${roles[@]}"; do
  if [[ ! -f "$role" ]]; then
    echo "error: extension controller runtime role missing: $role" >&2
    status=1
  fi
done

if (( status != 0 )); then
  exit "$status"
fi

role_reachthrough="$(
  rg -n '\bExtensionManager(Runtime)?\b|\bBrowserManager\b|\bstruct (Dependencies|Actions)\b|\bclass [A-Za-z0-9_]*Owner\b' \
    "${roles[@]}" || true
)"
if [[ -n "$role_reachthrough" ]]; then
  printf 'error: extension controller role reached through a manager/bag/Owner:\n%s\n' \
    "$role_reachthrough" >&2
  status=1
fi

owner_storage_hits="$(
  rg -n -P '^\s*(private\s+)?(weak\s+)?(var|let)\s+\w+\s*:\s*(any\s+)?[A-Za-z0-9_]+Owner\??\s*$|^\s+\w+\s*:\s*(any\s+)?[A-Za-z0-9_]+Owner[?,]?\s*$' \
    "${roles[@]}" || true
)"
if [[ -n "$owner_storage_hits" ]]; then
  printf 'error: controller runtime role stores or accepts a concrete Owner:\n%s\n' \
    "$owner_storage_hits" >&2
  status=1
fi

for preparation_class in \
  'ExtensionWebViewConfigurationPreparation' \
  'ExtensionLiveWebViewRuntimePreparation'; do
  preparation_file="$cold_preparation"
  if [[ "$preparation_class" == 'ExtensionLiveWebViewRuntimePreparation' ]]; then
    preparation_file="$live_preparation"
  fi
  preparation_body="$(
    sed -n "/final class $preparation_class:/,/^}/p" "$preparation_file"
  )"
  if rg -n '\bExtensionManager(Runtime)?\b|\bBrowserManager\b|\bstruct (Dependencies|Actions)\b|\bclass [A-Za-z0-9_]*Owner\b' \
      <<<"$preparation_body" >/dev/null; then
    echo "error: WebView preparation role reached through a root/bag/Owner: $preparation_class" >&2
    status=1
  fi
done

query_body="$(sed -n '/final class ExtensionExistingExactTabControllerQuery:/,/^}/p' "$query")"
if rg -n 'ensure|provision|setController|makeExtensionController' \
    <<<"$query_body" >/dev/null; then
  echo 'error: existing-controller query can provision or mutate controllers' >&2
  status=1
fi
if ! rg -Fq 'extensionTab(for: tab.id) === tab' <<<"$query_body"; then
  echo 'error: existing-controller query lacks exact canonical Tab proof' >&2
  status=1
fi

if ! rg -Fq 'extensionTab(for: tab.id) === tab' "$residence"; then
  echo 'error: WebView residence query lacks exact canonical Tab proof' >&2
  status=1
fi
if ! rg -Fq 'owningTab === tab' "$residence"; then
  echo 'error: WebView residence query lacks exact physical WebView ownership proof' >&2
  status=1
fi

if ! rg -Fq 'extensionTab(for: tab.id) === tab' "$admission" \
    || ! rg -Fq 'owningTab === tab' "$admission" \
    || ! rg -Fq 'webViews?.contains(webView, for: tab) == true' "$admission"; then
  echo 'error: controller admission can accept a stale Tab or foreign WebView' >&2
  status=1
fi
if rg -Fq 'ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner' \
    "$admission"; then
  echo 'error: controller admission stores the concrete compatibility prelude owner' >&2
  status=1
fi
late_bind_hits="$(
  rg -n -P 'canLateBindController|webView\.configuration\.webExtensionController\s*=(?!=)' \
    Sumi/Managers/ExtensionManager || true
)"
if [[ -n "$late_bind_hits" ]]; then
  printf 'error: impossible post-construction WebKit controller mutation returned:\n%s\n' \
    "$late_bind_hits" >&2
  status=1
fi

aggregate_protocol_hits="$(
  rg -n 'protocol ExtensionControllerBinding(Query)?\b|\bExtensionControllerBinding(Query)?\b' \
    Sumi/Managers/ExtensionManager || true
)"
if [[ -n "$aggregate_protocol_hits" ]]; then
  printf 'error: deleted aggregate controller binding capability returned:\n%s\n' \
    "$aggregate_protocol_hits" >&2
  status=1
fi

if rg -n 'updateWebViewsForProfile|reconcile(Profile|WebViews)' "$provisioning" >/dev/null; then
  echo 'error: controller provisioning can synchronously re-enter profile reconciliation' >&2
  status=1
fi
if rg -n 'reconcile(Profile)?|runtimeReconciler' "$runtime_demand" >/dev/null; then
  echo 'error: extension runtime demand can synchronously re-enter reconciliation' >&2
  status=1
fi
reload_body="$(
  sed -n '/func reloadRuntimePublications(/,/^    }/p' \
    "$runtime_publication"
)"
if ! rg -Fq 'guard attachedBrowserManager != nil' <<<"$reload_body" \
    || ! rg -Fq 'controllerRuntimeComposition != nil' <<<"$reload_body"; then
  echo 'error: cold install/enable can materialize browser runtime publication' >&2
  status=1
fi
for attached_admission in \
  'Sumi/Managers/ExtensionManager/ExtensionControllerDelegateBridge.swift' \
  'Sumi/Managers/ExtensionManager/ExtensionWindowRequestRouter.swift'; do
  if ! rg -Fq 'attachedBrowserManager != nil' "$attached_admission"; then
    echo "error: stale browser attachment remains admitted: $attached_admission" >&2
    status=1
  fi
done
strong_runtime_root_hits="$(
  rg -n 'let (ownershipQuery|rebuild|websiteDataCleanup) = browserManager|\[(ownershipQuery|rebuild|websiteDataCleanup)\]' \
    "$browser_runtime_factory" || true
)"
if [[ -n "$strong_runtime_root_hits" ]]; then
  printf 'error: extension runtime retains browser WebView services:\n%s\n' \
    "$strong_runtime_root_hits" >&2
  status=1
fi
attach_body="$(
  sed -n '/func attach(browserManager: BrowserManager)/,/^    }/p' \
    "$runtime_attachment"
)"
if ! rg -Fq 'controllerRuntimeComposition == nil' <<<"$attach_body" \
    || ! rg -Fq 'attachedBrowserManager === browserManager' \
      <<<"$attach_body"; then
  echo 'error: controller runtime attachment can silently replace live role graphs' >&2
  status=1
fi
if rg -Fq 'traceNativeMessagingContextBinding' \
    "$cold_preparation" "$live_preparation"; then
  echo 'error: split WebView preparation contains dead manager-less tracing' >&2
  status=1
fi

for old_surface in \
  'func extensionController(for tab:' \
  'func tabMatchesExtensionContext(' \
  'func resolvedLiveWebView(for tab:' \
  'func ownedUntrackedCurrentWebView(for tab:' \
  'func attachExtensionControllerIfNeeded(' \
  'func ensureExtensionControllerAttachedForTab(' \
  'updateWebViewsForProfile'; do
  hits="$(rg -n -F "$old_surface" Sumi/Managers/ExtensionManager || true)"
  if [[ -n "$hits" ]]; then
    printf 'error: deleted controller capability returned (%s):\n%s\n' \
      "$old_surface" "$hits" >&2
    status=1
  fi
done

for old_facade in \
  'func extensionController(for tab:' \
  'func tabMatchesExtensionContext(' \
  'func resolvedLiveWebView(for tab:' \
  'func ownedUntrackedCurrentWebView(for tab:' \
  'func attachExtensionControllerIfNeeded(' \
  'func ensureExtensionControllerAttachedForTab(' \
  'func webViewNeedsExtensionRuntimeRebuild(' \
  'func updateWebViewsForProfile('; do
  hits="$(rg -n -F "$old_facade" Sumi/Managers/ExtensionManager/ExtensionManager*.swift || true)"
  if [[ -n "$hits" ]]; then
    printf 'error: deleted controller manager facade returned (%s):\n%s\n' \
      "$old_facade" "$hits" >&2
    status=1
  fi
done

if (( $(rg -Fc 'tabs?.extensionTab(for: tab.id) === tab' "$repair") < 2 )); then
  echo 'error: repair/reconcile roles lack exact physical Tab proofs' >&2
  status=1
fi
if ! rg -Fq 'rebuildExtensionLiveWebViews(' "$repair"; then
  echo 'error: runtime repair lost its explicit browser rebuild port' >&2
  status=1
fi
if rg -n '\.didCommit' \
    "$bridge" "$repair" "$browser_composition" >/dev/null; then
  echo 'error: extension rebuild boundary flattened typed submission state to Bool' >&2
  status=1
fi
rebuild_protocol_body="$(
  sed -n '/protocol ExtensionTabWebViewRebuilding:/,/^}/p' "$bridge"
)"
rebuild_adapter_body="$(
  sed -n '/func rebuildExtensionLiveWebViews(/,/^    }/p' \
    Sumi/Managers/ExtensionManager/BrowserExtensionWebViewAdapter.swift
)"
for rebuild_body in "$rebuild_protocol_body" "$rebuild_adapter_body"; do
  if ! rg -Fq ') -> ExtensionTabWebViewRebuildSubmissionOutcome' \
      <<<"$rebuild_body"; then
    echo 'error: extension rebuild boundary lost its typed submission outcome' >&2
    status=1
  fi
done
for rebuild_case in committed deferred noLiveWindows failed; do
  if ! rg -Fq "case .$rebuild_case" "$browser_composition"; then
    echo "error: browser bridge does not map rebuild result: $rebuild_case" >&2
    status=1
  fi
done

if ! rg -Fq 'resolveProfileID: @MainActor (UUID?) -> UUID?' \
    "$cold_preparation"; then
  echo 'error: cold configuration preparation lacks narrow profile resolver' >&2
  status=1
fi
if ! rg -Fq 'requestRuntime: @MainActor (UUID) -> Void' \
    "$cold_preparation"; then
  echo 'error: cold configuration demand does not preserve its resolved profile' >&2
  status=1
fi
if rg -n '\(\) -> ExtensionManagerRuntime|ExtensionControllerProvisioningOwner' \
    "$cold_preparation" >/dev/null; then
  echo 'error: cold configuration preparation stores a broad runtime/concrete owner' >&2
  status=1
fi
if rg -n '\bstruct (Dependencies|Actions)\b|installPreludes\(' \
    "$live_preparation" >/dev/null; then
  echo 'error: live WebView preparation regained a closure bag or foreign prelude mutation' >&2
  status=1
fi
if rg -n '\bfunc bind\b|\brepair\?*\.repair\(' \
    "$live_preparation" >/dev/null \
    || ! rg -Fq 'tabRegistration: ExtensionNormalTabRegistration' \
      "$live_preparation"; then
  echo 'error: live WebView preparation regained two-phase or fallback repair wiring' >&2
  status=1
fi

prepared_candidate_body="$(
  sed -n '/private func preparedNormalTabWebViewIsUsable(/,/^    }/p' \
    "$requested_materializer"
)"
if [[ -z "$prepared_candidate_body" ]] \
    || ! rg -Fq 'webViews.isCanonical(tab)' <<<"$prepared_candidate_body" \
    || ! rg -Fq 'owningTab === tab' <<<"$prepared_candidate_body" \
    || ! rg -Fq 'webView.configuration.webExtensionController === controller' \
      <<<"$prepared_candidate_body"; then
  echo 'error: requested replacement lacks exact pre-commit construction proof' >&2
  status=1
fi
if rg -n 'controllerAdmission\.admit|webViews\.contains' \
    <<<"$prepared_candidate_body" >/dev/null; then
  echo 'error: pre-commit candidate validation incorrectly requires committed residence' >&2
  status=1
fi

composition_fields="$(
  sed -n '/struct ExtensionControllerRuntimeComposition {/,/^}/p' "$assembler" \
    | rg -c '^    let ' || true
)"
composition_fields="${composition_fields:-0}"
if (( composition_fields > 9 )); then
  echo "error: controller lifetime composition grew beyond 9 leaves ($composition_fields)" >&2
  status=1
fi
if ! rg -Fq 'let tabWebViewResolver: ExtensionTabWebViewResolver' "$assembler" \
    || rg -n 'tabWebViewResolver.*!' \
      Sumi/Managers/ExtensionManager/ExtensionManager.swift >/dev/null; then
  echo 'error: unattached Tab WebView projection is no longer a safe read-only capability' >&2
  status=1
fi
if ! rg -Fq 'manager?.attachedBrowserManager != nil' "$action_surface" \
    || ! rg -Fq 'manager?.controllerRuntimeComposition != nil' \
      "$action_surface"; then
  echo 'error: cold extension load can materialize browser publication roles before attachment' >&2
  status=1
fi
if ! rg -Fq 'guard attachedBrowserManager != nil' \
    Sumi/Managers/ExtensionManager/ExtensionWindowRequestRouter.swift \
    || ! rg -Fq 'controllerRuntimeComposition != nil' \
      Sumi/Managers/ExtensionManager/ExtensionWindowRequestRouter.swift \
    || ! rg -Fq 'ExtensionWindowVisibilityResolver(manager: self)' \
      Sumi/Managers/ExtensionManager/ExtensionManager.swift; then
  echo 'error: attached-only extension window graph can materialize on a cold manager' >&2
  status=1
fi
if ! rg -Fq 'guard manager.attachedBrowserManager != nil' \
    Sumi/Managers/ExtensionManager/ExtensionControllerDelegateBridge.swift \
    || ! rg -Fq 'manager.controllerRuntimeComposition != nil' \
      Sumi/Managers/ExtensionManager/ExtensionControllerDelegateBridge.swift; then
  echo 'error: cold extension Tab callback can materialize browser publication roles' >&2
  status=1
fi

composition_refs="$(
  rg -l 'ExtensionControllerRuntimeComposition' Sumi | wc -l | tr -d ' '
)"
if (( composition_refs > 2 )); then
  echo "error: controller lifetime composition escaped assembler/store boundary ($composition_refs files)" >&2
  status=1
fi
if rg -n '\brequiredControllerRuntime\b' Sumi >/dev/null; then
  echo 'error: aggregate controller runtime capability escaped composition' >&2
  status=1
fi

if ! sed -n '/final class ExtensionPreparedNormalTabQuery/,/^}/p' "$query" \
    | rg -Fq 'tab.isEphemeral == false'; then
  echo 'error: normal prepared-Tab query no longer rejects ephemeral Tabs' >&2
  status=1
fi

for required_test in \
  testExistingExactControllerQueryAllowsCanonicalEphemeralAuxiliaryTab \
  testExistingExactControllerQueryRejectsStaleSameIDEphemeralTab \
  testRuntimeRepairPreservesCommittedSubmissionOutcome \
  testRuntimeRepairPreservesDeferredSubmissionOutcome \
  testRuntimeRepairPreservesNoLiveWindowsSubmissionOutcome \
  testRuntimeRepairPreservesFailedSubmissionOutcome \
  testRuntimeRepairDoesNotClearSameIDReplacementAfterSubmission \
  testRuntimeRepairPreservesReentrantNewerOpenOnSameTab \
  testRuntimeRepairPreservesReentrantWindowPrepublicationOnSameTab \
  testLivePreparationSubmitsOneRepairThroughBoundRegistration \
  testReadyConfigurationDemandDoesNotReenterWebViewReconciliation \
  testRepeatedAttachmentToSameBrowserKeepsControllerRuntimeIdentity \
  testColdExtensionRequestedWindowFailsWithoutMaterializingBrowserRuntime \
  testExtensionWebViewReturnsNilWithoutControllerOnLoadedPage \
  testExtensionWebViewRejectsCrossProfileContext; do
  if ! rg -Fq "func $required_test" SumiTests; then
    echo "error: controller runtime regression missing: $required_test" >&2
    status=1
  fi
done

for rebuild_case in committed deferred noLiveWindows failed; do
  case "$rebuild_case" in
    committed) test_suffix='Committed' ;;
    deferred) test_suffix='Deferred' ;;
    noLiveWindows) test_suffix='NoLiveWindows' ;;
    failed) test_suffix='Failed' ;;
  esac
  test_body="$(
    sed -n "/func testRuntimeRepairPreserves${test_suffix}SubmissionOutcome()/,/^    }/p" \
      SumiTests/ExtensionControllerRuntimeBoundaryTests.swift
  )"
  if ! rg -Fq "assertRepairInvalidatesPublication(for: .$rebuild_case)" \
      <<<"$test_body"; then
    echo "error: typed rebuild test does not exercise .$rebuild_case" >&2
    status=1
  fi
done

repair_fixture_body="$(
  sed -n '/private func assertRepairInvalidatesPublication(/,/^    }/p' \
    SumiTests/ExtensionControllerRuntimeBoundaryTests.swift
)"
for proof in \
  'let tabPublicationRevisions =' \
  'let runtimeLoadStatus = ExtensionRuntimeLoadStatusAuthority()' \
  'runtimeLoadStatus.markExtensionsLoaded()' \
  'establishSettledOpen(' \
  'repair.repair('; do
  if ! rg -Fq "$proof" <<<"$repair_fixture_body"; then
    echo "error: rebuild outcome fixture lacks coherent runtime proof: $proof" >&2
    status=1
  fi
done
if rg -Fq 'allowWhenExtensionsNotLoaded: true' <<<"$repair_fixture_body"; then
  echo 'error: rebuild outcome fixture bypasses live-runtime admission' >&2
  status=1
fi

cold_test_body="$(
  sed -n \
    '/func testPrepareWebViewConfigurationAlignsWebsiteDataStoreWithProfile()/,/^    }/p' \
    SumiTests/SafariExtensionRuntimeDataStoreTests.swift
)"
if (( $(rg -Fc 'XCTAssertNil(manager.controllerRuntimeComposition)' \
    <<<"$cold_test_body") < 2 )); then
  echo 'error: cold configuration preparation regression lacks no-attach proof' >&2
  status=1
fi

cold_context_test_body="$(
  sed -n \
    '/func testExtensionWebViewReturnsNilWithoutControllerOnLoadedPage()/,/^    }/p' \
    SumiTests/SafariExtensionWebViewControllerWiringTests.swift
)"
for proof in \
  'XCTAssertTrue(extensionContext.isLoaded)' \
  'XCTAssertNil(manager.controllerRuntimeComposition)' \
  'XCTAssertNil(manager.runtimePublicationComposition)' \
  'XCTAssertNil(manager.normalTabRuntimeComposition)'; do
  if ! rg -Fq "$proof" <<<"$cold_context_test_body"; then
    echo "error: cold context-load regression lacks zero-cost proof: $proof" >&2
    status=1
  fi
done
if rg -Fq 'requestExtensionRuntime(' <<<"$cold_test_body" \
    || ! rg -Fq 'XCTAssertNil(manager.extensionController)' \
      <<<"$cold_test_body" \
    || ! rg -Fq 'XCTAssertNotNil(manager.extensionController)' \
      <<<"$cold_test_body"; then
  echo 'error: cold configuration regression pre-provisions runtime or lacks provision proof' >&2
  status=1
fi

repeated_attach_body="$(
  sed -n \
    '/func testRepeatedAttachmentToSameBrowserKeepsControllerRuntimeIdentity()/,/^    }/p' \
    SumiTests/SafariExtensionRuntimeDataStoreTests.swift
)"
if (( $(rg -Fc 'XCTAssertIdentical(' <<<"$repeated_attach_body") < 9 )); then
  echo 'error: repeated attachment regression does not freeze every controller leaf identity' >&2
  status=1
fi

materializer_body="$(
  sed -n '/struct ExtensionRequestedTabWebViewMaterializer {/,/^}/p' \
    "$requested_materializer"
)"
retired_runtime_session='ExtensionRuntime''Session'
if rg -n "$retired_runtime_session|runtimeSession|ExtensionRuntime[A-Za-z]+Authority" \
    <<<"$materializer_body" \
    || rg -Fq 'preconditionFailure(' <<<"$materializer_body"; then
  echo 'error: retained requested-Tab materializer regained aggregate runtime authority' >&2
  status=1
fi

retained_materializer_test="$(
  sed -n \
    '/func testRetainedNormalTabLeafCollaboratorsDoNotRetainManager()/,/^    }/p' \
    SumiTests/ExtensionNormalTabRuntimeAdversarialTests.swift
)"
for proof in \
  'let materializer = composition.requestedTabWebViewMaterializer' \
  'manager = nil' \
  'materializer.materializeNormalTabIfNeeded(' \
  'XCTAssertNil(materializerProbe.resolvedCurrentWebView())'; do
  if ! rg -Fq "$proof" <<<"$retained_materializer_test"; then
    echo "error: retained materializer behavior regression lacks proof: $proof" >&2
    status=1
  fi
done

if ! rg -Fq 'openPublicationInvalidationWitness()' "$repair" \
    || ! rg -Fq 'preparedTokenIdentity' \
      Sumi/Models/Tab/TabExtensionPageRuntimeOwner.swift \
    || ! rg -Fq 'preparedTokenPhase' \
      Sumi/Models/Tab/TabExtensionPageRuntimeOwner.swift; then
  echo 'error: runtime repair lacks exact open/prepublication invalidation authority' >&2
  status=1
fi

role_caps=(
  "$residence:110" "$admission:145" "$repair:270" "$assembler:135"
  "$cold_preparation:115" "$live_preparation:135"
)
for role_cap in "${role_caps[@]}"; do
  role="${role_cap%:*}"
  cap="${role_cap##*:}"
  lines="$(wc -l < "$role" | tr -d ' ')"
  if (( lines > cap )); then
    echo "error: $role grew beyond $cap LOC ($lines)" >&2
    status=1
  fi
done

if (( status != 0 )); then
  exit "$status"
fi
echo 'extension controller runtime boundary passed'
