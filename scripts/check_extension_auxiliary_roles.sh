#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

scan_arguments() {
  local mode="$1"
  shift
  local options=()
  while (( $# > 0 )) && [[ "$1" == -* ]]; do
    options+=("$1")
    shift
  done
  local pattern="$1"
  shift
  case "$mode" in
    capture)
      if (( ${#options[@]} > 0 )); then
        guard_capture_matches "$pattern" "${options[@]}" "$@"
      else
        guard_capture_matches "$pattern" "$@"
      fi
      ;;
    count)
      if (( ${#options[@]} > 0 )); then
        guard_count_matches "$pattern" "${options[@]}" "$@"
      else
        guard_count_matches "$pattern" "$@"
      fi
      ;;
  esac
}

capture_matches() {
  scan_arguments capture "$@"
}

count_matches() {
  scan_arguments count "$@"
}

require_matches() {
  local count
  count="$(scan_arguments count "$@")" || return
  if (( count == 0 )); then
    printf 'error: required auxiliary-window production invariant missing: %s\n' "$*" >&2
    return 1
  fi
}

scan_has_matches() {
  local count
  count="$(scan_arguments count "$@")" || exit $?
  (( count > 0 ))
}

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
for file in "$bridge" "$opening" "$opening_runtime" "$initial" "$content" "$native" \
  "$residency" "$retention" "$loading" "$settlement" "$deferred" \
  "$weak_events" "$browser_aux" "$session_registry" "$teardown" \
  "$ui_delegate" "$extension_opening" "$popup_opening" "$extension_bridge" \
  "$state_coordinator" "$manager_support" \
  "$extension_control" "$tab_commands" "$presentation" \
  "$page_resolution" "$window_presentation" "$close_router" \
  "$permission_runtime" "$compact_window" "$window_router"; do
  [[ -f "$file" ]] || { echo "error: missing extension auxiliary role: $file" >&2; exit 1; }
done

if scan_has_matches 'Task \{' "$bridge"; then
  echo 'error: controller delegate bridge regained asynchronous opening transactions' >&2
  exit 1
fi
require_matches 'ExtensionControllerOpeningCallbackHandler' "$bridge"
require_matches 'runtime\.contextPreloader\.prepare' "$opening"
require_matches 'presentExtensionPopupWindow' "$opening"
require_matches 'ExtensionControllerCallbackEvidence' "$opening"
require_matches 'admission\.isCurrent' "$opening"
require_matches 'hasUnresolvedExtensionOwnership == false' "$opening"
require_matches 'ExtensionPopupWindowPresentationReceipt' \
  "$extension_bridge"
require_matches 'presentation\?\.retire\(\)' "$opening"
require_matches 'struct AuxiliaryWindowSessionReceipt: Hashable' "$session_registry"
require_matches -F 'fileprivate init(session: AuxiliaryWindowSession)' "$session_registry"
require_matches 'let sessionIdentity: ObjectIdentifier' "$session_registry"
require_matches 'let webViewIdentity: ObjectIdentifier' "$session_registry"
require_matches -F 'guard isCurrent(receipt),' "$session_registry"
require_matches -F 'sessions.remove(receipt)' "$teardown"
if scan_has_matches -U \
  'func (teardown|receipt|remove)\(\s*(for )?webView|closeAuxiliaryWindowWebView|containsAuxiliaryWebView|closeAuxiliaryWindowSession\(\s*_ session:|recordAuxiliaryWindowSessionFocus\(\s*_ sessionId:|focusAuxiliaryWindowSession\(\s*_ sessionId:' \
  "$session_registry" "$teardown" "$extension_control" "$extension_bridge" \
  "$tab_commands" "$close_router"; then
  echo 'error: auxiliary destructive/focus control regained mutable WebView, session, or UUID authority' >&2
  exit 1
fi
require_matches -U 'protocol ExtensionAuxiliaryTabClosing[^}]+auxiliaryWindowSessionReceipt[^}]+closeAuxiliaryWindowSession\(\s*_ receipt: AuxiliaryWindowSessionReceipt' \
  "$extension_bridge"
require_matches -F 'miniWindowAdapter?.bind(receipt)' "$presentation"
require_matches -F 'private var sessionReceipt: AuxiliaryWindowSessionReceipt?' \
  "$extension_bridge"
require_matches -F 'func bind(_ receipt: AuxiliaryWindowSessionReceipt)' \
  "$extension_bridge"
require_matches -F 'auxiliaryWindows?.focusAuxiliaryWindowSession(sessionReceipt)' \
  "$extension_bridge"
require_matches -F 'private let stateTransitions = ExtensionWindowStateTransitionCoordinator(' \
  "$extension_bridge"
require_matches -F 'stateTransitions.transition(' "$extension_bridge"
require_matches -F 'self.sessionReceipt == expectedReceipt' "$extension_bridge"
require_matches -F 'ObjectIdentifier(current) == sessionIdentity' "$extension_bridge"
require_matches -F 'current.window === window' "$extension_bridge"
require_matches -F 'isRetired = true' "$extension_bridge"
require_matches -F 'stateTransitions.invalidateActiveTransition()' "$extension_bridge"
require_matches -U 'isRetired = true[[:space:]]+stateTransitions\.invalidateActiveTransition\(\)[[:space:]]+auxiliaryWindows\.closeAuxiliaryWindowSession\(sessionReceipt\)' \
  "$extension_bridge"
require_matches -F 'if window.isZoomed { return .maximized }' "$extension_bridge"
require_matches -F 'previous.ownsWindow(with: windowIdentity)' "$state_coordinator"
require_matches -F 'admissionGeneration == requestGeneration' "$state_coordinator"
require_matches -F 'ObjectIdentifier(window) == windowIdentity' "$state_coordinator"
require_matches -F 'guard self?.active?.id == finishedID else { return }' \
  "$state_coordinator"
for notification in didMiniaturize didDeminiaturize didEnterFullScreen \
  didExitFullScreen didResize; do
  require_matches -F "NSWindow.${notification}Notification" "$state_coordinator"
done
require_matches -F 'object: window' "$state_coordinator"
require_matches -F 'settlement.isSatisfied(by: window)' "$state_coordinator"
require_matches -F 'window.isZoomed == expected' "$state_coordinator"
require_matches -F 'action?(window)' "$state_coordinator"
require_matches -U 'action\?\(window\)[[:space:]]+guard validateCurrentWindow\(\) else' \
  "$state_coordinator"
require_matches -F 'closeObservation?.invalidate()' "$state_coordinator"
require_matches -F 'settlementObservation?.invalidate()' "$state_coordinator"
require_matches -F 'deinit {' "$state_coordinator"
require_matches -F 'removeObservers()' "$state_coordinator"
require_matches -U 'didComplete = true[[:space:]]+removeObservers\(\)[[:space:]]+let completion = self\.completion[[:space:]]+self\.completion = nil[[:space:]]+didFinish\(id\)[[:space:]]+completion\?\(error\)' \
  "$state_coordinator"
require_matches -F 'miniWindowStateTransitionSuperseded' "$manager_support"
require_matches -F 'miniWindowStateTransitionInvalidated' "$manager_support"
if scan_has_matches 'Timer|asyncAfter|sleep\(|usleep\(|poll' "$state_coordinator"; then
  echo 'error: mini-window state settlement regained timers, sleeps, or polling' >&2
  exit 1
fi
require_matches '\.miniaturizable' "$compact_window"
require_matches -F '$0.performMiniaturize(nil)' "$state_coordinator"
require_matches -U 'trackedOwner\([[:space:]]+containing: webView[[:space:]]+\)[[:space:]]+\{' \
  "$permission_runtime"
require_matches -F 'isAuxiliaryMiniWindowTab(sourceTab)' "$permission_runtime"
require_matches -F 'webViewRoutingService.ownsLiveWebView' "$permission_runtime"
require_matches -F 'let profileID = sourceTab.profileId' "$permission_runtime"
require_matches -F 'profile.id == profileID' "$permission_runtime"
require_matches -F 'sumiIsNormalTabWebViewConfiguration == false' "$permission_runtime"
require_matches -U 'webView\.configuration\.websiteDataStore[[:space:]]+=== profile\.dataStore' \
  "$permission_runtime"
require_matches 'let sessionReceipt = presented\.receipt' "$extension_opening"
require_matches -F 'teardown.teardown(' "$extension_opening"
require_matches 'sessionReceipt,' "$extension_opening"
if scan_has_matches -U '\[weak session\]|teardown\.teardown\(\s*for:\s*session\.webView' \
  "$extension_opening" "$popup_opening"; then
  echo 'error: popup retirement regained mutable WebView/session lookup authority' >&2
  exit 1
fi
if scan_has_matches 'map\(\\\.webView\)' "$teardown"; then
  echo 'error: bulk auxiliary teardown must snapshot exact receipts, not WebViews' >&2
  exit 1
fi
require_matches 'sessions\.sessionsSnapshot\(\)\.compactMap' "$teardown"
require_matches 'sessions\.sessions\(forExtensionID: extensionID\)' "$teardown"
ui_detach_lines=( $(
  capture_matches 'session\.webView\.uiDelegate = nil' "$teardown" | cut -d: -f1
) )
navigation_detach_lines=( $(
  capture_matches 'session\.webView\.navigationDelegate = nil' "$teardown" | cut -d: -f1
) )
stop_lines=( $(
  capture_matches 'session\.webView\.stopLoading\(\)' "$teardown" | cut -d: -f1
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
if scan_has_matches 'session\(for: webView\)|webView\.window' "$ui_delegate"; then
  echo 'error: auxiliary UI delegate regained mutable WebView lookup authority' >&2
  exit 1
fi
current_session_validation_count="$(
  count_matches 'currentSession\(for: webView\)' "$ui_delegate"
)"
if (( current_session_validation_count < 7 )); then
  echo 'error: every auxiliary UI callback and popup permission tail must revalidate its exact receipt' >&2
  exit 1
fi
require_matches -F 'let session = sessions.session(for: sessionReceipt)' "$ui_delegate"
require_matches -U 'permissionResult\.isAllowed,\s+currentSession\(for: webView\) === session' \
  "$ui_delegate"
require_matches -U 'currentPageID: currentPageID,\s+completionHandler: exactSessionCompletion' \
  "$ui_delegate"
cleanup_line="$(capture_matches 'session\.tab\.performComprehensiveWebViewCleanup' \
  "$teardown" | cut -d: -f1)"
tab_remove_line="$(capture_matches 'tabs\.removeMiniWindowTab' "$teardown" | cut -d: -f1)"
close_callback_line="$(capture_matches 'notifyAuxiliaryWindowClosed' "$teardown" | cut -d: -f1)"
reuse_guard_line="$(capture_matches 'physicalIdentityWasNotReused' "$teardown" | head -1 | cut -d: -f1)"
if [[ -z "$cleanup_line" || -z "$tab_remove_line" \
      || -z "$close_callback_line" || -z "$reuse_guard_line" ]] \
    || (( cleanup_line >= tab_remove_line \
          || tab_remove_line >= close_callback_line \
          || close_callback_line >= reuse_guard_line )); then
  echo 'error: auxiliary physical retirement must finish before the reentrant close callback and guarded focus tail' >&2
  exit 1
fi
require_matches 'load\.hasUnresolvedExtensionOwnership == false' "$window_router"
if scan_has_matches 'auxiliaryContains|teardownAuxiliaryWebView|auxiliaryWindowSession\(for: webView\)' \
  "$close_router"; then
  echo 'error: generic WebView close routing regained auxiliary WebView authority' >&2
  exit 1
fi
require_matches 'teardownAuxiliarySessionForTab' "$close_router"
require_matches -U 'session\.tab === tab,[[:space:]]+let receipt = auxiliaryWindows\.sessions\.receipt' \
  "$close_router"
atomic_load_line="$(capture_matches 'let load = loadResolver\.resolve' "$window_router" | tail -1 | cut -d: -f1)"
atomic_reject_line="$(capture_matches 'load\.hasUnresolvedExtensionOwnership == false' "$window_router" | tail -2 | head -1 | cut -d: -f1)"
atomic_prepare_line="$(capture_matches 'await prepare\(' "$window_router" | tail -1 | cut -d: -f1)"
if [[ -z "$atomic_load_line" || -z "$atomic_reject_line" \
      || -z "$atomic_prepare_line" ]] \
    || (( atomic_load_line >= atomic_reject_line \
          || atomic_reject_line >= atomic_prepare_line )); then
  echo 'error: unresolved extension-owned window load must fail before preload' >&2
  exit 1
fi
require_matches 'let sessionIdentity: ObjectIdentifier' "$extension_bridge"
require_matches 'let webViewIdentity: ObjectIdentifier' "$extension_bridge"
require_matches 'exactContextIdentity' "$page_resolution"
require_matches '\$0\.id == identity\.extensionId && \$0\.isEnabled' \
  "$page_resolution"
require_matches 'candidates\.dropFirst\(\)\.allSatisfy' "$page_resolution"
owner_guard_line="$(capture_matches 'extensionIntegration == nil \|\| extensionID != nil' \
  "$popup_opening" | cut -d: -f1)"
external_create_line="$(capture_matches 'guard let tab = tabs\.createMiniWindowTab' \
  "$popup_opening" | tail -1 | cut -d: -f1)"
if [[ -z "$owner_guard_line" || -z "$external_create_line" ]] \
    || (( owner_guard_line >= external_create_line )); then
  echo 'error: external extension popup owner evidence must fail before tab mutation' >&2
  exit 1
fi
owner_validation_count="$(
  count_matches 'runtime\.integration\.resolveExtensionID' "$extension_opening"
)"
if (( owner_validation_count < 2 )); then
  echo 'error: extension window owner evidence must be revalidated after awaits' >&2
  exit 1
fi
last_owner_validation_line="$(capture_matches 'runtime\.integration\.resolveExtensionID' \
  "$extension_opening" | tail -1 | cut -d: -f1)"
extension_create_line="$(capture_matches 'guard let tab = tabs\.createMiniWindowTab' \
  "$extension_opening" | cut -d: -f1)"
load_line="$(capture_matches 'tab\.loadURL\(loadURL\)' "$extension_opening" | cut -d: -f1)"
history_line="$(capture_matches 'runtime\.recentRequests\.record\(loadURL\)' \
  "$extension_opening" | cut -d: -f1)"
if [[ -z "$last_owner_validation_line" || -z "$extension_create_line" \
      || -z "$load_line" || -z "$history_line" ]] \
    || (( last_owner_validation_line >= extension_create_line \
          || load_line >= history_line )); then
  echo 'error: extension popup mutation/history escaped exact owner or completion admission' >&2
  exit 1
fi
if scan_has_matches 'presentExtensionExternalWebPopup' \
  "$extension_bridge" "$window_presentation"; then
  echo 'error: dead external popup forwarding capability returned to extension presentation' >&2
  exit 1
fi
require_matches 'private weak var target' "$weak_events"
require_matches 'events: WeakAuxiliaryWindowExtensionEvents' "$browser_aux"
require_matches -F 'let extensionEvents: (any AuxiliaryWindowExtensionEventHandling)?' \
  Sumi/AuxiliaryWindows/AuxiliaryWindowSessionRegistry.swift
if scan_has_matches 'weak var extensionEvents' \
  Sumi/AuxiliaryWindows/AuxiliaryWindowSessionRegistry.swift; then
  echo 'error: auxiliary session stopped owning its weak lifetime projection' >&2
  exit 1
fi
if scan_has_matches 'events: self' "$browser_aux" \
  Sumi/Managers/ExtensionManager/ExtensionControllerOpeningCallbackComposition.swift; then
  echo 'error: auxiliary integration regained transitive ExtensionManager retention' >&2
  exit 1
fi
require_matches 'private struct ScheduledTask' "$content"
require_matches 'tasksByProfile\[profileID\]\?\.token == token' "$content"
require_matches 'retiredTokens' "$content"
require_matches -F 'target?.notifyAuxiliaryWindowOpened(session) ?? false' "$weak_events"

if scan_has_matches 'private (weak|unowned) var manager|private unowned let manager' \
  "$initial" "$native" "$retention" "$loading" "$settlement" "$deferred"; then
  echo 'error: auxiliary role regained an ExtensionManager backreference' >&2
  exit 1
fi
if scan_has_matches '\bExtensionManager\b|\[(weak|unowned) manager\]' \
  "$opening" "$deferred"; then
  echo 'error: exact opening/deferred roles regained an ExtensionManager root' >&2
  exit 1
fi
require_matches 'let runtimeQuery: ExtensionDeferredRuntimeQuery' "$deferred"
require_matches 'let contextLoading: ExtensionContextResidencyOwner' "$deferred"
require_matches 'let backgroundWake: ExtensionBackgroundWakeCoordinator' "$deferred"
require_matches 'deferredRuntimeOwnerStoreStorage?' \
  Sumi/Managers/ExtensionManager/ExtensionManager.swift
if scan_has_matches '_ = deferredRuntimeOwnerStore' \
  Sumi/Managers/ExtensionManager/ExtensionManager.swift; then
  echo 'error: disabled extension runtime eagerly materializes deferred owners' >&2
  exit 1
fi
if scan_has_matches 'struct Dependencies|dependencies\.' \
  "$residency" "$retention" "$loading" "$settlement"; then
  echo 'error: context residency closure dependency bag returned' >&2
  exit 1
fi
require_matches 'ExtensionContentScriptContextPreparationOwner' "$initial"
require_matches 'ExtensionInitialDocumentNativeMessagingWarmupOwner' "$initial"
require_matches 'let retention: ExtensionContextRetentionOwner' "$residency"
require_matches 'let loading: ExtensionContextLoadingOwner' "$residency"
require_matches 'let settlement: ExtensionContextSettlementOwner' "$residency"

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
