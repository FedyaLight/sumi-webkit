#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

# Browser-profile website data may only be mutated by the canonical cleanup
# service. Callers must enter through the destructive-cleanup preparer so live
# WebViews and extension participants are quiesced before the WebKit mutation.
# WKWebExtensionController owns a separate extension metadata store and remains
# in the extension residency boundary.
production_roots=(App Sumi SidebarChrome CommandPalette Settings UI Packages)
canonical_cleanup_source="Sumi/Services/SumiWebsiteDataCleanupService.swift"
extension_cleanup_source="Sumi/Managers/ExtensionManager/WebExtensionControllerDataCleanupOwner.swift"
profile_mutation_source="Sumi/Services/SumiProfileWebsiteDataMutationService.swift"
mutation_gate_source="Sumi/Managers/WebViewRuntime/WebsiteDataMutationGate.swift"
lease_kernel_source="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Transactions/WebsiteDataMutationLeaseLedger.swift"
participant_kernel_source="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Transactions/WebsiteDataCleanupParticipantLedger.swift"
terminal_receipt_source="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Transactions/WebsiteDataCleanupTerminalReceipt.swift"
navigation_barrier_source="Sumi/Managers/WebViewRuntime/WebsiteDataCleanupNavigationBarrier.swift"
cleanup_transaction_source="Sumi/Managers/WebViewRuntime/WebsiteDataCleanupTransaction.swift"

for source in \
  "$canonical_cleanup_source" \
  "$extension_cleanup_source" \
  "$profile_mutation_source" \
  "$mutation_gate_source" \
  "$lease_kernel_source" \
  "$participant_kernel_source" \
  "$terminal_receipt_source" \
  "$navigation_barrier_source" \
  "$cleanup_transaction_source"; do
  guard_require_file "$source"
done

require_source_pattern() {
  local file="$1"
  local pattern="$2"
  local failure="$3"
  local count
  count="$(guard_count_matches "$pattern" "$file")" || return
  if (( count == 0 )); then
    guard_record_failure "$failure"
  fi
}

printf '%s\n' 'Website-data mutation boundary audit'
printf '%s\n' '------------------------------------'

remove_data_hits="$(
  guard_capture_matches \
    '\.removeData[[:space:]]*\(' \
    --glob '*.swift' "${production_roots[@]}"
)"
delete_cookie_hits="$(
  guard_capture_matches \
    '\.deleteCookie[[:space:]]*\(' \
    --glob '*.swift' "${production_roots[@]}"
)"
static_store_remove_hits="$(
  guard_capture_matches \
    'WKWebsiteDataStore[[:space:]]*\.[[:space:]]*remove[[:space:]]*\(' \
    --glob '*.swift' "${production_roots[@]}"
)"
mutation_hits="$(
  printf '%s\n%s\n%s\n' \
    "$remove_data_hits" \
    "$delete_cookie_hits" \
    "$static_store_remove_hits" \
    | sed '/^$/d' \
    | sort -u
)"

while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  file="${match%%:*}"
  case "$file" in
    "$canonical_cleanup_source"|"$extension_cleanup_source")
      ;;
    *)
      guard_record_failure \
        "raw website-data mutation bypasses the canonical cleanup service: $match"
      ;;
  esac
done <<< "$mutation_hits"

# High-level cleanup protocols are destructive too. Calling one directly still
# bypasses quiesce unless the role owns a preparer-backed transaction.
high_level_hits="$(
  guard_capture_matches \
    '\.(removeCookies|removeWebsiteData|removeWebsiteDataForDomain|removeWebsiteDataForDomains|removeWebsiteDataForExactHost|clearAllProfileWebsiteData|prunePersistentDataStores)[[:space:]]*\(' \
    --glob '*.swift' "${production_roots[@]}"
)"
while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  file="${match%%:*}"
  case "$file" in
    "$canonical_cleanup_source"|\
    "$profile_mutation_source"|\
    Sumi/Models/Profile/Profile.swift|\
    Sumi/Services/SumiManualWebsiteDataCleanupService.swift|\
    Sumi/Services/SumiBrowsingDataCleanupService.swift|\
    Sumi/Services/SumiSiteDataPolicyEnforcementService.swift|\
    Sumi/Services/BrowserPrivacyService.swift)
      ;;
    *)
      guard_record_failure \
        "destructive cleanup call bypasses a preparer-backed mutation boundary: $match"
      ;;
  esac
done <<< "$high_level_hits"

# Persistent-store removal is legal only behind Profile's terminal deletion
# method after reference migration and website-data quiescence complete.
persistent_store_hits="$(
  guard_capture_matches \
    '\b(cleanupService|websiteDataCleanupService)\.removePersistentDataStore[[:space:]]*\(' \
    --glob '*.swift' "${production_roots[@]}"
)"
while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  file="${match%%:*}"
  case "$file" in
    "$canonical_cleanup_source"|Sumi/Models/Profile/Profile.swift)
      ;;
    *)
      guard_record_failure \
        "persistent website-data store removal bypasses Profile terminal deletion: $match"
      ;;
  esac
done <<< "$persistent_store_hits"

# The package owns only the profile-agnostic lease/admission state machine.
# Product replay keys, restore authority and concrete browser/WebKit types stay
# in the app composition layer.
kernel_code="$(
  perl -0777 -pe '
    s{""".*?"""}{""}gs;
    s{"(?:\\.|[^"\\])*"}{""}g;
    s{/\*.*?\*/}{}gs;
    s{//[^\n]*}{}g
  ' "$lease_kernel_source"
)"
kernel_policy_hits="$(
  guard_capture_matches \
    '\b(BrowserManager|BrowserWindowState|Tab|Profile|WKWebView|WKWebsiteDataStore|DeferredAdmissionKey|semanticRevision|replay)\b|^import[[:space:]]+(AppKit|WebKit|SwiftUI)\b' \
    - <<< "$kernel_code"
)"
if [[ -n "$kernel_policy_hits" ]]; then
  guard_record_failure \
    "website-data lease kernel contains app/WebKit policy: $kernel_policy_hits"
fi

lease_owner_hits="$(
  guard_capture_matches \
    'final[[:space:]]+class[[:space:]]+WebsiteDataMutationLeaseLedger\b' \
    --glob '*.swift' "${production_roots[@]}"
)"
lease_owner_count="$(
  printf '%s\n' "$lease_owner_hits" | sed '/^$/d' | wc -l | tr -d '[:space:]'
)"
if [[ "$lease_owner_count" != 1 || "$lease_owner_hits" != "$lease_kernel_source:"* ]]; then
  guard_record_failure \
    "WebsiteDataMutationLeaseLedger must have exactly one production owner in SumiWebRuntime: $lease_owner_hits"
fi

require_source_pattern \
  "$mutation_gate_source" \
  '^import SumiWebRuntime$' \
  'app website-data mutation gate does not import the SumiWebRuntime lease kernel'
require_source_pattern \
  "$mutation_gate_source" \
  'private let leaseLedger = WebsiteDataMutationLeaseLedger\(\)' \
  'app website-data mutation gate does not compose the SumiWebRuntime lease kernel'

# Exact WebView participation, navigation phases and terminal-event receipt
# generations form one product-agnostic transaction kernel. Tab ownership,
# WebKit effects and restore commands stay in the app adapter.
for kernel_source in "$participant_kernel_source" "$terminal_receipt_source"; do
  participant_kernel_code="$(
    perl -0777 -pe '
      s{""".*?"""}{""}gs;
      s{"(?:\\.|[^"\\])*"}{""}g;
      s{/\*.*?\*/}{}gs;
      s{//[^\n]*}{}g
    ' "$kernel_source"
  )"
  participant_policy_hits="$(
    guard_capture_matches \
      '\b(BrowserManager|BrowserWindowState|Tab|Profile|TabMainFrameReloadCommandOutcome|DeferredAdmissionKey|SumiSurface)\b|^import[[:space:]]+(Navigation|SumiDomain|SwiftUI)\b' \
      - <<< "$participant_kernel_code"
  )"
  if [[ -n "$participant_policy_hits" ]]; then
    guard_record_failure \
      "website-data participant kernel contains app/product policy ($kernel_source): $participant_policy_hits"
  fi
done

for declaration in \
  WebsiteDataCleanupParticipantLedger \
  WebsiteDataCleanupTerminalReceipt; do
  declaration_hits="$(
    guard_capture_matches \
      "final[[:space:]]+class[[:space:]]+${declaration}\\b" \
      --glob '*.swift' "${production_roots[@]}"
  )"
  expected_source="$participant_kernel_source"
  if [[ "$declaration" == WebsiteDataCleanupTerminalReceipt ]]; then
    expected_source="$terminal_receipt_source"
  fi
  declaration_count="$(
    printf '%s\n' "$declaration_hits" \
      | sed '/^$/d' \
      | wc -l \
      | tr -d '[:space:]'
  )"
  if [[ "$declaration_count" != 1 || "$declaration_hits" != "$expected_source:"* ]]; then
    guard_record_failure \
      "$declaration must have exactly one production owner in SumiWebRuntime: $declaration_hits"
  fi
done

require_source_pattern \
  "$navigation_barrier_source" \
  '^import SumiWebRuntime$' \
  'app cleanup navigation barrier does not import the participant kernel'
require_source_pattern \
  "$navigation_barrier_source" \
  'private let participantLedger = WebsiteDataCleanupParticipantLedger\(\)' \
  'app cleanup navigation barrier does not compose the participant kernel'

duplicated_participant_state="$(
  guard_capture_matches \
    'enum ParticipantPhase\b|class TerminalWait\b|struct RestoreStartCandidate\b|participantsByWebViewID' \
    "$navigation_barrier_source"
)"
if [[ -n "$duplicated_participant_state" ]]; then
  guard_record_failure \
    "app cleanup navigation barrier duplicates package-owned participant state: $duplicated_participant_state"
fi

require_source_pattern \
  "$navigation_barrier_source" \
  '\blet tab: Tab\b' \
  'Tab ownership escaped the app cleanup adapter'
require_source_pattern \
  "$navigation_barrier_source" \
  '\bwaitForMutationPermission\b' \
  'mutation permission escaped the app cleanup adapter'
require_source_pattern \
  "$navigation_barrier_source" \
  '\bloadBlankNavigation\b' \
  'physical WebKit policy escaped the app cleanup adapter'

duplicated_lease_state="$(
  guard_capture_matches \
    'private var (activeLease|leaseWaiters|admissionWaiters|admissionGeneration)\b' \
    "$mutation_gate_source"
)"
if [[ -n "$duplicated_lease_state" ]]; then
  guard_record_failure \
    "app mutation gate duplicates package-owned lease/admission state: $duplicated_lease_state"
fi

duplicate_transaction_admission="$(
  guard_capture_matches \
    'transactionSlot(IsOwned|Waiters)|acquireTransactionSlot|releaseTransactionSlot' \
    "$cleanup_transaction_source"
)"
if [[ -n "$duplicate_transaction_admission" ]]; then
  guard_record_failure \
    "cleanup transaction duplicates package-owned exclusive admission: $duplicate_transaction_admission"
fi

require_source_pattern \
  "$mutation_gate_source" \
  'enum DeferredAdmissionKey:' \
  'product replay keys escaped the app mutation gate'
require_source_pattern \
  "$mutation_gate_source" \
  'private var deferredAdmissions:' \
  'product deferred-admission policy escaped the app mutation gate'
require_source_pattern \
  "$mutation_gate_source" \
  'private var restoreRevisionByTabID:' \
  'product restore-revision policy escaped the app mutation gate'

if (( guard_failures > 0 )); then
  printf '%s\n' \
    'Route browser-profile mutations through SumiWebsiteDataCleanupServicing and attach the owning caller to the destructive-cleanup preparer. Keep the generic lease/admission kernel in SumiWebRuntime and product replay policy in the app.' \
    >&2
fi
guard_finish 'website-data mutation boundary audit'
