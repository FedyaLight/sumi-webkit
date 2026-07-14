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

for file in "$bridge" "$opening" "$opening_runtime" "$initial" "$content" "$native" \
  "$residency" "$retention" "$loading" "$settlement" "$deferred" \
  "$weak_events" "$browser_aux"; do
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
  Sumi/Managers/ExtensionManager/ExtensionBridge.swift
rg -q 'presentation\?\.retire\(\)' "$opening"
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
