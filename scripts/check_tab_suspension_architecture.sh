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

state_files=(
  Sumi/Models/Tab/TabSuspensionState.swift
  Sumi/Models/Tab/TabDocumentSuspensionDecision.swift
)

suspension_script=Sumi/UserScripts/SumiTabSuspensionUserScript.swift
document_sensor=Sumi/UserScripts/SumiDocumentSuspensionSensorUserScript.swift
subframe_pip_sensor=Sumi/UserScripts/SumiSubframePictureInPictureUserScript.swift

required_runtime_files=(
  Sumi/Managers/TabSuspensionController.swift
  Sumi/Managers/MemoryPressureTabSuspensionHandler.swift
  Sumi/Managers/BrowserManager/BrowserTabSuspensionRuntimeFactory.swift
)

for file in "${state_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: suspension value-state boundary missing: %s\n' "$file" >&2
    status=1
  fi
done

for file in "$suspension_script" "$document_sensor" "$subframe_pip_sensor"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: physical document suspension script missing: %s\n' "$file" >&2
    status=1
  fi
done

for file in "${required_runtime_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: suspension runtime boundary missing: %s\n' "$file" >&2
    status=1
  fi
done

if [[ -f Sumi/Managers/MemoryPressureTabSuspensionService.swift ]]; then
  printf 'error: legacy memory-pressure suspension service still exists\n' >&2
  status=1
fi

legacy_hits="$(
  rg -n '\b(TabSuspensionService|TabSuspensionRuntime|TabSuspensionStateOwner|suspensionStateOwner)\b' \
    Sumi SumiTests -g '*.swift' || true
)"
fail_matches "deleted suspension facade/owner reintroduced" "$legacy_hits"

logical_document_state_hits="$(
  rg -n '\b(suspensionProtection|TabSuspensionProtectionState|TabPageSuspensionVeto)\b' \
    Sumi SumiTests -g '*.swift' || true
)"
fail_matches "logical Tab suspension last-writer state reintroduced" "$logical_document_state_hits"

embedded_script_hits="$(
  rg -n '\b(class|struct) SumiTabSuspensionUserScript\b' \
    Sumi/Models/Tab/TabCoreUserScripts.swift || true
)"
fail_matches "document suspension script embedded in Tab composition" "$embedded_script_hits"

if ! rg -q 'func recordSuspensionReport\(' \
  Sumi/Models/Tab/TabCommittedDocumentLedger.swift; then
  printf 'error: committed-document ledger does not own suspension reports\n' >&2
  status=1
fi

if rg -q 'documentLeaseToken|activateCommittedDocument' "$suspension_script"; then
  printf 'error: page suspension API exposes native document authority\n' >&2
  status=1
fi

if ! rg -q 'message\.frameInfo\.isMainFrame' "$document_sensor" \
  || ! rg -q 'mainFrameDocumentLease\(for: webView\)' "$document_sensor" \
  || ! rg -q 'documentLeaseToken' "$document_sensor" \
  || ! rg -q 'documentLeaseEpoch' "$document_sensor" \
  || ! rg -q 'suspensionActivationEpoch' \
    Sumi/Models/Tab/TabCommittedDocumentLedger.swift; then
  printf 'error: suspension message handler lacks physical main-document validation\n' >&2
  status=1
fi

if ! rg -q 'forMainFrameOnly = false' "$subframe_pip_sensor" \
  || ! rg -q 'in: \.defaultClient' "$subframe_pip_sensor" \
  || ! rg -q 'documentLeaseToken' "$subframe_pip_sensor"; then
  printf 'error: subframe PiP veto is not isolated and epoch-bound\n' >&2
  status=1
fi

if ! rg -q 'reconcileDocumentSuspensionState' "$document_sensor" \
  || ! rg -q 'reconcileDocumentSuspensionState' \
    Sumi/Models/Tab/Navigation/TabMainFrameLifecyclePromotionReducer.swift \
  || ! rg -q 'reconcileDocumentSuspensionState' \
    Sumi/Managers/BrowserManager/TabBrowserNavigationRuntimeFactory.swift; then
  printf 'error: document suspension evidence is not reconciled after reports and finish\n' >&2
  status=1
fi

legacy_component_hits="$(
  rg -n '\b(MemoryPressureTabSuspensionService|tabSuspensionContextSource|tabSuspensionExecutor|proactiveTabSuspension|memoryPressureTabSuspension)\b' \
    Sumi SumiTests -g '*.swift' || true
)"
fail_matches "legacy suspension graph components remain externally visible" "$legacy_component_hits"

partial_install_hits="$(
  rg -n '\b(attachTabSuspensionContextRuntime|attachTabSuspensionWebViewRuntime|attachTabSuspensionCatalogRuntime|tabSuspensionRuntimePorts)\b' \
    Sumi SumiTests -g '*.swift' || true
)"
fail_matches "partial suspension runtime installation seam reintroduced" "$partial_install_hits"

suspension_owner_files="$(
  rg --files Sumi \
    | rg '/[^/]*Suspension[^/]*Owner[^/]*\.swift$' || true
)"
fail_matches "suspension responsibility hidden behind an Owner file" "$suspension_owner_files"

if [[ -f "${state_files[0]}" && -f "${state_files[1]}" ]]; then
  state_framework_hits="$(
    rg -n '^import (AppKit|SwiftUI|WebKit)$|\b(BrowserManager|TabManager|WKWebView|Tab)\b' \
      "${state_files[@]}" || true
  )"
  fail_matches "suspension value-state depends on UI/runtime graph types" "$state_framework_hits"
fi

core_files=(
  Sumi/Managers/TabSuspensionPolicy.swift
  Sumi/Managers/TabSuspensionRuntimePorts.swift
  Sumi/Managers/TabSuspensionEligibilityEvaluator.swift
  Sumi/Managers/TabSuspensionExecutor.swift
  Sumi/Managers/TabSuspensionVisibilityLedger.swift
  Sumi/Managers/ProactiveTabSuspensionTimerScheduler.swift
  Sumi/Managers/TabSuspensionReconcileScheduler.swift
  Sumi/Managers/TabSuspensionPolicyChangeMonitor.swift
  Sumi/Managers/ProactiveTabSuspensionLifecycle.swift
  Sumi/Managers/MemoryPressureTabSuspensionHandler.swift
  Sumi/Managers/TabSuspensionController.swift
)

existing_core_files=()
for file in "${core_files[@]}"; do
  [[ -f "$file" ]] && existing_core_files+=("$file")
done

if [[ ${#existing_core_files[@]} -gt 0 ]]; then
  browser_graph_hits="$(
    rg -n '\b(BrowserManager|BrowserWindowState|TabManager)\b' \
      "${existing_core_files[@]}" || true
  )"
  fail_matches "suspension core reaches back into the browser composition graph" "$browser_graph_hits"
fi

mechanism_constructor_hits="$(
  rg -n '\b(TabSuspensionContextSource|TabSuspensionExecutor|ProactiveTabSuspensionLifecycle|MemoryPressureTabSuspensionHandler)\s*\(' \
    Sumi -g '*.swift' -g '!TabSuspensionController.swift' || true
)"
fail_matches "suspension mechanisms constructed outside the lifecycle authority" "$mechanism_constructor_hits"

factory_locator_hits="$(
  rg -n '\b(BrowserManager|TabManager)\b' \
    Sumi/Managers/BrowserManager/BrowserTabSuspensionRuntimeFactory.swift || true
)"
fail_matches "suspension runtime factory reaches into a browser service locator" "$factory_locator_hits"

controller_exposure_hits="$(
  rg -n '^[[:space:]]{4}(let|var)[[:space:]]+(contextSource|executor|proactiveLifecycle|memoryPressureHandler)\b' \
    Sumi/Managers/TabSuspensionController.swift || true
)"
fail_matches "controller exposes private suspension mechanisms" "$controller_exposure_hits"

if [[ -f Sumi/Managers/TabSuspensionController.swift ]]; then
  controller_loc="$(wc -l < Sumi/Managers/TabSuspensionController.swift | tr -d ' ')"
  if (( controller_loc > 160 )); then
    printf 'error: TabSuspensionController exceeds focused lifecycle boundary (%d > 160)\n' \
      "$controller_loc" >&2
    status=1
  fi
fi

for file in \
  Sumi/BrowserRuntime/BrowserKernelGraph.swift \
  Sumi/Managers/BrowserManager/BrowserManager.swift; do
  if ! rg -q 'let tabSuspensionController: TabSuspensionController' "$file"; then
    printf 'error: canonical suspension controller edge missing: %s\n' "$file" >&2
    status=1
  fi
done

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo "tab suspension architecture boundary passed"
