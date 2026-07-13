#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

role_files=(
  Sumi/Managers/ExtensionManager/ExtensionActionPopupAnchorResolver.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupAnchorStore.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupBindingRecovery.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupCallbackAdmission.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupCommitRecorder.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupCompletion.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupCoordinator.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupFocusRestorer.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupInvocationLedger.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupPresentation.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupRetirementOutcome.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupRetirementService.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupRuntimeRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupSession.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupSessionLedger.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupSourceReceipt.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupTargetCapture.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPopupTelemetry.swift
)

for file in "${role_files[@]}"; do
  [[ -f "$file" ]] || {
    printf 'error: action-popup role missing: %s\n' "$file" >&2
    exit 1
  }
done

[[ ! -e Sumi/Managers/ExtensionManager/ExtensionActionPopupSessionOwner.swift ]] || {
  printf 'error: retired action-popup owner returned\n' >&2
  exit 1
}

if rg -n '(ExtensionActionPopupUIDelegate|ExtensionActionPopupChildWindowRouter|popupWebView\.uiDelegate\s*=)' \
    Sumi/Managers/ExtensionManager/ExtensionActionPopup*.swift; then
  printf 'error: popup lifecycle replaced WebKit native UI-delegate routing\n' >&2
  exit 1
fi

if rg -n '\b(BrowserManager|ExtensionManager|Dependencies|Actions|SessionOwner)\b' \
    "${role_files[@]}"; then
  printf 'error: action-popup roles regained manager-root or closure-bag authority\n' >&2
  exit 1
fi

if rg -n '(fittingSize|minimumContentSize|\.contentSize\s*=|\.closePopup\(\))' \
    "${role_files[@]}"; then
  printf 'error: action-popup lifecycle bypasses native WebKit popover sizing/close\n' >&2
  exit 1
fi

if rg -n '(clearLaunchSessionOnExtensionContextUnload|nativeMessagingPortRegistry|disconnectAll\()' \
    "${role_files[@]}"; then
  printf 'error: popup close regained extension-context/native-port teardown\n' >&2
  exit 1
fi

presentation_context='Sumi/Components/Extensions/ExtensionActionPresentationContext.swift'
if rg -n '(popover\.delegate\s*=|Task\.sleep|asyncAfter\s*\(|\bTimer\s*[.(]|popupWebView\.reload\s*\()' \
    "${role_files[@]}" "$presentation_context"; then
  printf 'error: popup lifecycle regained delegate takeover or time-based recovery\n' >&2
  exit 1
fi

require_pattern() {
  local file="$1"
  local pattern="$2"
  local invariant="$3"
  if ! rg -q "$pattern" "$file"; then
    printf 'error: action-popup invariant missing (%s): %s\n' \
      "$invariant" "$file" >&2
    exit 1
  fi
}

ledger='Sumi/Managers/ExtensionManager/ExtensionActionPopupSessionLedger.swift'
session='Sumi/Managers/ExtensionManager/ExtensionActionPopupSession.swift'
target='Sumi/Managers/ExtensionManager/ExtensionActionPopupTargetCapture.swift'
runtime_retirement='Sumi/Managers/ExtensionManager/ExtensionActionPopupRuntimeRetirement.swift'
context_retirement='Sumi/Managers/ExtensionManager/ExtensionContextRetirement.swift'
binding_recovery='Sumi/Managers/ExtensionManager/ExtensionActionPopupBindingRecovery.swift'
delegate_bridge='Sumi/Managers/ExtensionManager/ExtensionControllerDelegateBridge.swift'
invocation_tests='SumiTests/ExtensionActionInvocationAdmissionTests.swift'
recovery_tests='SumiTests/ExtensionActionPopupBindingRecoveryTests.swift'
completion_tests='SumiTests/ExtensionActionPopupCompletionTests.swift'
session_ledger_tests='SumiTests/ExtensionActionPopupSessionLedgerTests.swift'
native_messaging_tests='SumiTests/SafariExtensionPopupNativeMessagingLifecycleTests.swift'

for file in "$context_retirement" "$delegate_bridge" "$invocation_tests" \
  "$recovery_tests" "$completion_tests" "$session_ledger_tests" \
  "$native_messaging_tests" "$presentation_context"; do
  [[ -f "$file" ]] || {
    printf 'error: action-popup integration boundary missing: %s\n' "$file" >&2
    exit 1
  }
done

click_target_line="$(rg -n 'let currentTab = currentActionTab$' "$presentation_context" | cut -d: -f1)"
first_click_await_line="$(rg -n 'let result = await ' "$presentation_context" | cut -d: -f1)"
if [[ -z "$click_target_line" || -z "$first_click_await_line" ]] \
  || (( click_target_line >= first_click_await_line )); then
  printf 'error: popup click target is not captured once before suspension\n' >&2
  exit 1
fi

require_pattern "$ledger" 'func reserve\(' 'monotonic reservation'
require_pattern "$ledger" 'func activate\(' 'validation before activation'
require_pattern "$ledger" 'func stage\(' 'session staged before presentation'
require_pattern "$ledger" 'closingByPopoverID' 'physical close tombstones'
require_pattern "$target" 'claimAnchor\(' 'one-shot exact anchor claim'
require_pattern "$target" 'adapter\.evidence\.isCurrent\(' 'exact current-tab admission'
require_pattern "$session" 'NSPopover\.willCloseNotification' 'scoped pre-close observation'
require_pattern "$session" 'NSPopover\.didCloseNotification' 'scoped close completion'
require_pattern "$runtime_retirement" 'invocations\.quarantine\(binding: receipt\)' 'pre-unload callback quarantine'
require_pattern "$runtime_retirement" 'invocations\.retire\(binding: receipt\)' 'post-unload tombstone removal'
require_pattern "$context_retirement" 'actionPopups\?\.begin\(receipt\)' 'popup retirement before unload'
require_pattern "$context_retirement" 'actionPopups\?\.complete\(receipt\)' 'popup retirement after exact removal'
require_pattern "$binding_recovery" 'fresh\.contextIdentifier != stalled\.contextIdentifier' 'fresh physical WebKit context'
require_pattern "$binding_recovery" 'context\.webExtensionController === controller' 'physical controller binding'
require_pattern "$binding_recovery" 'controller\.extensionContexts\.contains' 'physical controller membership'
require_pattern "$delegate_bridge" 'actionPopupCallbackAdmission\.capture' 'callback evidence capture'
require_pattern "$delegate_bridge" 'actionPopupInvocationLedger\.claim' 'browser invocation claim'

bridge_capture_line="$(rg -n 'actionPopupCallbackAdmission\.capture' "$delegate_bridge" | cut -d: -f1)"
bridge_claim_line="$(rg -n 'actionPopupInvocationLedger\.claim' "$delegate_bridge" | cut -d: -f1)"
bridge_present_line="$(rg -n 'actionPopupCoordinator\.present' "$delegate_bridge" | cut -d: -f1)"
if (( bridge_capture_line >= bridge_claim_line \
   || bridge_claim_line >= bridge_present_line )); then
  printf 'error: popup callback lost evidence -> invocation -> presentation order\n' >&2
  exit 1
fi

coordinator='Sumi/Managers/ExtensionManager/ExtensionActionPopupCoordinator.swift'
stage_line="$(rg -n 'sessions\.stage\(' "$coordinator" | cut -d: -f1)"
observe_line="$(rg -n 'observePopoverClosing\(' "$coordinator" | cut -d: -f1)"
present_line="$(rg -n 'presentResolvedExtensionActionPopup\(' "$coordinator" | cut -d: -f1)"
commit_line="$(rg -n 'sessions\.commit\(' "$coordinator" | cut -d: -f1)"
if (( stage_line >= observe_line || observe_line >= present_line \
   || present_line >= commit_line )); then
  printf 'error: popup transaction lost stage -> observe -> show -> commit order\n' >&2
  exit 1
fi

if (( $(rg -c 'object: popover' "$session") < 2 \
   || $(rg -c 'notification\.object.*NSPopover.*=== popover' "$session") < 2 )); then
  printf 'error: popup close observations are not scoped to the exact popover\n' >&2
  exit 1
fi

for required_test in \
  testPendingIdentityIsExclusiveUntilFailureSettlesOnce \
  testDistinctActivationSupersedesPendingWithoutStaleRetirement \
  testClosingIdentityRemainsExclusiveAndStaleClosePreservesReplacement; do
  require_pattern "$session_ledger_tests" "func $required_test" \
    "session-ledger regression $required_test"
done
require_pattern "$completion_tests" \
  'func testReentrantSettlementCannotInvokeWebKitCompletionTwice' \
  'reentrant one-shot completion'
require_pattern "$recovery_tests" \
  'func testFreshRuntimeReceiptWithoutPhysicalControllerLoadFailsClosed' \
  'registry-only popup recovery rejection'
require_pattern "$invocation_tests" \
  'func testSuccessfulBindingRecoveryRetriesInvocationServiceOnce' \
  'invocation recovery retry orchestration'
require_pattern "$session_ledger_tests" \
  'func testCommittedSessionRetirementPreservesWebKitUIDelegate' \
  'native WebKit UI-delegate preservation'
require_pattern "$native_messaging_tests" \
  'func testPopupCloseDoesNotCancelInFlightOneShotRelay' \
  'in-flight native messaging survival'

if rg -n '(\.cancel\(|\.settle\(|\.retirePresentation\(|\.finishPopoverClosing\()' \
    "$ledger"; then
  printf 'error: popup state ledger regained physical retirement effects\n' >&2
  exit 1
fi

if rg -n '\?\?\s*UUID\(\)' \
    Sumi/Managers/ExtensionManager/ExtensionActionPopup*.swift \
    "$presentation_context"; then
  printf 'error: popup target authority fell back to a fabricated UUID\n' >&2
  exit 1
fi

session_lines="$(wc -l < "$session")"
ledger_lines="$(wc -l < "$ledger")"
coordinator_lines="$(wc -l < Sumi/Managers/ExtensionManager/ExtensionActionPopupCoordinator.swift)"
invocation_lines="$(wc -l < Sumi/Managers/ExtensionManager/ExtensionActionPopupInvocationLedger.swift)"
retirement_lines="$(wc -l < Sumi/Managers/ExtensionManager/ExtensionActionPopupRetirementService.swift)"
outcome_lines="$(wc -l < Sumi/Managers/ExtensionManager/ExtensionActionPopupRetirementOutcome.swift)"
commit_recorder_lines="$(wc -l < Sumi/Managers/ExtensionManager/ExtensionActionPopupCommitRecorder.swift)"
if (( session_lines > 230 || ledger_lines > 400 || coordinator_lines > 320 \
   || retirement_lines > 150 || outcome_lines > 90 \
   || commit_recorder_lines > 70 \
   || invocation_lines > 240 )); then
  printf 'error: action-popup responsibility surface grew past frozen bounds\n' >&2
  exit 1
fi

echo "extension action popup lifecycle boundary passed"
