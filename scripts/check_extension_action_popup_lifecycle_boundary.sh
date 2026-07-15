#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

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

[[ ! -e Sumi/Managers/ExtensionManager/ExtensionActionPopupSessionOwner.swift \
   && ! -L Sumi/Managers/ExtensionManager/ExtensionActionPopupSessionOwner.swift ]] || {
  printf 'error: retired action-popup owner returned\n' >&2
  exit 1
}

forbidden_hits="$(
  guard_capture_matches \
    '(ExtensionActionPopupUIDelegate|ExtensionActionPopupChildWindowRouter|popupWebView\.uiDelegate\s*=)' \
    Sumi/Managers/ExtensionManager/ExtensionActionPopup*.swift
)"
if [[ -n "$forbidden_hits" ]]; then
  printf '%s\n' "$forbidden_hits" >&2
  printf 'error: popup lifecycle replaced WebKit native UI-delegate routing\n' >&2
  exit 1
fi

forbidden_hits="$(
  guard_capture_matches \
    '\b(BrowserManager|ExtensionManager|Dependencies|Actions|SessionOwner)\b' \
    "${role_files[@]}"
)"
if [[ -n "$forbidden_hits" ]]; then
  printf '%s\n' "$forbidden_hits" >&2
  printf 'error: action-popup roles regained manager-root or closure-bag authority\n' >&2
  exit 1
fi

forbidden_hits="$(
  guard_capture_matches \
    '(fittingSize|minimumContentSize|\.contentSize\s*=|\.closePopup\(\))' \
    "${role_files[@]}"
)"
if [[ -n "$forbidden_hits" ]]; then
  printf '%s\n' "$forbidden_hits" >&2
  printf 'error: action-popup lifecycle bypasses native WebKit popover sizing/close\n' >&2
  exit 1
fi

forbidden_hits="$(
  guard_capture_matches \
    '(clearLaunchSessionOnExtensionContextUnload|nativeMessagingPortRegistry|disconnectAll\()' \
    "${role_files[@]}"
)"
if [[ -n "$forbidden_hits" ]]; then
  printf '%s\n' "$forbidden_hits" >&2
  printf 'error: popup close regained extension-context/native-port teardown\n' >&2
  exit 1
fi

presentation_context='Sumi/Components/Extensions/ExtensionActionPresentationContext.swift'
forbidden_hits="$(
  guard_capture_matches \
    '(popover\.delegate\s*=|Task\.sleep|asyncAfter\s*\(|\bTimer\s*[.(]|popupWebView\.reload\s*\()' \
    "${role_files[@]}" "$presentation_context"
)"
if [[ -n "$forbidden_hits" ]]; then
  printf '%s\n' "$forbidden_hits" >&2
  printf 'error: popup lifecycle regained delegate takeover or time-based recovery\n' >&2
  exit 1
fi

require_scan_pattern() {
  local file="$1"
  local pattern="$2"
  local invariant="$3"
  local count
  count="$(guard_count_matches "$pattern" "$file")"
  if (( count == 0 )); then
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

for file in "$context_retirement" "$delegate_bridge" "$presentation_context"; do
  [[ -f "$file" ]] || {
    printf 'error: action-popup integration boundary missing: %s\n' "$file" >&2
    exit 1
  }
done

click_target_line="$(
  guard_capture_matches 'let currentTab = currentActionTab$' \
    "$presentation_context" -m 1 | cut -d: -f1
)"
first_click_await_line="$(
  guard_capture_matches 'let result = await ' \
    "$presentation_context" -m 1 | cut -d: -f1
)"
if [[ -z "$click_target_line" || -z "$first_click_await_line" ]] \
  || (( click_target_line >= first_click_await_line )); then
  printf 'error: popup click target is not captured once before suspension\n' >&2
  exit 1
fi

require_scan_pattern "$ledger" 'func reserve\(' 'monotonic reservation'
require_scan_pattern "$ledger" 'func activate\(' 'validation before activation'
require_scan_pattern "$ledger" 'func stage\(' 'session staged before presentation'
require_scan_pattern "$ledger" 'closingByPopoverID' 'physical close tombstones'
require_scan_pattern "$target" 'claimAnchor\(' 'one-shot exact anchor claim'
require_scan_pattern "$target" 'adapter\.evidence\.isCurrent\(' 'exact current-tab admission'
require_scan_pattern "$session" 'NSPopover\.willCloseNotification' 'scoped pre-close observation'
require_scan_pattern "$session" 'NSPopover\.didCloseNotification' 'scoped close completion'
require_scan_pattern "$runtime_retirement" 'invocations\.quarantine\(binding: receipt\)' 'pre-unload callback quarantine'
require_scan_pattern "$runtime_retirement" 'invocations\.retire\(binding: receipt\)' 'post-unload tombstone removal'
require_scan_pattern "$context_retirement" 'actionPopups\?\.begin\(receipt\)' 'popup retirement before unload'
require_scan_pattern "$context_retirement" 'actionPopups\?\.complete\(receipt\)' 'popup retirement after exact removal'
require_scan_pattern "$binding_recovery" 'fresh\.contextIdentifier != stalled\.contextIdentifier' 'fresh physical WebKit context'
require_scan_pattern "$binding_recovery" 'context\.webExtensionController === controller' 'physical controller binding'
require_scan_pattern "$binding_recovery" 'controller\.extensionContexts\.contains' 'physical controller membership'
require_scan_pattern "$delegate_bridge" 'actionPopupCallbackAdmission\.capture' 'callback evidence capture'
require_scan_pattern "$delegate_bridge" 'actionPopupInvocationLedger\.claim' 'browser invocation claim'

bridge_capture_line="$(
  guard_capture_matches 'actionPopupCallbackAdmission\.capture' \
    "$delegate_bridge" -m 1 | cut -d: -f1
)"
bridge_claim_line="$(
  guard_capture_matches 'actionPopupInvocationLedger\.claim' \
    "$delegate_bridge" -m 1 | cut -d: -f1
)"
bridge_present_line="$(
  guard_capture_matches 'actionPopupCoordinator\.present' \
    "$delegate_bridge" -m 1 | cut -d: -f1
)"
if [[ -z "$bridge_capture_line" || -z "$bridge_claim_line" \
   || -z "$bridge_present_line" ]] \
  || (( bridge_capture_line >= bridge_claim_line \
   || bridge_claim_line >= bridge_present_line )); then
  printf 'error: popup callback lost evidence -> invocation -> presentation order\n' >&2
  exit 1
fi

coordinator='Sumi/Managers/ExtensionManager/ExtensionActionPopupCoordinator.swift'
stage_line="$(guard_capture_matches 'sessions\.stage\(' "$coordinator" -m 1 | cut -d: -f1)"
observe_line="$(guard_capture_matches 'observePopoverClosing\(' "$coordinator" -m 1 | cut -d: -f1)"
present_line="$(guard_capture_matches 'presentResolvedExtensionActionPopup\(' "$coordinator" -m 1 | cut -d: -f1)"
commit_line="$(guard_capture_matches 'sessions\.commit\(' "$coordinator" -m 1 | cut -d: -f1)"
if [[ -z "$stage_line" || -z "$observe_line" || -z "$present_line" \
   || -z "$commit_line" ]] \
  || (( stage_line >= observe_line || observe_line >= present_line \
   || present_line >= commit_line )); then
  printf 'error: popup transaction lost stage -> observe -> show -> commit order\n' >&2
  exit 1
fi

popover_scope_count="$(guard_count_matches 'object: popover' "$session")"
popover_identity_count="$(
  guard_count_matches 'notification\.object.*NSPopover.*=== popover' "$session"
)"
if (( popover_scope_count < 2 || popover_identity_count < 2 )); then
  printf 'error: popup close observations are not scoped to the exact popover\n' >&2
  exit 1
fi

forbidden_hits="$(
  guard_capture_matches \
    '(\.cancel\(|\.settle\(|\.retirePresentation\(|\.finishPopoverClosing\()' \
    "$ledger"
)"
if [[ -n "$forbidden_hits" ]]; then
  printf '%s\n' "$forbidden_hits" >&2
  printf 'error: popup state ledger regained physical retirement effects\n' >&2
  exit 1
fi

forbidden_hits="$(
  guard_capture_matches '\?\?\s*UUID\(\)' \
    Sumi/Managers/ExtensionManager/ExtensionActionPopup*.swift \
    "$presentation_context"
)"
if [[ -n "$forbidden_hits" ]]; then
  printf '%s\n' "$forbidden_hits" >&2
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
