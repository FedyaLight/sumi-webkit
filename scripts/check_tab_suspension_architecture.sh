#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

status=0

state_files=(
  Sumi/Models/Tab/TabSuspensionState.swift
  Sumi/Models/Tab/TabDocumentSuspensionDecision.swift
)

suspension_script=Sumi/UserScripts/SumiTabSuspensionUserScript.swift
document_sensor=Sumi/UserScripts/SumiDocumentSuspensionSensorUserScript.swift

required_runtime_files=(
  Sumi/Managers/TabSuspensionController.swift
  Sumi/Managers/MemoryPressureTabSuspensionHandler.swift
  Sumi/Managers/BrowserManager/BrowserTabSuspensionRuntimeFactory.swift
)

for file in "${state_files[@]}"; do
  guard_require_file "$file"
done

for file in "$suspension_script" "$document_sensor"; do
  guard_require_file "$file"
done

for file in "${required_runtime_files[@]}"; do
  guard_require_file "$file"
done

if [[ -f Sumi/Managers/MemoryPressureTabSuspensionService.swift ]]; then
  printf 'error: legacy memory-pressure suspension service still exists\n' >&2
  status=1
fi

if [[ -f Sumi/Managers/TabSuspensionPolicyChangeMonitor.swift ]]; then
  printf 'error: retired always-on suspension policy monitor still exists\n' >&2
  status=1
fi

legacy_hits="$(
  guard_capture_matches '\b(TabSuspensionService|TabSuspensionRuntime|TabSuspensionStateOwner|suspensionStateOwner)\b' \
    Sumi SumiTests -g '*.swift'
)"
if [[ -n "$legacy_hits" ]]; then
  guard_record_failure "deleted suspension facade/owner reintroduced:
$legacy_hits"
fi

logical_document_state_hits="$(
  guard_capture_matches '\b(suspensionProtection|TabSuspensionProtectionState|TabPageSuspensionVeto)\b' \
    Sumi SumiTests -g '*.swift'
)"
if [[ -n "$logical_document_state_hits" ]]; then
  guard_record_failure "logical Tab suspension last-writer state reintroduced:
$logical_document_state_hits"
fi

embedded_script_hits="$(
  guard_capture_matches '\b(class|struct) SumiTabSuspensionUserScript\b' \
    Sumi/Models/Tab/TabCoreUserScripts.swift
)"
if [[ -n "$embedded_script_hits" ]]; then
  guard_record_failure "document suspension script embedded in Tab composition:
$embedded_script_hits"
fi

ledger_report_count="$(guard_count_matches 'func recordSuspensionReport\(' \
  Sumi/Models/Tab/TabCommittedDocumentLedger.swift)"
if (( ledger_report_count == 0 )); then
  printf 'error: committed-document ledger does not own suspension reports\n' >&2
  status=1
fi

suspension_authority_count="$(
  guard_count_matches 'documentLeaseToken|activateCommittedDocument' "$suspension_script"
)"
if (( suspension_authority_count > 0 )); then
  printf 'error: page suspension API exposes native document authority\n' >&2
  status=1
fi

main_frame_count="$(guard_count_matches 'message\.frameInfo\.isMainFrame' "$document_sensor")"
lease_count="$(guard_count_matches 'committedDocumentRuntime\.lease\(for: webView\)' "$document_sensor")"
lease_token_count="$(guard_count_matches 'documentLeaseToken' "$document_sensor")"
lease_epoch_count="$(guard_count_matches 'documentLeaseEpoch' "$document_sensor")"
activation_epoch_count="$(guard_count_matches 'suspensionActivationEpoch' \
  Sumi/Models/Tab/TabCommittedDocumentLedger.swift)"
if (( main_frame_count == 0 || lease_count == 0 || lease_token_count == 0 \
  || lease_epoch_count == 0 || activation_epoch_count == 0 )); then
  printf 'error: suspension message handler lacks physical main-document validation\n' >&2
  status=1
fi

report_count="$(guard_count_matches 'recordSuspensionReport' "$document_sensor")"
decision_change_count="$(guard_count_matches 'committedDocumentSuspensionDecisionDidChange' \
  Sumi/Models/Tab/TabCommittedDocumentRuntime.swift)"
promotion_reconcile_count="$(guard_count_matches 'reconcileDocumentSuspensionState' \
  Sumi/Models/Tab/Navigation/TabMainFrameLifecyclePromotionReducer.swift)"
factory_reconcile_count="$(guard_count_matches 'reconcileDocumentSuspensionState' \
  Sumi/Managers/BrowserManager/TabBrowserNavigationRuntimeFactory.swift)"
if (( report_count == 0 || decision_change_count == 0 \
  || promotion_reconcile_count == 0 || factory_reconcile_count == 0 )); then
  printf 'error: document suspension evidence is not reconciled after reports and finish\n' >&2
  status=1
fi

legacy_component_hits="$(
  guard_capture_matches '\b(MemoryPressureTabSuspensionService|tabSuspensionContextSource|tabSuspensionExecutor|proactiveTabSuspension|memoryPressureTabSuspension)\b' \
    Sumi SumiTests -g '*.swift'
)"
if [[ -n "$legacy_component_hits" ]]; then
  guard_record_failure "legacy suspension graph components remain externally visible:
$legacy_component_hits"
fi

partial_install_hits="$(
  guard_capture_matches '\b(attachTabSuspensionContextRuntime|attachTabSuspensionWebViewRuntime|attachTabSuspensionCatalogRuntime|tabSuspensionRuntimePorts)\b' \
    Sumi SumiTests -g '*.swift'
)"
if [[ -n "$partial_install_hits" ]]; then
  guard_record_failure "partial suspension runtime installation seam reintroduced:
$partial_install_hits"
fi

suspension_owner_files="$(
  find Sumi -type f -print \
    | guard_capture_matches '/[^/]*Suspension[^/]*Owner[^/]*\.swift$' -
)"
if [[ -n "$suspension_owner_files" ]]; then
  guard_record_failure "suspension responsibility hidden behind an Owner file:
$suspension_owner_files"
fi

if [[ -f "${state_files[0]}" && -f "${state_files[1]}" ]]; then
  state_framework_hits="$(
    guard_capture_matches '^import (AppKit|SwiftUI|WebKit)$|\b(BrowserManager|TabManager|WKWebView|Tab)\b' \
      "${state_files[@]}"
  )"
  if [[ -n "$state_framework_hits" ]]; then
    guard_record_failure "suspension value-state depends on UI/runtime graph types:
$state_framework_hits"
  fi
fi

core_files=(
  Sumi/Managers/TabSuspensionPolicy.swift
  Sumi/Managers/TabSuspensionRuntimePorts.swift
  Sumi/Managers/TabSuspensionEligibilityEvaluator.swift
  Sumi/Managers/TabSuspensionExecutor.swift
  Sumi/Managers/TabSuspensionVisibilityLedger.swift
  Sumi/Managers/ProactiveTabSuspensionTimerScheduler.swift
  Sumi/Managers/TabSuspensionReconcileScheduler.swift
  Sumi/Managers/ProactiveTabSuspensionLifecycle.swift
  Sumi/Managers/MemoryPressureTabSuspensionHandler.swift
  Sumi/Managers/TabSuspensionController.swift
)

for file in "${core_files[@]}"; do
  guard_require_file "$file"
done

browser_graph_hits="$(
  guard_capture_matches '\b(BrowserManager|BrowserWindowState|TabManager)\b' \
    "${core_files[@]}"
)"
if [[ -n "$browser_graph_hits" ]]; then
  guard_record_failure "suspension core reaches back into the browser composition graph:
$browser_graph_hits"
fi

mechanism_constructor_hits="$(
  guard_capture_matches '\b(TabSuspensionContextSource|TabSuspensionExecutor|ProactiveTabSuspensionLifecycle|MemoryPressureTabSuspensionHandler)\s*\(' \
    Sumi -g '*.swift' -g '!TabSuspensionController.swift'
)"
if [[ -n "$mechanism_constructor_hits" ]]; then
  guard_record_failure "suspension mechanisms constructed outside the lifecycle authority:
$mechanism_constructor_hits"
fi

factory_locator_hits="$(
  guard_capture_matches '\b(BrowserManager|TabManager)\b' \
    Sumi/Managers/BrowserManager/BrowserTabSuspensionRuntimeFactory.swift
)"
if [[ -n "$factory_locator_hits" ]]; then
  guard_record_failure "suspension runtime factory reaches into a browser service locator:
$factory_locator_hits"
fi

controller_exposure_hits="$(
  guard_capture_matches '^[[:space:]]{4}(let|var)[[:space:]]+(contextSource|executor|proactiveLifecycle|memoryPressureHandler)\b' \
    Sumi/Managers/TabSuspensionController.swift
)"
if [[ -n "$controller_exposure_hits" ]]; then
  guard_record_failure "controller exposes private suspension mechanisms:
$controller_exposure_hits"
fi

controller_loc="$(guard_count_lines Sumi/Managers/TabSuspensionController.swift)"
if (( controller_loc > 160 )); then
  printf 'error: TabSuspensionController exceeds focused lifecycle boundary (%d > 160)\n' \
    "$controller_loc" >&2
  status=1
fi

for file in \
  Sumi/BrowserRuntime/BrowserKernelGraph.swift \
  Sumi/Managers/BrowserManager/BrowserManager.swift; do
  edge_count="$(guard_count_matches 'let tabSuspensionController: TabSuspensionController' "$file")"
  if (( edge_count == 0 )); then
    printf 'error: canonical suspension controller edge missing: %s\n' "$file" >&2
    status=1
  fi
done

if (( status != 0 || guard_failures != 0 )); then
  exit 1
fi

echo "tab suspension architecture boundary passed"
