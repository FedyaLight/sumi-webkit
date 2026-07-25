#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

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
metadata_store='Sumi/Managers/ExtensionManager/ExtensionInstallationMetadataStore.swift'
scoped_retirement='Sumi/Managers/ExtensionManager/ExtensionScopedRuntimeRetirement.swift'
publication_resolver='Sumi/Managers/ExtensionManager/ExtensionAuxiliaryWindowPublicationResolver.swift'
load_resolver='Sumi/Managers/ExtensionManager/ExtensionRequestedTabLoadResolver.swift'
runtime_admission='Sumi/Managers/ExtensionManager/ExtensionRequestedTabRuntimeAdmission.swift'
target_resolver='Sumi/Managers/ExtensionManager/ExtensionRequestedTabTargetResolver.swift'
opening_service='Sumi/Managers/ExtensionManager/ExtensionRequestedTabOpeningService.swift'

reject_production_pattern() {
  local message="$1"
  local pattern="$2"
  shift 2
  local matches
  matches="$(guard_capture_matches "$pattern" "$@")" || return
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
    printf 'error: %s\n' "$message" >&2
    return 1
  fi
}

require_production_pattern() {
  local message="$1"
  local pattern="$2"
  shift 2
  local count
  count="$(guard_count_matches "$pattern" "$@")" || return
  if (( count == 0 )); then
    printf 'error: %s\n' "$message" >&2
    return 1
  fi
}

for file in "$service" "$delegate" "$registry" "$resolver" \
  "$composition" "$transaction" "$coordinator" "$claim_ledger" \
  "$page_resolution" "$page_owner" "$options_bridge" "$toolbar_options" \
  "$metadata_store" "$scoped_retirement" "$publication_resolver" \
  "$load_resolver" "$runtime_admission" "$target_resolver" "$opening_service"; do
  guard_require_file "$file"
done
require_production_pattern 'options service lost its presentation receipt' \
  'ExtensionOptionsWindowPresentationReceipt' "$service"
require_production_pattern 'options service lost its presentation coordinator' \
  'ExtensionOptionsWindowPresentationCoordinator\.present' "$service"
require_production_pattern 'options coordinator lost its presentation claim' \
  'let claim = service\.issuePresentationClaim' "$coordinator"
require_production_pattern 'options coordinator lost mutation admission' \
  'await runtime\.websiteDataAdmission\.wait' "$coordinator"
claim_line="$(guard_capture_matches 'let claim = service\.issuePresentationClaim' "$coordinator" | cut -d: -f1)"
await_line="$(guard_capture_matches 'await runtime\.websiteDataAdmission\.wait' "$coordinator" | cut -d: -f1)"
if [[ -z "$claim_line" || -z "$await_line" ]] || (( claim_line >= await_line )); then
  echo 'error: options presentation claim must be issued before the first suspension' >&2
  exit 1
fi
require_production_pattern 'options coordinator lost current-presentation admission' \
  'service\.presentationIsCurrent' "$coordinator"
require_production_pattern 'options service lost exact registry/runtime admission' \
  'registry\.isCurrent\(claim\) && runtime\.isCurrent\(receipt\)' "$service"
reject_production_pattern 'options callback admission regained mutable identity fallback' \
  'fallbackProfileId|profileId\(for: extensionContext\)|currentProfile\(\)' \
  "$service" "$composition" "$transaction" "$coordinator"
reject_production_pattern 'options async presentation regained the ExtensionManager root' \
  '\bExtensionManager\b' "$service" "$transaction" "$coordinator"
require_production_pattern 'options callback lost its captured profile' \
  'let profile: Profile' "$composition"
require_production_pattern 'options callback lost the exact extension configuration' \
  'evidence\.context\.webViewConfiguration' "$composition"
reject_production_pattern 'options callback replaced exact WebKit extension configuration' \
  'auxiliaryWebViewConfiguration' "$composition"
require_production_pattern 'options callback lost installed-record revision evidence' \
  'installedRecordRevision: UInt64' "$composition"
enabled_record_checks="$(guard_count_matches '\$0\.id == evidence\.extensionID && \$0\.isEnabled' "$composition")"
if (( enabled_record_checks < 2 )); then
  echo 'error: options capture and revalidation must require an enabled record' >&2
  exit 1
fi
require_production_pattern 'options callback lost website-data-store identity capture' \
  'configuration\.websiteDataStore === profile\.dataStore' "$composition"
require_production_pattern 'options callback lost controller identity capture' \
  'configuration\.webExtensionController === evidence\.controller' "$composition"
require_production_pattern 'options callback lost website-data-store revalidation' \
  'receipt\.configuration\.websiteDataStore' "$composition"
require_production_pattern 'options callback lost profile data-store revalidation' \
  '=== receipt\.profile\.dataStore' "$composition"
require_production_pattern 'options callback lost controller revalidation' \
  'receipt\.configuration\.webExtensionController' "$composition"
require_production_pattern 'options callback lost exact controller identity revalidation' \
  '=== evidence\.controller' "$composition"
require_production_pattern 'options callback lost visited-link-store evidence' \
  'configuration\.sumiVisitedLinkStoreObject' "$composition"
require_production_pattern 'options resolver lost exact context identity' \
  'controller\.extensionContext\(for: sdkURL\) === context' "$resolver"
require_production_pattern 'options resolver lost package-file validation' \
  'FileManager\.default\.fileExists' "$resolver"
runtime_options_sources=(
  "$resolver"
  "$service"
  "$coordinator"
  "$transaction"
  "$composition"
  "$options_bridge"
  "$toolbar_options"
)
reject_production_pattern 'options URL regained recursive manifest/baseURL fallback' \
  'preferredURL|manifestURL|context\.baseURL|persistedPath|runtimeCatalog' \
  "${runtime_options_sources[@]}"
reject_production_pattern 'dead legacy options URL resolution surface returned' \
  'func computeOptionsPageURL|func resolvedURL\s*\(' \
  Sumi/Managers/ExtensionManager --glob '*.swift'
require_production_pattern 'installation metadata lost stored options-page resolution' \
  'ExtensionOptionsPageResolution\.storedPath' "$metadata_store"
reject_production_pattern \
  'options-window parallel dictionaries or extension-ID callback retirement returned' \
  'private(set)? var windows:|delegates: \[String:|profileIDsByExtensionID|cleanupWindow\(\s*for:' \
  "$service"

delegate_identity_hits="$(
  guard_capture_matches 'extensionI[dD]: String|private let extensionI[Dd]' "$service" \
    | guard_capture_matches 'ExtensionOptionsWindowDelegate|private let' -
)"
if [[ -n "$delegate_identity_hits" ]]; then
  printf '%s\n' "$delegate_identity_hits" >&2
  echo 'error: options-window delegate must retire an exact receipt, not an extension ID' >&2
  exit 1
fi

require_production_pattern 'options registry lost exact receipt identity' \
  'struct ExtensionOptionsWindowReceipt: Hashable, Sendable' "$registry"
require_production_pattern 'options claim ledger lost exact claim identity' \
  'struct ExtensionOptionsWindowPresentationClaim: Hashable, Sendable' "$claim_ledger"
require_production_pattern 'options receipt lost registration identity' \
  'registrationID: UUID' "$registry"
require_production_pattern 'options registry lost exact receipt comparison' \
  'registrationsByExtensionID\[receipt.extensionID\]\?\.receipt == receipt' "$registry"
require_production_pattern 'options registry lost current claim admission' \
  'presentationClaims\.isCurrent\(claim\)' "$registry"
require_production_pattern 'options registry lost claim invalidation' \
  'presentationClaims\.invalidate' "$registry"
require_production_pattern 'options service lost global claim invalidation' \
  'invalidateAllPresentationClaims' "$service"
require_production_pattern 'options service lost receipt-backed claim invalidation' \
  'invalidatePresentationClaims\(backedBy:' "$service"
require_production_pattern 'options service lost its registry owner' \
  'private let registry = ExtensionOptionsWindowRegistry\(\)' "$service"
require_production_pattern 'options service lost exact retirement' \
  'func retire\(' "$service"
require_production_pattern 'options transaction lost delegate binding' \
  'delegate.bind\(tracked\)' "$transaction"
require_production_pattern 'options transaction lost window publication' \
  'createdWindow\.orderFront' "$transaction"
receipt_checks="$(guard_count_matches 'service\.receipt\(for: receipt\.evidence\.extensionID\)' "$transaction")"
if (( receipt_checks < 2 )); then
  echo 'error: options registration must be exact before and after orderFront' >&2
  exit 1
fi
# The options page is loaded only after the window is ordered front and made
# key, so a reentrant close/replacement callback can invalidate the claim
# between those AppKit phases. Every stage of the transaction stays gated:
# entry, post-layout, post-delegate, post-tracking, and post-load.
options_order_front_line="$(guard_capture_matches 'createdWindow\.makeKey\(\)' "$transaction" | tail -1 | cut -d: -f1)"
options_load_line="$(guard_capture_matches 'webView\.load\(URLRequest\(url: receipt\.optionsURL\)\)' "$transaction" | tail -1 | cut -d: -f1)"
if [[ -z "$options_order_front_line" || -z "$options_load_line" ]] \
    || (( options_order_front_line >= options_load_line )); then
  echo 'error: options page load must follow the explicit orderFront/makeKey phases' >&2
  exit 1
fi
stage_gate_count="$(guard_count_matches 'guard isCurrent' "$transaction")"
if (( stage_gate_count < 5 )); then
  echo 'error: options transaction lost a presentation-claim stage gate' >&2
  exit 1
fi
require_production_pattern 'options service lost untracked web-view retirement protection' \
  'registry\.owns\(webView\) == false' "$service"
require_production_pattern 'options service lost untracked window retirement protection' \
  'registry\.owns\(window\) == false' "$service"
require_production_pattern 'options service lost replacement-window retirement protection' \
  'registry\.owns\(registration\.window\) == false' "$service"
require_production_pattern 'scoped runtime retirement lost its exact options receipt' \
  'let optionsWindowReceipt = optionsWindows\.receipt' "$scoped_retirement"
reject_production_pattern \
  'scoped runtime retirement regressed to extension-ID resource cleanup' \
  'optionsWindows\.closeWindow\(for: extensionID\)' "$scoped_retirement"
require_production_pattern 'auxiliary publication lost profile-scoped context lookup' \
  'profileRuntime\.contexts\(for: profileID\)\[ownerExtensionID\]' "$publication_resolver"
reject_production_pattern \
  'nil context override returned as ordinary-tab ownership evidence' \
  'registerOrdinaryTabWhenRuntimeIsReady|ordinaryTabRuntimeNotReady' \
  Sumi/Managers/ExtensionManager
require_production_pattern 'requested-tab load resolver lost explicit ownership' \
  'enum Ownership' "$load_resolver"
require_production_pattern 'requested-tab load resolver lost fail-closed ownership' \
  'case unresolvedExtensionOwned' "$load_resolver"
require_production_pattern 'requested-tab admission lost ordinary-request classification' \
  'load\.isOrdinaryBrowserRequest' "$runtime_admission"
require_production_pattern 'requested-tab admission lost publication readiness' \
  'publicationControllerIsReady' "$runtime_admission"
require_production_pattern 'requested-tab admission lost extension-URL identity rejection' \
  'ExtensionURLIdentity\.isOwned\(tab\.url\) == false' "$runtime_admission"
require_production_pattern 'requested-tab targeting lost residence policy' \
  'enum ExtensionRequestedTabResidencePolicy' "$target_resolver"
require_production_pattern 'requested-tab targeting lost ordinary-browser residence' \
  'case ordinaryBrowser' "$target_resolver"
require_production_pattern 'requested-tab opening lost resolved residence policy' \
  'residencePolicy: residencePolicy' "$opening_service"
reject_production_pattern \
  'extension retirement regained global auxiliary-window teardown' \
  'closeAuxiliaryWindowSessions' Sumi --glob '*.swift'

for limit_and_file in \
  "190:$service" \
  "130:$registry" \
  "100:$resolver" \
  "200:$composition" \
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
