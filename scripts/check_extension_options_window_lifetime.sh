#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

service='Sumi/Managers/ExtensionManager/ExtensionOptionsWindowService.swift'
delegate='Sumi/Managers/ExtensionManager/ExtensionOptionsWindowDelegate.swift'
registry='Sumi/Managers/ExtensionManager/ExtensionOptionsWindowRegistry.swift'
resolver='Sumi/Managers/ExtensionManager/ExtensionOptionsPageResolver.swift'
composition='Sumi/Managers/ExtensionManager/ExtensionOptionsWindowCallbackComposition.swift'
transaction='Sumi/Managers/ExtensionManager/ExtensionOptionsWindowPresentationTransaction.swift'
coordinator='Sumi/Managers/ExtensionManager/ExtensionOptionsWindowPresentationCoordinator.swift'
claim_ledger='Sumi/Managers/ExtensionManager/ExtensionOptionsWindowPresentationClaimLedger.swift'
page_resolution='Sumi/Managers/ExtensionManager/ExtensionOptionsPageResolution.swift'
page_owner='Sumi/Managers/ExtensionManager/ExtensionPageResolutionOwner.swift'
options_bridge='Sumi/Managers/ExtensionManager/ExtensionControllerDelegateBridge+Options.swift'
toolbar_options='Sumi/Managers/ExtensionManager/SumiExtensionToolbarActionSurface.swift'
options_tests='SumiTests/SafariExtensionWindowAndOptionsAdmissionTests.swift'

for file in "$service" "$delegate" "$registry" "$resolver" \
  "$composition" "$transaction" "$coordinator" "$claim_ledger" \
  "$page_resolution" "$page_owner" "$options_bridge" "$toolbar_options"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: extension options-window role missing: %s\n' "$file" >&2
    exit 1
  fi
done
rg -q 'ExtensionOptionsWindowPresentationReceipt' "$service"
rg -q 'ExtensionOptionsWindowPresentationCoordinator\.present' "$service"
rg -q 'let claim = service\.issuePresentationClaim' "$coordinator"
rg -q 'await runtime\.waitForWebsiteDataMutationAdmission' "$coordinator"
claim_line="$(rg -n 'let claim = service\.issuePresentationClaim' "$coordinator" | cut -d: -f1)"
await_line="$(rg -n 'await runtime\.waitForWebsiteDataMutationAdmission' "$coordinator" | cut -d: -f1)"
if (( claim_line >= await_line )); then
  echo 'error: options presentation claim must be issued before the first suspension' >&2
  exit 1
fi
rg -q 'service\.presentationIsCurrent' "$coordinator"
rg -q 'registry\.isCurrent\(claim\) && runtime\.isCurrent\(receipt\)' "$service"
if rg -n 'fallbackProfileId|profileId\(for: extensionContext\)|currentProfile\(\)' \
  "$service" "$composition" "$transaction" "$coordinator"; then
  echo 'error: options callback admission regained mutable identity fallback' >&2
  exit 1
fi
if rg -n '\bExtensionManager\b' "$service" "$transaction" "$coordinator"; then
  echo 'error: options async presentation regained the ExtensionManager root' >&2
  exit 1
fi
rg -q 'let profile: Profile' "$composition"
rg -q 'evidence\.context\.webViewConfiguration' "$composition"
if rg -n 'auxiliaryWebViewConfiguration' "$composition"; then
  echo 'error: options callback replaced exact WebKit extension configuration' >&2
  exit 1
fi
rg -q 'installedRecordRevision: UInt64' "$composition"
if (( $(rg -c '\$0\.id == evidence\.extensionID && \$0\.isEnabled' "$composition") < 2 )); then
  echo 'error: options capture and revalidation must require an enabled record' >&2
  exit 1
fi
rg -q 'configuration\.websiteDataStore === profile\.dataStore' "$composition"
rg -q 'configuration\.webExtensionController === evidence\.controller' \
  "$composition"
rg -q 'receipt\.configuration\.websiteDataStore' "$composition"
rg -q '=== receipt\.profile\.dataStore' "$composition"
rg -q 'receipt\.configuration\.webExtensionController' "$composition"
rg -q '=== evidence\.controller' "$composition"
rg -q 'configuration\.sumiVisitedLinkStoreObject' "$composition"
rg -q 'controller\.extensionContext\(for: sdkURL\) === context' "$resolver"
rg -q 'FileManager\.default\.fileExists' "$resolver"
runtime_options_sources=(
  "$resolver"
  "$service"
  "$coordinator"
  "$transaction"
  "$composition"
  "$options_bridge"
  "$toolbar_options"
)
if rg -n 'preferredURL|manifestURL|context\.baseURL|persistedPath|runtimeCatalog' \
  "${runtime_options_sources[@]}"; then
  echo 'error: options URL regained recursive manifest/baseURL fallback' >&2
  exit 1
fi
if rg -n 'func computeOptionsPageURL|func resolvedURL\s*\(' \
  Sumi/Managers/ExtensionManager --glob '*.swift'; then
  echo 'error: dead legacy options URL resolution surface returned' >&2
  exit 1
fi
rg -q 'ExtensionOptionsPageResolution\.storedPath' \
  Sumi/Managers/ExtensionManager/ExtensionInstallationMetadataStore.swift

if rg -n 'private(set)? var windows:|delegates: \[String:|profileIDsByExtensionID|cleanupWindow\(\s*for:' "$service"; then
  echo 'error: options-window parallel dictionaries or extension-ID callback retirement returned' >&2
  exit 1
fi

if rg -n 'extensionI[dD]: String|private let extensionI[Dd]' "$service" | rg 'ExtensionOptionsWindowDelegate|private let'; then
  echo 'error: options-window delegate must retire an exact receipt, not an extension ID' >&2
  exit 1
fi

rg -q 'struct ExtensionOptionsWindowReceipt: Hashable, Sendable' "$registry"
rg -q 'struct ExtensionOptionsWindowPresentationClaim: Hashable, Sendable' "$claim_ledger"
rg -q 'registrationID: UUID' "$registry"
rg -q 'registrationsByExtensionID\[receipt.extensionID\]\?\.receipt == receipt' "$registry"
rg -q 'presentationClaims\.isCurrent\(claim\)' "$registry"
rg -q 'presentationClaims\.invalidate' "$registry"
rg -q 'invalidateAllPresentationClaims' "$service"
rg -q 'invalidatePresentationClaims\(backedBy:' "$service"
rg -q 'private let registry = ExtensionOptionsWindowRegistry\(\)' "$service"
rg -q 'func retire\(' "$service"
rg -q 'delegate.bind\(tracked\)' "$transaction"
rg -q 'createdWindow\.orderFront' "$transaction"
if (( $(rg -Fc 'service.receipt(for: receipt.evidence.extensionID)' "$transaction") < 2 )); then
  echo 'error: options registration must be exact before and after orderFront' >&2
  exit 1
fi
if (( $(rg -c 'guard isCurrent' "$transaction") < 7 )); then
  echo 'error: options transaction lost a presentation-claim stage gate' >&2
  exit 1
fi
rg -Fq 'registry.owns(webView) == false' "$service"
rg -Fq 'registry.owns(window) == false' "$service"
rg -Fq 'registry.owns(registration.window) == false' "$service"
rg -q 'let optionsWindowReceipt = optionsWindows.receipt' \
  'Sumi/Managers/ExtensionManager/ExtensionScopedRuntimeRetirement.swift'
if rg -n 'optionsWindows\.closeWindow\(for: extensionID\)' \
  'Sumi/Managers/ExtensionManager/ExtensionScopedRuntimeRetirement.swift'; then
  echo 'error: scoped runtime retirement regressed to extension-ID resource cleanup' >&2
  exit 1
fi
rg -Fq 'profileRuntime.contexts(for: profileID)[ownerExtensionID]' \
  'Sumi/Managers/ExtensionManager/ExtensionAuxiliaryWindowPublicationResolver.swift'
if rg -n 'registerOrdinaryTabWhenRuntimeIsReady|ordinaryTabRuntimeNotReady' \
  Sumi/Managers/ExtensionManager SumiTests; then
  echo 'error: nil context override returned as ordinary-tab ownership evidence' >&2
  exit 1
fi
rg -q 'enum Ownership' \
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabLoadResolver.swift
rg -q 'case unresolvedExtensionOwned' \
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabLoadResolver.swift
rg -q 'load\.isOrdinaryBrowserRequest' \
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabRuntimeAdmission.swift
rg -q 'publicationControllerIsReady' \
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabRuntimeAdmission.swift
rg -q 'ExtensionURLIdentity\.isOwned\(tab\.url\) == false' \
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabRuntimeAdmission.swift
rg -q 'enum ExtensionRequestedTabResidencePolicy' \
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabTargetResolver.swift
rg -q 'case ordinaryBrowser' \
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabTargetResolver.swift
rg -q 'residencePolicy: residencePolicy' \
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabOpeningService.swift
rg -q 'testLoadResolverKeepsUnresolvedExtensionURLFailClosed' \
  SumiTests/ExtensionRequestedTabServicesTests.swift
rg -q 'testUnresolvedExtensionOwnedRequestFailsBeforeCreatingTab' \
  SumiTests/ExtensionRequestedTabServicesTests.swift
rg -q 'XCTAssertTrue\(lifecycleEvents\.isEmpty\)' \
  SumiTests/AuxiliaryWindowLifecycleTests.swift
rg -q 'testSupersededReceiptCannotRetireReregisteredSameWindowIdentity' \
  SumiTests/ExtensionOptionsWindowServiceTests.swift
rg -q 'stale options admission rejected' \
  "$options_tests"
rg -q 'Current Profile B' "$options_tests"
rg -q 'replacingPackageRoot' "$options_tests"
rg -q 'disabled options record rejected' \
  "$options_tests"
rg -q 'older options presentation suspended' \
  "$options_tests"
rg -q 'ReentrantOptionsWindow' \
  "$options_tests"
rg -q 'testAuxiliaryCloseReentrancyCannotRetireReplacementOptionsWindow' \
  SumiTests/ExtensionScopedRuntimeRetirementTests.swift
rg -q 'testCapturedAuxiliaryReceiptCannotCloseReentrantReplacementSession' \
  SumiTests/ExtensionScopedRuntimeRetirementTests.swift
if rg -n 'closeAuxiliaryWindowSessions' Sumi SumiTests --glob '*.swift'; then
  echo 'error: extension retirement regained global auxiliary-window teardown' >&2
  exit 1
fi

for limit_and_file in \
  "190:$service" \
  "130:$registry" \
  "100:$resolver" \
  "150:$composition" \
  "130:$transaction" \
  "100:$coordinator" \
  "70:$claim_ledger"; do
  limit="${limit_and_file%%:*}"
  file="${limit_and_file#*:}"
  lines="$(wc -l < "$file" | tr -d ' ')"
  if (( lines > limit )); then
    printf 'error: extension options-window role grew beyond its boundary (%s: %s > %s)\n' \
      "$file" "$lines" "$limit" >&2
    exit 1
  fi
done

echo 'extension options-window lifetime boundary passed'
