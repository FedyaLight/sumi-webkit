#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Canonical ownership model:
# - WebViewSessionRepository is the process-wide placement source of truth.
# - WebViewSessionHandle is Tab's narrow detached-placement/read boundary.
# - tracked window mutations stay package-only behind WebViewTrackingLifecycleOwner.
# - Tab stores no WKWebView mirror and exposes no ownership façade.
# - TabMainFrameLoadRuntime alone owns the raw pending-load/intent ledger.
# - TabMainFrameRuntimeTransaction coordinates lifecycle/recovery transitions.
# - TabCommittedDocumentRuntime alone owns durable committed-document state.

production_roots=(App Sumi SidebarChrome FloatingBar Settings UI)
all_swift_roots=("${production_roots[@]}" Packages SumiTests SumiUITests)
repository_source="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Session/WebViewSessionRepository.swift"
handle_source="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Session/WebViewSessionHandle.swift"
main_frame_load_runtime="Sumi/Models/Tab/TabMainFrameLoadRuntime.swift"
web_view_rebuild_epoch="Sumi/Models/Tab/TabWebViewRebuildEpoch.swift"
main_frame_transaction="Sumi/Models/Tab/TabMainFrameRuntimeTransaction.swift"
committed_document_runtime="Sumi/Models/Tab/TabCommittedDocumentRuntime.swift"
status=0

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

for required in "$repository_source" "$handle_source" "$main_frame_load_runtime" \
  "$web_view_rebuild_epoch" \
  "$main_frame_transaction" "$committed_document_runtime"; do
  if [[ ! -f "$required" ]]; then
    printf 'error: required WebView/main-frame architecture source missing: %s\n' \
      "$required" >&2
    status=1
  fi
done

# Tombstones: the split registry/session/owner model must not return.
legacy_type_hits="$(
  rg -n '\b(TabWebViewSession|WindowWebViewRegistry|TabWebViewOwnershipOwner)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "deleted WebView ownership type reintroduced" "$legacy_type_hits"

# These assignment-shaped Tab APIs silently mutate a mirror and are forbidden.
legacy_assignment_hits="$(
  rg -n '\b(assignWebViewToWindow|assignPrimaryWebView|setPrimaryWindowId|setCurrentWebView|setExistingWebView|syncFromTabIfNeeded|adoptDetachedState)\s*\(|\.rebind\s*\(\s*to:' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "legacy mirror-assignment API reintroduced" "$legacy_assignment_hits"

# A repository may only be constructed at explicit composition/bootstrap seams.
repository_construction_hits="$(
  rg -n '\bWebViewSessionRepository\s*\(' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  case "$file" in
    App/SumiApp.swift)
      ;;
    *)
      printf 'error: WebViewSessionRepository constructed outside composition/bootstrap: %s\n' "$match" >&2
      status=1
      ;;
  esac
done <<< "$repository_construction_hits"

# Browser-owned tabs must enter through TabFactory so their session handle is
# backed by the composition-root repository from construction time. The
# isolated extension infrastructure probe intentionally builds a throwaway tab
# that never enters the browser graph.
tab_construction_hits="$(
  rg -n '\bTab[[:space:]]*\(' "${production_roots[@]}" -g '*.swift' \
    | rg -v ':[0-9]+:[[:space:]]*//' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  case "$file" in
    Sumi/Managers/TabManager/TabFactory.swift|Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionInlineUIInfrastructureProbe.swift)
      ;;
    *)
      printf 'error: production Tab constructed outside TabFactory: %s\n' "$match" >&2
      status=1
      ;;
  esac
done <<< "$tab_construction_hits"

# In app code, only Tab constructs its scoped handle.
handle_construction_hits="$(
  rg -n '\bWebViewSessionHandle\s*\(' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "Sumi/Models/Tab/Tab.swift" ]]; then
    printf 'error: WebViewSessionHandle constructed outside Tab: %s\n' "$match" >&2
    status=1
  fi
done <<< "$handle_construction_hits"

# Window slots are lifecycle-coupled package operations, never Tab-handle/app APIs.
tracked_mutator_pattern='\.(registerWindowWebView|removeWindowWebView|replaceWindowSet|promoteTrackedWebViewToPrimary|clearAll)\s*\('
tracked_repository_mutator_pattern='\b(webViewSessions|repository)\.(registerWindowWebView|removeWindowWebView|replaceWindowSet|promoteTrackedWebViewToPrimary|clearAll)\s*\('
tracked_app_hits="$(
  rg -n "$tracked_repository_mutator_pattern" "${production_roots[@]}" -g '*.swift' || true
)"
fail_matches "tracked repository mutator escaped SumiWebRuntime" "$tracked_app_hits"

tracked_handle_hits="$(rg -n "$tracked_mutator_pattern" "$handle_source" || true)"
fail_matches "tab-scoped handle gained tracked-window mutation" "$tracked_handle_hits"

tracked_visibility_hits="$(
  rg -n '\bfunc\s+(registerWindowWebView|removeWindowWebView|replaceWindowSet|promoteTrackedWebViewToPrimary|clearAll)\b' \
    "$repository_source" | rg -v 'package\s+func' || true
)"
fail_matches "tracked repository mutator is not package-scoped" "$tracked_visibility_hits"

tracked_package_hits="$(
  rg -n "$tracked_repository_mutator_pattern" \
    Packages/SumiWebRuntime/Sources/SumiWebRuntime -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != Packages/SumiWebRuntime/Sources/SumiWebRuntime/Owners/* ]]; then
    printf 'error: tracked mutator used outside repository lifecycle owners: %s\n' "$match" >&2
    status=1
  fi
done <<< "$tracked_package_hits"

# Detached repository mutation normally belongs to WebViewSessionHandle. The
# protected-command dispatcher is the one identity-checked deferred cleanup seam.
detached_mutator_pattern='\b(webViewSessions|repository)\.(noteParkedWebView|noteUntrackedWebView|adoptParkedWebViewAsUntracked|clearDetachedWebViews|removeDetachedWebView)\s*\('
detached_app_hits="$(
  rg -n "$detached_mutator_pattern" "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "Sumi/Managers/WebViewRuntime/WebViewProtectedCommandDispatchOwner.swift" ]]; then
    printf 'error: detached repository mutation bypasses WebViewSessionHandle: %s\n' "$match" >&2
    status=1
  fi
done <<< "$detached_app_hits"

# Pending-cleanup ownership is a two-step transaction. A focused cleanup
# service acquires the lease before deferral; the exact lease is consumed only
# by that cleanup boundary, physical cleanup, or the protected-command
# dispatcher immediately before shutdown.
pending_cleanup_hits="$(
  rg -n '\bwebViewSessions\.(beginPendingCleanup|consumePendingCleanup)\s*\(' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  case "$file" in
    Sumi/Managers/WebViewRuntime/DetachedWebViewCleanupService.swift|Sumi/Managers/WebViewRuntime/WebViewPhysicalCleanupService.swift|Sumi/Managers/WebViewRuntime/WebViewProtectedCommandDispatchOwner.swift)
      ;;
    *)
      printf 'error: pending-cleanup lease mutation escaped WebView runtime lifecycle: %s\n' "$match" >&2
      status=1
      ;;
  esac
done <<< "$pending_cleanup_hits"

# Tab must not regain stored/computed WKWebView ownership mirrors or façade reads.
tab_mirror_hits="$(
  rg -n '\bvar\s+(_?webView|_?existingWebView|currentWebView|assignedWebView|parkedWebView)\s*:\s*WKWebView\??' \
    Sumi/Models/Tab/Tab.swift Sumi/Models/Tab/Tab+WebViewRuntime.swift \
    Sumi/Models/Tab/TabMainFrame*.swift \
    Sumi/Models/Tab/TabCommittedDocumentLedger.swift \
    Sumi/Models/Tab/TabWebContentRecoveryPlanner.swift || true
)"
fail_matches "Tab WKWebView ownership mirror/façade reintroduced" "$tab_mirror_hits"

# The load runtime alone constructs and stores the raw intent ledger. The
# transaction constructs the exact load/lifecycle/recovery aggregate.
intent_ledger_construction_hits="$(
  rg -n '\bTabMainFrameIntentLedger\s*\(' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "$main_frame_load_runtime" ]]; then
    printf 'error: raw main-frame intent ledger constructed outside load runtime: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$intent_ledger_construction_hits"

intent_ledger_storage_hits="$(
  rg -n '\b(let|var)\s+\w+\s*:\s*TabMainFrameIntentLedger\b' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "$main_frame_load_runtime" ]]; then
    printf 'error: raw main-frame intent ledger stored outside load runtime: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$intent_ledger_storage_hits"

load_runtime_ledger_storage_count="$(
  rg --count-matches \
    '^    private let ledger: TabMainFrameIntentLedger$' \
    "$main_frame_load_runtime" 2>/dev/null || true
)"
load_runtime_ledger_storage_count="${load_runtime_ledger_storage_count:-0}"
if [[ "$load_runtime_ledger_storage_count" -ne 1 ]]; then
  printf 'error: TabMainFrameLoadRuntime must privately retain exactly one intent ledger (%s != 1)\n' \
    "$load_runtime_ledger_storage_count" >&2
  status=1
fi

main_frame_aggregate_construction_hits="$(
  rg -n '\b(TabMainFrameLoadRuntime|TabMainFrameLifecycleMachine|TabWebContentRecoveryPlanner)\s*\(' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "$main_frame_transaction" ]]; then
    printf 'error: main-frame aggregate component constructed outside transaction: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$main_frame_aggregate_construction_hits"

rebuild_epoch_construction_hits="$(
  rg -n '\bTabWebViewRebuildEpoch\s*\(' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "Sumi/Models/Tab/Tab.swift" ]]; then
    printf 'error: WebView rebuild epoch constructed outside Tab composition: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$rebuild_epoch_construction_hits"

tab_rebuild_epoch_storage_count="$(
  rg --count-matches \
    '^    let webViewRebuildEpoch = TabWebViewRebuildEpoch\(\)$' \
    Sumi/Models/Tab/Tab.swift 2>/dev/null || true
)"
tab_rebuild_epoch_storage_count="${tab_rebuild_epoch_storage_count:-0}"
if [[ "$tab_rebuild_epoch_storage_count" -ne 1 ]]; then
  printf 'error: Tab must retain exactly one physical WebView rebuild epoch (%s != 1)\n' \
    "$tab_rebuild_epoch_storage_count" >&2
  status=1
fi

# These operations change both pending-load authority and lifecycle/durable
# state. Feature code must enter through the transaction, never call the load
# capability directly for one half of the transition.
coordinated_load_mutation_hits="$(
  rg -n '\bmainFrameLoads\.(beginExplicitIntent|beginLifecycleIntent|beginRollbackIntent|updateTargetWithinRevision|consumeSubmittedLoad|failSubmittedLoad|restoreDeferredLoadAfterFailedSubmission|departure|promoteSubmittedAuthority)\s*\(' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "$main_frame_transaction" ]]; then
    printf 'error: coordinated main-frame load mutation escaped transaction: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$coordinated_load_mutation_hits"

committed_document_runtime_construction_hits="$(
  rg -n '\bTabCommittedDocumentRuntime\s*\(' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "$main_frame_transaction" ]]; then
    printf 'error: committed-document runtime constructed outside main-frame composition: %s\n' "$match" >&2
    status=1
  fi
done <<< "$committed_document_runtime_construction_hits"

committed_document_ledger_construction_hits="$(
  rg -n '\bTabCommittedDocumentLedger\s*\(' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "$committed_document_runtime" ]]; then
    printf 'error: durable document ledger constructed outside exact runtime: %s\n' "$match" >&2
    status=1
  fi
done <<< "$committed_document_ledger_construction_hits"

durable_webview_evidence_hits="$(
  rg -n '\b(let|var)\s+\w+\s*:\s*TabCommittedDocumentEvidence\b' \
    Sumi/Models/Tab/TabCommittedDocumentLedger.swift || true
)"
fail_matches "durable ledger regained strong WKWebView evidence storage" \
  "$durable_webview_evidence_hits"

committed_document_mutation_hits="$(
  rg -n '\bcommittedDocumentRuntime\.(performTransition|recordReplica|recordReplicas|recordCommit|adoptCanonicalDocument|updatePresentation|noteSurvivingDocument|removeWebView|removeWebViews|prepareRollbackSnapshot|adoptRehydratedEvidence)\s*\(' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "$main_frame_transaction" ]]; then
    printf 'error: committed-document transition mutation escaped main-frame transaction: %s\n' "$match" >&2
    status=1
  fi
done <<< "$committed_document_mutation_hits"

retired_document_facade_hits="$(
  rg -n '\b(mainFrameDocumentLease|documentSuspensionDecision|recordDocumentSuspensionReport|documentSuspensionActivationToken|activatePendingDocumentSuspensionReports|reconcileDocumentSuspensionStateIfChanged)\b' \
    Sumi/Models/Tab/Tab.swift || true
)"
fail_matches "retired Tab committed-document façade reintroduced" \
  "$retired_document_facade_hits"

retired_main_frame_load_facade_hits="$(
  rg -n '\b(beginWebViewRebuildIntent|currentWebViewRebuildIntentRevision|isCurrentWebViewRebuildIntent|currentMainFrameNavigationIntent|isCurrentMainFrameNavigationIntent|claimDirectMainFrameLoad|claimDirectMainFrameLoadLease|claimDeferredMainFrameLoad|submittedMainFrameLoadLease|beginPreparedMainFrameLoad|finishPreparedMainFrameLoad|markDeferredMainFrameLoad|clearDeferredMainFrameLoad|hasOutstandingMainFrameLoad|mainFrameLoadingWebViews)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "retired Tab main-frame load façade reintroduced" \
  "$retired_main_frame_load_facade_hits"

document_script_tab_root_hits="$(
  rg -n '\b(private\s+)?weak\s+var\s+tab\s*:\s*Tab\?' \
    Sumi/UserScripts/SumiDocumentSuspensionSensorUserScript.swift \
    Sumi/UserScripts/SumiSubframePictureInPictureUserScript.swift || true
)"
fail_matches "document sensor user script regained Tab root" \
  "$document_script_tab_root_hits"

tab_main_frame_component_storage_hits="$(
  rg -n '\b(let|var)\s+\w+\s*:\s*(TabMainFrameIntentLedger|TabMainFrameLifecycleMachine|TabCommittedDocumentLedger|TabWebContentRecoveryPlanner)\b' \
    Sumi/Models/Tab/Tab.swift || true
)"
fail_matches "Tab directly retains a main-frame state component" "$tab_main_frame_component_storage_hits"

tab_facade_read_hits="$(
  rg -n '\btab\.(currentWebView|existingWebView|assignedWebView|parkedWebView|primaryWindowId)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "deleted Tab WebView ownership accessor used" "$tab_facade_read_hits"

# Ownership-affecting Tab calls remain inside Tab internals, WebView runtime, or routing.
tab_mutator_hits="$(
  rg -n '\.(replaceUntrackedWebView|clearCurrentWebViewOwnership|clearAllWebViewOwnership|clearCurrentWebViewOwnershipIfIdentical|makeNormalTabWebView|prepareAssignedWebView)\s*\(' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  case "$file" in
    Sumi/Models/Tab/*|Sumi/Managers/WebViewRuntime/*|Sumi/Services/BrowserWebViewRoutingService.swift)
      ;;
    *)
      printf 'error: Tab WebView mutation outside Tab/WebView runtime/routing: %s\n' "$match" >&2
      status=1
      ;;
  esac
done <<< "$tab_mutator_hits"

dead_ensure_hits="$(
  rg -n '(\.ensureWebView\(|func\s+ensureWebView\(|\.setupWebView\()' \
    "${production_roots[@]}" -g '*.swift' || true
)"
fail_matches "dead Tab WebView construction API reintroduced" "$dead_ensure_hits"

if [[ "$status" -ne 0 ]]; then
  echo "Tab WebView ownership boundary audit failed" >&2
  echo "Use WebViewSessionRepository as canonical placement, WebViewSessionHandle for detached Tab state, and focused placement/replacement/cleanup services for lifecycle changes." >&2
  exit "$status"
fi

echo "Tab WebView ownership boundary audit passed"
