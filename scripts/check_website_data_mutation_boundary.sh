#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Browser-profile website data may only be mutated by the canonical cleanup
# service. Callers must enter through the destructive-cleanup preparer so live
# WebViews and extension participants are quiesced before the WebKit mutation.
#
# WKWebExtensionController owns a separate extension metadata store. Its data
# cleanup remains in the extension residency boundary and is deliberately not
# treated as a browser-profile WKWebsiteDataStore mutation.
production_roots=(App Sumi SidebarChrome FloatingBar Settings UI Packages)
canonical_cleanup_source="Sumi/Services/SumiWebsiteDataCleanupService.swift"
extension_cleanup_source="Sumi/Managers/ExtensionManager/WebExtensionControllerDataCleanupOwner.swift"
profile_mutation_source="Sumi/Services/SumiProfileWebsiteDataMutationService.swift"
mutation_gate_source="Sumi/Managers/WebViewRuntime/WebsiteDataMutationGate.swift"
lease_kernel_source="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Transactions/WebsiteDataMutationLeaseLedger.swift"
status=0

mutation_hits="$({
  rg -n --glob '*.swift' '\.removeData[[:space:]]*\(' "${production_roots[@]}" || true
  rg -n --glob '*.swift' '\.deleteCookie[[:space:]]*\(' "${production_roots[@]}" || true
  rg -n --glob '*.swift' 'WKWebsiteDataStore[[:space:]]*\.[[:space:]]*remove[[:space:]]*\(' \
    "${production_roots[@]}" || true
} | sort -u)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  case "$file" in
    "$canonical_cleanup_source"|"$extension_cleanup_source")
      ;;
    *)
      printf 'error: raw website-data mutation bypasses the canonical cleanup service: %s\n' \
        "$match" >&2
      status=1
      ;;
  esac
done <<< "$mutation_hits"

# High-level cleanup methods are destructive too: calling the protocol instead
# of WKWebsiteDataStore directly still bypasses quiesce unless the caller owns a
# preparer-backed transaction. Keep the allowlist role-based and intentionally
# exclude UI/view-model/settings repositories.
high_level_hits="$(
  rg -n --glob '*.swift' \
    '\.(removeCookies|removeWebsiteData|removeWebsiteDataForDomain|removeWebsiteDataForDomains|removeWebsiteDataForExactHost|clearAllProfileWebsiteData|prunePersistentDataStores)[[:space:]]*\(' \
    "${production_roots[@]}" || true
)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
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
      printf 'error: destructive cleanup call bypasses a preparer-backed mutation boundary: %s\n' \
        "$match" >&2
      status=1
      ;;
  esac
done <<< "$high_level_hits"

# Persistent-store removal is legal only behind Profile's terminal deletion
# method after reference migration and website-data quiescence have completed.
persistent_store_hits="$(
  rg -n --glob '*.swift' \
    '\b(cleanupService|websiteDataCleanupService)\.removePersistentDataStore[[:space:]]*\(' \
    "${production_roots[@]}" || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  case "$file" in
    "$canonical_cleanup_source"|Sumi/Models/Profile/Profile.swift)
      ;;
    *)
      printf 'error: persistent website-data store removal bypasses Profile terminal deletion: %s\n' \
        "$match" >&2
      status=1
      ;;
  esac
done <<< "$persistent_store_hits"

# The package owns only the profile-agnostic lease/admission state machine.
# Product replay keys, restore authority, and all concrete browser/WebKit types
# stay in the app composition layer. This prevents the extraction from becoming
# either a second state owner or an app-specific package in disguise.
if [[ ! -f "$lease_kernel_source" ]]; then
  printf 'error: website-data lease kernel is missing: %s\n' \
    "$lease_kernel_source" >&2
  status=1
else
  kernel_code="$(
    perl -0777 -pe '
      s{""".*?"""}{""}gs;
      s{"(?:\\.|[^"\\])*"}{""}g;
      s{/\*.*?\*/}{}gs;
      s{//[^\n]*}{}g
    ' "$lease_kernel_source"
  )"
  kernel_policy_hits="$(
    rg -n \
      '\b(BrowserManager|BrowserWindowState|Tab|Profile|WKWebView|WKWebsiteDataStore|DeferredAdmissionKey|semanticRevision|replay)\b|^import[[:space:]]+(AppKit|WebKit|SwiftUI)\b' \
      <<< "$kernel_code" || true
  )"
  if [[ -n "$kernel_policy_hits" ]]; then
    printf 'error: website-data lease kernel contains app/WebKit policy:\n%s\n' \
      "$kernel_policy_hits" >&2
    status=1
  fi
fi

kernel_declarations="$(
  rg -n --glob '*.swift' \
    'final[[:space:]]+class[[:space:]]+WebsiteDataMutationLeaseLedger\b' \
    "${production_roots[@]}" || true
)"
expected_kernel_declaration="$(
  rg -n --with-filename \
    'final[[:space:]]+class[[:space:]]+WebsiteDataMutationLeaseLedger\b' \
    "$lease_kernel_source" 2>/dev/null || true
)"
if [[ -z "$expected_kernel_declaration" ]] || \
   [[ "$kernel_declarations" != "$expected_kernel_declaration" ]]; then
  printf 'error: WebsiteDataMutationLeaseLedger must have exactly one production owner in SumiWebRuntime:\n%s\n' \
    "$kernel_declarations" >&2
  status=1
fi

if ! rg -q '^import SumiWebRuntime$' "$mutation_gate_source" || \
   ! rg -q 'private let leaseLedger = WebsiteDataMutationLeaseLedger\(\)' \
     "$mutation_gate_source"; then
  printf 'error: app website-data mutation gate does not compose the SumiWebRuntime lease kernel\n' >&2
  status=1
fi

duplicated_lease_state="$(
  rg -n \
    'private var (activeLease|leaseWaiters|admissionWaiters|admissionGeneration)\b' \
    "$mutation_gate_source" || true
)"
if [[ -n "$duplicated_lease_state" ]]; then
  printf 'error: app mutation gate duplicates package-owned lease/admission state:\n%s\n' \
    "$duplicated_lease_state" >&2
  status=1
fi

if ! rg -q 'enum DeferredAdmissionKey:' "$mutation_gate_source" || \
   ! rg -q 'private var deferredAdmissions:' "$mutation_gate_source" || \
   ! rg -q 'private var restoreRevisionByTabID:' "$mutation_gate_source"; then
  printf 'error: product replay/restore policy escaped the app mutation gate\n' >&2
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  cat >&2 <<'EOF'
Website-data mutation boundary audit failed.
Route browser-profile mutations through SumiWebsiteDataCleanupServicing and
attach the owning caller to the destructive-cleanup preparer. Keep the generic
lease/admission kernel in SumiWebRuntime and product replay policy in the app.
EOF
  exit "$status"
fi

echo "website-data mutation boundary audit passed"
