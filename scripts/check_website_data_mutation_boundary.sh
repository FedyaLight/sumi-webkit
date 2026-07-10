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

if [[ "$status" -ne 0 ]]; then
  cat >&2 <<'EOF'
Website-data mutation boundary audit failed.
Route browser-profile mutations through SumiWebsiteDataCleanupServicing and
attach the owning caller to the destructive-cleanup preparer.
EOF
  exit "$status"
fi

echo "website-data mutation boundary audit passed"
