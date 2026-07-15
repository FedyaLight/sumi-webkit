#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bridge='Sumi/Managers/ExtensionManager/ExtensionControllerDelegateBridge.swift'
opening='Sumi/Managers/ExtensionManager/ExtensionControllerOpeningCallbackHandler.swift'
opening_runtime='Sumi/Managers/ExtensionManager/ExtensionControllerOpeningCallbackRuntime.swift'
initial='Sumi/Managers/ExtensionManager/ExtensionInitialDocumentRuntimePreparationOwner.swift'
content='Sumi/Managers/ExtensionManager/ExtensionContentScriptContextPreparationOwner.swift'
native='Sumi/Managers/ExtensionManager/ExtensionInitialDocumentNativeMessagingWarmupOwner.swift'
residency='Sumi/Managers/ExtensionManager/ExtensionContextResidencyOwner.swift'
retention='Sumi/Managers/ExtensionManager/ExtensionContextRetentionOwner.swift'
loading='Sumi/Managers/ExtensionManager/ExtensionContextLoadingOwner.swift'
settlement='Sumi/Managers/ExtensionManager/ExtensionContextSettlementOwner.swift'
deferred='Sumi/Managers/ExtensionManager/ExtensionDeferredRuntimeOwnerStore.swift'

weak_events='Sumi/AuxiliaryWindows/WeakAuxiliaryWindowExtensionEvents.swift'
browser_aux='Sumi/AuxiliaryWindows/BrowserAuxiliaryWindowComposition.swift'
session_registry='Sumi/AuxiliaryWindows/AuxiliaryWindowSessionRegistry.swift'
teardown='Sumi/AuxiliaryWindows/AuxiliaryWindowTeardownService.swift'
ui_delegate='Sumi/AuxiliaryWindows/AuxiliaryWindowUIDelegate.swift'
extension_opening='Sumi/AuxiliaryWindows/ExtensionAuxiliaryWindowOpeningService.swift'
popup_opening='Sumi/AuxiliaryWindows/AuxiliaryPopupOpeningService.swift'
extension_bridge='Sumi/Managers/ExtensionManager/ExtensionBridge.swift'
state_coordinator='Sumi/Managers/ExtensionManager/ExtensionWindowStateTransitionCoordinator.swift'
manager_support='Sumi/Managers/ExtensionManager/ExtensionManagerSupport.swift'
extension_control='Sumi/Managers/ExtensionManager/BrowserExtensionAuxiliaryWindowAdapter.swift'
tab_commands='Sumi/Managers/ExtensionManager/ExtensionTabCommandMutation.swift'
presentation='Sumi/AuxiliaryWindows/AuxiliaryWindowPresentationService.swift'
page_resolution='Sumi/Managers/ExtensionManager/ExtensionPageResolutionOwner.swift'
window_presentation='Sumi/Managers/ExtensionManager/BrowserExtensionWindowPresentationAdapter.swift'
close_router='Sumi/Managers/BrowserManager/BrowserWebViewCloseRouter.swift'
permission_runtime='Sumi/Managers/BrowserManager/TabBrowserHostServicesRuntimeFactory.swift'
compact_window='Sumi/Components/Window/AuxiliaryCompactWindow.swift'
window_router='Sumi/Managers/ExtensionManager/ExtensionWindowRequestRouter.swift'
receipt_tests='SumiTests/AuxiliaryWindowReceiptABATests.swift'
state_tests='SumiTests/AuxiliaryWindowStateTransitionTests.swift'

for file in "$bridge" "$opening" "$opening_runtime" "$initial" "$content" "$native" \
  "$residency" "$retention" "$loading" "$settlement" "$deferred" \
  "$weak_events" "$browser_aux" "$session_registry" "$teardown" \
  "$ui_delegate" "$extension_opening" "$popup_opening" "$extension_bridge" \
  "$state_coordinator" "$manager_support" \
  "$extension_control" "$tab_commands" "$presentation" \
  "$page_resolution" "$window_presentation" "$close_router" \
  "$permission_runtime" "$compact_window" "$window_router" \
  "$receipt_tests" "$state_tests"; do
  [[ -f "$file" ]] || { echo "error: missing extension auxiliary role: $file" >&2; exit 1; }
done

if rg -n 'Task \{' "$bridge"; then
  echo 'error: controller delegate bridge regained asynchronous opening transactions' >&2
  exit 1
fi
rg -q 'ExtensionControllerOpeningCallbackHandler' "$bridge"
rg -q 'runtime\.contextPreloader\.prepare' "$opening"
rg -q 'presentExtensionPopupWindow' "$opening"
rg -q 'ExtensionControllerCallbackEvidence' "$opening"
rg -q 'admission\.isCurrent' "$opening"
rg -q 'hasUnresolvedExtensionOwnership == false' "$opening"
rg -q 'ExtensionPopupWindowPresentationReceipt' \
  "$extension_bridge"
rg -q 'presentation\?\.retire\(\)' "$opening"
rg -q 'struct AuxiliaryWindowSessionReceipt: Hashable' "$session_registry"
rg -Fq 'fileprivate init(session: AuxiliaryWindowSession)' "$session_registry"
rg -q 'let sessionIdentity: ObjectIdentifier' "$session_registry"
rg -q 'let webViewIdentity: ObjectIdentifier' "$session_registry"
rg -Fq 'guard isCurrent(receipt),' "$session_registry"
rg -Fq 'sessions.remove(receipt)' "$teardown"
if rg -U -n \
  'func (teardown|receipt|remove)\(\s*(for )?webView|closeAuxiliaryWindowWebView|containsAuxiliaryWebView|closeAuxiliaryWindowSession\(\s*_ session:|recordAuxiliaryWindowSessionFocus\(\s*_ sessionId:|focusAuxiliaryWindowSession\(\s*_ sessionId:' \
  "$session_registry" "$teardown" "$extension_control" "$extension_bridge" \
  "$tab_commands" "$close_router"; then
  echo 'error: auxiliary destructive/focus control regained mutable WebView, session, or UUID authority' >&2
  exit 1
fi
rg -Uq 'protocol ExtensionAuxiliaryTabClosing[^}]+auxiliaryWindowSessionReceipt[^}]+closeAuxiliaryWindowSession\(\s*_ receipt: AuxiliaryWindowSessionReceipt' \
  "$extension_bridge"
rg -Fq 'miniWindowAdapter?.bind(receipt)' "$presentation"
rg -Fq 'private var sessionReceipt: AuxiliaryWindowSessionReceipt?' \
  "$extension_bridge"
rg -Fq 'func bind(_ receipt: AuxiliaryWindowSessionReceipt)' \
  "$extension_bridge"
rg -Fq 'auxiliaryWindows?.focusAuxiliaryWindowSession(sessionReceipt)' \
  "$extension_bridge"
rg -Fq 'private let stateTransitions = ExtensionWindowStateTransitionCoordinator(' \
  "$extension_bridge"
rg -Fq 'stateTransitions.transition(' "$extension_bridge"
rg -Fq 'self.sessionReceipt == expectedReceipt' "$extension_bridge"
rg -Fq 'ObjectIdentifier(current) == sessionIdentity' "$extension_bridge"
rg -Fq 'current.window === window' "$extension_bridge"
rg -Fq 'isRetired = true' "$extension_bridge"
rg -Fq 'stateTransitions.invalidateActiveTransition()' "$extension_bridge"
rg -Uq 'isRetired = true[[:space:]]+stateTransitions\.invalidateActiveTransition\(\)[[:space:]]+auxiliaryWindows\.closeAuxiliaryWindowSession\(sessionReceipt\)' \
  "$extension_bridge"
rg -Fq 'if window.isZoomed { return .maximized }' "$extension_bridge"
rg -Fq 'previous.ownsWindow(with: windowIdentity)' "$state_coordinator"
rg -Fq 'admissionGeneration == requestGeneration' "$state_coordinator"
rg -Fq 'ObjectIdentifier(window) == windowIdentity' "$state_coordinator"
rg -Fq 'guard self?.active?.id == finishedID else { return }' \
  "$state_coordinator"
for notification in didMiniaturize didDeminiaturize didEnterFullScreen \
  didExitFullScreen didResize; do
  rg -Fq "NSWindow.${notification}Notification" "$state_coordinator"
done
rg -Fq 'object: window' "$state_coordinator"
rg -Fq 'settlement.isSatisfied(by: window)' "$state_coordinator"
rg -Fq 'window.isZoomed == expected' "$state_coordinator"
rg -Fq 'action?(window)' "$state_coordinator"
rg -Uq 'action\?\(window\)[[:space:]]+guard validateCurrentWindow\(\) else' \
  "$state_coordinator"
rg -Fq 'closeObservation?.invalidate()' "$state_coordinator"
rg -Fq 'settlementObservation?.invalidate()' "$state_coordinator"
rg -Fq 'deinit {' "$state_coordinator"
rg -Fq 'removeObservers()' "$state_coordinator"
rg -Uq 'didComplete = true[[:space:]]+removeObservers\(\)[[:space:]]+let completion = self\.completion[[:space:]]+self\.completion = nil[[:space:]]+didFinish\(id\)[[:space:]]+completion\?\(error\)' \
  "$state_coordinator"
rg -Fq 'miniWindowStateTransitionSuperseded' "$manager_support"
rg -Fq 'miniWindowStateTransitionInvalidated' "$manager_support"
if rg -n 'Timer|asyncAfter|sleep\(|usleep\(|poll' "$state_coordinator"; then
  echo 'error: mini-window state settlement regained timers, sleeps, or polling' >&2
  exit 1
fi
rg -q 'testMiniWindowAdapterFocusRejectsReplacementDuringOrderFront' \
  "$receipt_tests"
rg -q 'testMiniWindowAdapterSetFrameRejectsReplacementDuringResize' \
  "$receipt_tests"
rg -q 'testMiniWindowAdapterSetStateRejectsReplacementDuringMiniaturize' \
  "$receipt_tests"
rg -Fq 'target.window.observe(' "$receipt_tests"
rg -Fq '\.isVisible' "$receipt_tests"
rg -Fq 'change.oldValue == false' "$receipt_tests"
rg -Fq 'change.newValue == true' "$receipt_tests"
rg -Fq 'NSWindow.willMiniaturizeNotification' "$receipt_tests"
rg -Fq 'NSWindow.didMiniaturizeNotification' "$receipt_tests"
rg -q 'testMiniWindowAdapterSetStateCompletesAfterExactNativeSettlement' \
  "$state_tests"
rg -q 'testMiniWindowAdapterStateSupersessionSequencesNativeSettlement' \
  "$state_tests"
rg -q 'testMiniWindowAdapterCloseInvalidatesActiveStateExactlyOnce' \
  "$state_tests"
rg -Fq 'replacementObservedMiniaturize' "$state_tests"
rg -Fq 'replacementObservedDeminiaturize' "$state_tests"
rg -Fq 'assertForOverFulfill = true' "$state_tests"
rg -q 'testAuxiliaryPermissionContextsRejectWrongDataStoreWithoutBridgeEffects' \
  "$receipt_tests"
rg -q '\.miniaturizable' "$compact_window"
rg -Fq '$0.performMiniaturize(nil)' "$state_coordinator"
rg -Uq 'trackedOwner\([[:space:]]+containing: webView[[:space:]]+\)[[:space:]]+\{' \
  "$permission_runtime"
rg -Fq 'isAuxiliaryMiniWindowTab(sourceTab)' "$permission_runtime"
rg -Fq 'webViewRoutingService.ownsLiveWebView' "$permission_runtime"
rg -Fq 'let profileID = sourceTab.profileId' "$permission_runtime"
rg -Fq 'profile.id == profileID' "$permission_runtime"
rg -Fq 'sumiIsNormalTabWebViewConfiguration == false' "$permission_runtime"
rg -Uq 'webView\.configuration\.websiteDataStore[[:space:]]+=== profile\.dataStore' \
  "$permission_runtime"
rg -q 'let sessionReceipt = presented\.receipt' "$extension_opening"
rg -Fq 'teardown.teardown(' "$extension_opening"
rg -q 'sessionReceipt,' "$extension_opening"
if rg -U -n '\[weak session\]|teardown\.teardown\(\s*for:\s*session\.webView' \
  "$extension_opening" "$popup_opening"; then
  echo 'error: popup retirement regained mutable WebView/session lookup authority' >&2
  exit 1
fi
if rg -n 'map\(\\\.webView\)' "$teardown"; then
  echo 'error: bulk auxiliary teardown must snapshot exact receipts, not WebViews' >&2
  exit 1
fi
rg -q 'sessions\.sessionsSnapshot\(\)\.compactMap' "$teardown"
rg -q 'sessions\.sessions\(forExtensionID: extensionID\)' "$teardown"
ui_detach_lines=( $(
  rg -n 'session\.webView\.uiDelegate = nil' "$teardown" | cut -d: -f1
) )
navigation_detach_lines=( $(
  rg -n 'session\.webView\.navigationDelegate = nil' "$teardown" | cut -d: -f1
) )
stop_lines=( $(
  rg -n 'session\.webView\.stopLoading\(\)' "$teardown" | cut -d: -f1
) )
if (( ${#ui_detach_lines[@]} < 2 \
      || ${#navigation_detach_lines[@]} < 2 \
      || ${#stop_lines[@]} < 2 )); then
  echo 'error: both auxiliary teardown paths must detach WebKit delegates before stopping loads' >&2
  exit 1
fi
for index in 0 1; do
  if (( ui_detach_lines[index] >= stop_lines[index] \
        || navigation_detach_lines[index] >= stop_lines[index] )); then
    echo 'error: auxiliary teardown can reenter a delegate after retirement began' >&2
    exit 1
  fi
done
if rg -n 'session\(for: webView\)|webView\.window' "$ui_delegate"; then
  echo 'error: auxiliary UI delegate regained mutable WebView lookup authority' >&2
  exit 1
fi
if (( $(rg -c 'currentSession\(for: webView\)' "$ui_delegate") < 7 )); then
  echo 'error: every auxiliary UI callback and popup permission tail must revalidate its exact receipt' >&2
  exit 1
fi
rg -Fq 'let session = sessions.session(for: sessionReceipt)' "$ui_delegate"
rg -Uq 'permissionResult\.isAllowed,\s+currentSession\(for: webView\) === session' \
  "$ui_delegate"
rg -Uq 'currentPageID: currentPageID,\s+completionHandler: exactSessionCompletion' \
  "$ui_delegate"
cleanup_line="$(rg -n 'session\.tab\.performComprehensiveWebViewCleanup' \
  "$teardown" | cut -d: -f1)"
tab_remove_line="$(rg -n 'tabs\.removeMiniWindowTab' "$teardown" | cut -d: -f1)"
close_callback_line="$(rg -n 'notifyAuxiliaryWindowClosed' "$teardown" | cut -d: -f1)"
reuse_guard_line="$(rg -n 'physicalIdentityWasNotReused' "$teardown" | head -1 | cut -d: -f1)"
if [[ -z "$cleanup_line" || -z "$tab_remove_line" \
      || -z "$close_callback_line" || -z "$reuse_guard_line" ]] \
    || (( cleanup_line >= tab_remove_line \
          || tab_remove_line >= close_callback_line \
          || close_callback_line >= reuse_guard_line )); then
  echo 'error: auxiliary physical retirement must finish before the reentrant close callback and guarded focus tail' >&2
  exit 1
fi
rg -q 'load\.hasUnresolvedExtensionOwnership == false' "$window_router"
if rg -n 'auxiliaryContains|teardownAuxiliaryWebView|auxiliaryWindowSession\(for: webView\)' \
  "$close_router"; then
  echo 'error: generic WebView close routing regained auxiliary WebView authority' >&2
  exit 1
fi
rg -q 'teardownAuxiliarySessionForTab' "$close_router"
rg -Uq 'session\.tab === tab,[[:space:]]+let receipt = auxiliaryWindows\.sessions\.receipt' \
  "$close_router"
atomic_load_line="$(rg -n 'let load = loadResolver\.resolve' "$window_router" | tail -1 | cut -d: -f1)"
atomic_reject_line="$(rg -n 'load\.hasUnresolvedExtensionOwnership == false' "$window_router" | tail -2 | head -1 | cut -d: -f1)"
atomic_prepare_line="$(rg -n 'await prepare\(' "$window_router" | tail -1 | cut -d: -f1)"
if [[ -z "$atomic_load_line" || -z "$atomic_reject_line" \
      || -z "$atomic_prepare_line" ]] \
    || (( atomic_load_line >= atomic_reject_line \
          || atomic_reject_line >= atomic_prepare_line )); then
  echo 'error: unresolved extension-owned window load must fail before preload' >&2
  exit 1
fi
rg -q 'let sessionIdentity: ObjectIdentifier' "$extension_bridge"
rg -q 'let webViewIdentity: ObjectIdentifier' "$extension_bridge"
rg -q 'exactContextIdentity' "$page_resolution"
rg -q '\$0\.id == identity\.extensionId && \$0\.isEnabled' \
  "$page_resolution"
rg -q 'candidates\.dropFirst\(\)\.allSatisfy' "$page_resolution"
owner_guard_line="$(rg -n 'extensionIntegration == nil \|\| extensionID != nil' \
  "$popup_opening" | cut -d: -f1)"
external_create_line="$(rg -n 'guard let tab = tabs\.createMiniWindowTab' \
  "$popup_opening" | tail -1 | cut -d: -f1)"
if [[ -z "$owner_guard_line" || -z "$external_create_line" ]] \
    || (( owner_guard_line >= external_create_line )); then
  echo 'error: external extension popup owner evidence must fail before tab mutation' >&2
  exit 1
fi
if (( $(rg -c 'runtime\.integration\.resolveExtensionID' \
  "$extension_opening") < 2 )); then
  echo 'error: extension window owner evidence must be revalidated after awaits' >&2
  exit 1
fi
last_owner_validation_line="$(rg -n 'runtime\.integration\.resolveExtensionID' \
  "$extension_opening" | tail -1 | cut -d: -f1)"
extension_create_line="$(rg -n 'guard let tab = tabs\.createMiniWindowTab' \
  "$extension_opening" | cut -d: -f1)"
load_line="$(rg -n 'tab\.loadURL\(loadURL\)' "$extension_opening" | cut -d: -f1)"
history_line="$(rg -n 'runtime\.recentRequests\.record\(loadURL\)' \
  "$extension_opening" | cut -d: -f1)"
if [[ -z "$last_owner_validation_line" || -z "$extension_create_line" \
      || -z "$load_line" || -z "$history_line" ]] \
    || (( last_owner_validation_line >= extension_create_line \
          || load_line >= history_line )); then
  echo 'error: extension popup mutation/history escaped exact owner or completion admission' >&2
  exit 1
fi
if rg -n 'presentExtensionExternalWebPopup' \
  "$extension_bridge" "$window_presentation"; then
  echo 'error: dead external popup forwarding capability returned to extension presentation' >&2
  exit 1
fi
rg -q 'testExternalPopupRejectsInvalidOwnerEvidenceBeforeAnyMutation' \
  "$receipt_tests"
rg -q 'testFocusRestoreRejectsTargetReplacedDuringFocusCallback' \
  "$receipt_tests"
rg -q 'testStalePopupReceiptCannotRetireSameWebViewReplacementOrSibling' \
  SumiTests/AuxiliaryWindowLifecycleTests.swift
rg -q 'testPopupReceiptRetiresCurrentExactSessionAndKeepsSibling' \
  SumiTests/AuxiliaryWindowLifecycleTests.swift
rg -q 'testReentrantPopupRejectionPreservesSameWebViewReplacement' \
  SumiTests/AuxiliaryWindowLifecycleTests.swift
rg -q 'testReentrantExternalPopupRejectionPreservesSameWebViewReplacement' \
  SumiTests/AuxiliaryWindowPublicationLifecycleTests.swift
rg -q 'testBulkCloseUsesExactReceiptSnapshotAcrossSameWebViewReplacement' \
  SumiTests/AuxiliaryWindowLifecycleTests.swift
rg -q 'testStaleUIDelegateCannotActOnSameWebViewReplacement' \
  SumiTests/AuxiliaryWindowReceiptABATests.swift
rg -q 'testPopupPermissionReentrancyCannotOpenChildForReplacement' \
  SumiTests/AuxiliaryWindowReceiptABATests.swift
rg -q 'testFilePickerAsyncTailRejectsSameWebViewReplacement' \
  SumiTests/AuxiliaryWindowReceiptABATests.swift
rg -q 'testCloseCallbackReplacementKeepsSamePhysicalResources' \
  SumiTests/AuxiliaryWindowReceiptABATests.swift
rg -q 'testUnresolvedExtensionWindowFailsBeforePreparationOrMutation' \
  SumiTests/SafariExtensionWindowAndOptionsAdmissionTests.swift
rg -q 'AuxiliaryPublicationIdentityTuple' \
  SumiTests/AuxiliaryWindowPublicationLifecycleTests.swift
rg -q 'originalPublication.count, 2' \
  SumiTests/AuxiliaryWindowPublicationLifecycleTests.swift
rg -q 'unrelatedEvents.isEmpty' \
  SumiTests/AuxiliaryWindowPublicationLifecycleTests.swift
rg -q 'replacement.openWindows.isEmpty' \
  SumiTests/AuxiliaryWindowPublicationLifecycleTests.swift
rg -q 'private weak var target' "$weak_events"
rg -q 'events: WeakAuxiliaryWindowExtensionEvents' "$browser_aux"
rg -Fq 'let extensionEvents: (any AuxiliaryWindowExtensionEventHandling)?' \
  Sumi/AuxiliaryWindows/AuxiliaryWindowSessionRegistry.swift
if rg -n 'weak var extensionEvents' \
  Sumi/AuxiliaryWindows/AuxiliaryWindowSessionRegistry.swift; then
  echo 'error: auxiliary session stopped owning its weak lifetime projection' >&2
  exit 1
fi
if rg -n 'events: self' "$browser_aux" \
  Sumi/Managers/ExtensionManager/ExtensionControllerOpeningCallbackComposition.swift; then
  echo 'error: auxiliary integration regained transitive ExtensionManager retention' >&2
  exit 1
fi
rg -q 'private struct ScheduledTask' "$content"
rg -q 'tasksByProfile\[profileID\]\?\.token == token' "$content"
rg -q 'retiredTokens' "$content"
rg -q 'testCancelledContentScriptTaskCannotRemoveNewSameProfileTask' \
  SumiTests/ExtensionNativeMessagingBackgroundWakeOwnerTests.swift
rg -q 'testFullCallbackRejectsUnresolvedOwnershipBeforePreloadOrMaterialization' \
  SumiTests/ExtensionRequestedTabServicesTests.swift
rg -q 'testAuxiliaryIntegrationReceiptDoesNotRetainExtensionManager' \
  SumiTests/SafariExtensionLazyRuntimePolicyTests.swift
rg -q 'testWeakExtensionEventsFailClosedAfterEventRootDeallocation' \
  SumiTests/AuxiliaryWindowLifecycleTests.swift
rg -Fq 'target?.notifyAuxiliaryWindowOpened(session) ?? false' "$weak_events"

if rg -n 'private (weak|unowned) var manager|private unowned let manager' \
  "$initial" "$native" "$retention" "$loading" "$settlement" "$deferred"; then
  echo 'error: auxiliary role regained an ExtensionManager backreference' >&2
  exit 1
fi
if rg -n '\bExtensionManager\b|\[(weak|unowned) manager\]' \
  "$opening" "$deferred"; then
  echo 'error: exact opening/deferred roles regained an ExtensionManager root' >&2
  exit 1
fi
rg -q 'let runtimeQuery: ExtensionDeferredRuntimeQuery' "$deferred"
rg -q 'let contextLoading: ExtensionContextResidencyOwner' "$deferred"
rg -q 'let backgroundWake: ExtensionBackgroundWakeCoordinator' "$deferred"
rg -q 'deferredRuntimeOwnerStoreStorage?' \
  Sumi/Managers/ExtensionManager/ExtensionManager.swift
if rg -n '_ = deferredRuntimeOwnerStore' \
  Sumi/Managers/ExtensionManager/ExtensionManager.swift; then
  echo 'error: disabled extension runtime eagerly materializes deferred owners' >&2
  exit 1
fi
rg -Fq 'XCTAssertNil(manager.loadedInitialDocumentRuntimePreparationOwner)' \
  SumiTests/SafariExtensionLazyRuntimePolicyTests.swift
if rg -n 'struct Dependencies|dependencies\.' \
  "$residency" "$retention" "$loading" "$settlement"; then
  echo 'error: context residency closure dependency bag returned' >&2
  exit 1
fi
rg -q 'ExtensionContentScriptContextPreparationOwner' "$initial"
rg -q 'ExtensionInitialDocumentNativeMessagingWarmupOwner' "$initial"
rg -q 'let retention: ExtensionContextRetentionOwner' "$residency"
rg -q 'let loading: ExtensionContextLoadingOwner' "$residency"
rg -q 'let settlement: ExtensionContextSettlementOwner' "$residency"

for limit_and_file in \
  "320:$bridge" \
  "160:$opening" \
  "90:$opening_runtime" \
  "220:$initial" \
  "150:$content" \
  "170:$native" \
  "140:$residency" \
  "130:$retention" \
  "150:$loading" \
  "110:$settlement" \
  "180:$deferred"; do
  limit="${limit_and_file%%:*}"
  file="${limit_and_file#*:}"
  lines="$(wc -l < "$file" | tr -d ' ')"
  if (( lines > limit )); then
    printf 'error: extension auxiliary role grew beyond boundary (%s: %s > %s)\n' \
      "$file" "$lines" "$limit" >&2
    exit 1
  fi
done

echo 'extension auxiliary role boundary passed'
