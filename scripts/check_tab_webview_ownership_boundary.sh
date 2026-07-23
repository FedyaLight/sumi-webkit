#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

# Canonical ownership model:
# - WebViewSessionRepository is the process-wide placement source of truth.
# - WebViewSessionHandle is Tab's narrow detached-placement/read boundary.
# - tracked window mutations stay package-only behind WebViewTrackingLifecycleOwner.
# - Tab stores no WKWebView mirror and exposes no ownership façade.
# - TabMainFrameLoadRuntime alone owns the raw pending-load/intent ledger.
# - TabMainFrameRuntimeTransaction coordinates lifecycle/recovery transitions.
# - TabCommittedDocumentRuntime alone owns durable committed-document state.

production_roots=(App Sumi SidebarChrome CommandPalette Settings UI)
all_swift_roots=("${production_roots[@]}" Packages SumiTests SumiUITests)
repository_source="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Session/WebViewSessionRepository.swift"
handle_source="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Session/WebViewSessionHandle.swift"
main_frame_load_runtime="Sumi/Models/Tab/TabMainFrameLoadRuntime.swift"
web_view_rebuild_epoch="Sumi/Models/Tab/TabWebViewRebuildEpoch.swift"
main_frame_transaction="Sumi/Models/Tab/TabMainFrameRuntimeTransaction.swift"
main_frame_capabilities="Sumi/Models/Tab/TabMainFrameRuntimeCapabilities.swift"
authority_effect_ledger="Sumi/Models/Tab/TabMainFrameAuthorityEffectLedger.swift"
participant_effect_ledger="Sumi/Models/Tab/TabMainFrameParticipantEffectLedger.swift"
authority_reducer="Sumi/Models/Tab/TabMainFrameAuthorityReducer.swift"
participant_transition_applier="Sumi/Models/Tab/TabMainFrameParticipantTransitionApplier.swift"
authority_transition_applier="Sumi/Models/Tab/TabMainFrameAuthorityTransitionApplier.swift"
transition_output="Sumi/Models/Tab/TabMainFrameTransitionOutput.swift"
recovery_capabilities="Sumi/Models/Tab/TabWebContentRecoveryCapabilities.swift"
recovery_marker_ledger="Sumi/Models/Tab/TabWebContentRecoveryMarkerLedger.swift"
committed_document_runtime="Sumi/Models/Tab/TabCommittedDocumentRuntime.swift"
status=0


for required in "$repository_source" "$handle_source" "$main_frame_load_runtime" \
  "$web_view_rebuild_epoch" \
  "$main_frame_transaction" "$main_frame_capabilities" \
  "$authority_effect_ledger" "$participant_effect_ledger" \
  "$authority_reducer" "$participant_transition_applier" \
  "$authority_transition_applier" "$transition_output" \
  "$recovery_capabilities" \
  "$recovery_marker_ledger" \
  "$committed_document_runtime"; do
  if [[ ! -f "$required" ]]; then
    printf 'error: required WebView/main-frame architecture source missing: %s\n' \
      "$required" >&2
    status=1
  fi
done

# Tab composes the concrete transaction once and stores only the narrow
# submission port. Lifecycle/promotion ports are injected directly into the
# WebKit responder; the concrete type is not a general feature dependency.
transaction_construction_hits="$(
  guard_capture_matches '\bTabMainFrameRuntimeTransaction\s*\(' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "Sumi/Models/Tab/Tab.swift" ]]; then
    printf 'error: main-frame transaction constructed outside Tab composition: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$transaction_construction_hits"

transaction_construction_count="$({
  printf '%s\n' "$transaction_construction_hits"
} | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "$transaction_construction_count" -ne 1 ]]; then
  printf 'error: production must construct exactly one main-frame transaction (%s != 1)\n' \
    "$transaction_construction_count" >&2
  status=1
fi

transaction_storage_hits="$(
  guard_capture_matches '\b(let|var)\s+\w+\s*:\s*TabMainFrameRuntimeTransaction\b' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  if [[ "$match" != \
    Sumi/Models/Tab/Tab.swift:*:'    private let mainFrameRuntimeTransaction: TabMainFrameRuntimeTransaction' ]]; then
    printf 'error: concrete main-frame transaction storage escaped Tab: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$transaction_storage_hits"

transaction_storage_count="$(
  guard_count_matches \
    '^    private let mainFrameRuntimeTransaction: TabMainFrameRuntimeTransaction$' \
    Sumi/Models/Tab/Tab.swift
)"
transaction_storage_count="${transaction_storage_count:-0}"
if [[ "$transaction_storage_count" -ne 1 ]]; then
  printf 'error: Tab must privately retain exactly one concrete main-frame transaction (%s != 1)\n' \
    "$transaction_storage_count" >&2
  status=1
fi

submission_capability_storage_count="$(
  guard_count_matches \
    '^    let mainFrameSubmission: any TabMainFrameSubmissionSettlement$' \
    Sumi/Models/Tab/Tab.swift
)"
submission_capability_storage_count="${submission_capability_storage_count:-0}"
if [[ "$submission_capability_storage_count" -ne 1 ]]; then
  printf 'error: Tab must retain exactly one protocol-typed mainFrameSubmission capability (%s != 1)\n' \
    "$submission_capability_storage_count" >&2
  status=1
fi

tab_lifecycle_promotion_surface_hits="$(
  {
    guard_capture_matches '\b(let|var)\s+mainFrame(Lifecycle|Promotion)\b' \
      Sumi/Models/Tab/Tab.swift Sumi/Models/Tab/Tab+*.swift
    guard_capture_matches '\btab\.mainFrame(Lifecycle|Promotion)\b' \
      "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
  }
)"
if [[ -n "$tab_lifecycle_promotion_surface_hits" ]]; then
  guard_record_failure "Tab regained stored/accessed lifecycle or promotion capability:
$tab_lifecycle_promotion_surface_hits"
fi

# Lifecycle and promotion settlement ports are callback-local: the concrete
# transaction conforms, the responder privately retains its injected ports,
# and the promotion reducer receives its port as an explicit parameter.
lifecycle_promotion_type_hits="$(
  guard_capture_matches '\bTabMainFrame(Lifecycle|Promotion)Settlement\b' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  content="${match#*:*:}"
  case "$file" in
    "$main_frame_capabilities")
      ;;
    "$main_frame_transaction")
      if [[ ! "$content" =~ ^[[:space:]]+TabMainFrame(Lifecycle|Promotion)Settlement,$ ]]; then
        printf 'error: lifecycle/promotion capability used beyond transaction conformance: %s\n' \
          "$match" >&2
        status=1
      fi
      ;;
    Sumi/Models/Tab/Navigation/SumiTabLifecycleNavigationResponder.swift)
      if [[ ! "$content" =~ ^[[:space:]]+(private[[:space:]]+let[[:space:]]+(lifecycle|promotion):[[:space:]]+any[[:space:]]+TabMainFrame(Lifecycle|Promotion)Settlement|lifecycle:[[:space:]]+any[[:space:]]+TabMainFrameLifecycleSettlement,|promotion:[[:space:]]+any[[:space:]]+TabMainFramePromotionSettlement,?)$ ]]; then
        printf 'error: lifecycle/promotion capability escaped responder private storage/init: %s\n' \
          "$match" >&2
        status=1
      fi
      ;;
    Sumi/Models/Tab/Navigation/TabMainFrameLifecyclePromotionReducer.swift)
      if [[ ! "$content" =~ ^[[:space:]]+(promotion:[[:space:]]+any[[:space:]]+TabMainFramePromotionSettlement|lifecycle:[[:space:]]+any[[:space:]]+TabMainFrameLifecycleSettlement)$ ]]; then
        printf 'error: lifecycle/promotion capability escaped reducer parameter: %s\n' \
          "$match" >&2
        status=1
      fi
      ;;
    *)
      printf 'error: lifecycle/promotion capability escaped callback settlement boundary: %s\n' \
        "$match" >&2
      status=1
      ;;
  esac
done <<< "$lifecycle_promotion_type_hits"

main_frame_responder_factory_count="$(
  guard_count_matches \
    '^    func makeMainFrameLifecycleResponder\(\) -> SumiTabLifecycleNavigationResponder \{$' \
    Sumi/Models/Tab/Tab.swift
)"
main_frame_responder_factory_count="${main_frame_responder_factory_count:-0}"
if [[ "$main_frame_responder_factory_count" -ne 1 ]]; then
  printf 'error: Tab must expose exactly one main-frame lifecycle responder factory (%s != 1)\n' \
    "$main_frame_responder_factory_count" >&2
  status=1
fi

responder_construction_hits="$(
  guard_capture_matches '\bSumiTabLifecycleNavigationResponder\s*\(' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "Sumi/Models/Tab/Tab.swift" ]]; then
    printf 'error: lifecycle responder constructed outside Tab factory: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$responder_construction_hits"

responder_construction_count="$({
  printf '%s\n' "$responder_construction_hits"
} | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "$responder_construction_count" -ne 1 ]]; then
  printf 'error: production must construct exactly one lifecycle responder (%s != 1)\n' \
    "$responder_construction_count" >&2
  status=1
fi

responder_factory_usage_hits="$(
  guard_capture_matches '\.makeMainFrameLifecycleResponder\s*\(' \
    "${production_roots[@]}" -g '*.swift'
)"
responder_factory_usage_count="$({
  printf '%s\n' "$responder_factory_usage_hits"
} | sed '/^$/d' | wc -l | tr -d ' ')"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != \
    "Sumi/Models/Tab/Navigation/SumiTabNavigationDelegateBundle.swift" ]]; then
    printf 'error: lifecycle responder factory consumed outside navigation delegate bundle: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$responder_factory_usage_hits"
if [[ "$responder_factory_usage_count" -ne 1 ]]; then
  printf 'error: navigation delegate bundle must acquire exactly one lifecycle responder (%s != 1)\n' \
    "$responder_factory_usage_count" >&2
  status=1
fi

production_transaction_injection_hits="$(
  guard_capture_matches '\bmainFrameRuntimeTransaction\s*:' \
    "${production_roots[@]}" -g '*.swift' \
    | guard_capture_matches '^Sumi/Models/Tab/Tab\.swift:[0-9]+:    private let mainFrameRuntimeTransaction:' -v --no-line-number -
)"
if [[ -n "$production_transaction_injection_hits" ]]; then
  guard_record_failure "main-frame transaction test injection label used in production:
$production_transaction_injection_hits"
fi

# Concrete injection is temporary test scaffolding for transaction-coupled unit
# scenarios. Keep it inside the audited files; BrowserManager-backed fixtures
# must use TabFactory/createNewTab and the real responder path.
test_transaction_injection_files="$(
  guard_capture_files 'mainFrameRuntimeTransaction\s*:' SumiTests -g '*.swift' \
    | sort
)"
allowed_test_transaction_injection_files="$(cat <<'EOF'
SumiTests/BrowserWebViewRoutingServiceTests.swift
SumiTests/NormalTabInitialDocumentRuntimeHandoffTests.swift
SumiTests/SumiGPCTests.swift
SumiTests/SumiReaderPresentationTests.swift
SumiTests/TabMainFrameFinishSettlementTests.swift
SumiTests/TabMainFrameRuntimeTransactionTests.swift
SumiTests/TabNavigationCommandsTests.swift
SumiTests/TabRuntimeRoutingTests.swift
SumiTests/TabScriptMessageHandlerIsolationTests.swift
SumiTests/TabSuspensionArchitectureTests.swift
SumiTests/TabWebViewMaterializationAndRebuildTests.swift
SumiTests/WebViewRuntimeTabRegistryTests.swift
EOF
)"
if [[ "$test_transaction_injection_files" != \
  "$allowed_test_transaction_injection_files" ]]; then
  printf 'error: concrete main-frame transaction injection escaped audited unit fixtures:\n%s\n' \
    "${test_transaction_injection_files:-none}" >&2
  status=1
fi

# Callback capabilities settle already-admitted work. Cross-boundary
# admission, departure, recovery, and rollback remain atomic Tab/transaction
# operations and must not be smuggled into these protocol surfaces.
side_effectful_capability_hits="$(
  guard_capture_matches '^\s*func\s+(beginExplicitIntent|beginLifecycle|abortNavigation|webViewsDidLeaveRuntime|accept[A-Za-z0-9_]*Target|rollback[A-Za-z0-9_]*|beginRecovery)\b' \
    "$main_frame_capabilities"
)"
if [[ -n "$side_effectful_capability_hits" ]]; then
  guard_record_failure "main-frame settlement capability gained cross-boundary mutation:
$side_effectful_capability_hits"
fi

retired_lifecycle_settlement_hits="$(
  guard_capture_matches '^\s*func\s+(recordCommit|recordResponse|responseIsPDF)\b' \
    "$main_frame_capabilities"
)"
if [[ -n "$retired_lifecycle_settlement_hits" ]]; then
  guard_record_failure "raw lifecycle settlement operation returned to callback capability:
$retired_lifecycle_settlement_hits"
fi

# Tombstones: the split registry/session/owner model must not return.
legacy_type_hits="$(
  guard_capture_matches '\b(TabWebViewSession|WindowWebViewRegistry|TabWebViewOwnershipOwner|WebViewOwnershipService)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$legacy_type_hits" ]]; then
  guard_record_failure "deleted WebView ownership type reintroduced:
$legacy_type_hits"
fi

if [[ -e Sumi/Models/Tab/TabWebContentRecoveryPlanner.swift ]]; then
  printf 'error: retired TabWebContentRecoveryPlanner.swift must stay deleted\n' >&2
  status=1
fi

retired_recovery_planner_hits="$(
  guard_capture_matches '\bTabWebContentRecoveryPlanner\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$retired_recovery_planner_hits" ]]; then
  guard_record_failure "retired TabWebContentRecoveryPlanner type reintroduced:
$retired_recovery_planner_hits"
fi

# These assignment-shaped Tab APIs silently mutate a mirror and are forbidden.
legacy_assignment_hits="$(
  guard_capture_matches '\b(assignWebViewToWindow|assignPrimaryWebView|setPrimaryWindowId|setCurrentWebView|setExistingWebView|syncFromTabIfNeeded|adoptDetachedState)\s*\(|\.rebind\s*\(\s*to:' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$legacy_assignment_hits" ]]; then
  guard_record_failure "legacy mirror-assignment API reintroduced:
$legacy_assignment_hits"
fi

# A repository may only be constructed at explicit composition/bootstrap seams.
repository_construction_hits="$(
  guard_capture_matches '\bWebViewSessionRepository\s*\(' \
    "${production_roots[@]}" -g '*.swift'
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
  guard_capture_matches '\bTab[[:space:]]*\(' "${production_roots[@]}" -g '*.swift' \
    | guard_capture_matches ':[0-9]+:[[:space:]]*//' -v --no-line-number -
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
  guard_capture_matches '\bWebViewSessionHandle\s*\(' \
    "${production_roots[@]}" -g '*.swift'
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
  guard_capture_matches "$tracked_repository_mutator_pattern" "${production_roots[@]}" -g '*.swift'
)"
if [[ -n "$tracked_app_hits" ]]; then
  guard_record_failure "tracked repository mutator escaped SumiWebRuntime:
$tracked_app_hits"
fi

tracked_handle_hits="$(guard_capture_matches "$tracked_mutator_pattern" "$handle_source")"
if [[ -n "$tracked_handle_hits" ]]; then
  guard_record_failure "tab-scoped handle gained tracked-window mutation:
$tracked_handle_hits"
fi

tracked_visibility_hits="$(
  guard_capture_matches '\bfunc\s+(registerWindowWebView|removeWindowWebView|replaceWindowSet|promoteTrackedWebViewToPrimary|clearAll)\b' \
    "$repository_source" | guard_capture_matches 'package\s+func' -v --no-line-number -
)"
if [[ -n "$tracked_visibility_hits" ]]; then
  guard_record_failure "tracked repository mutator is not package-scoped:
$tracked_visibility_hits"
fi

tracked_package_hits="$(
  guard_capture_matches "$tracked_repository_mutator_pattern" \
    Packages/SumiWebRuntime/Sources/SumiWebRuntime -g '*.swift'
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
# deferred command executor is the one authority-checked cleanup seam.
detached_mutator_pattern='\b(webViewSessions|repository)\.(noteParkedWebView|noteUntrackedWebView|adoptParkedWebViewAsUntracked|clearDetachedWebViews|removeDetachedWebView)\s*\('
detached_app_hits="$(
  guard_capture_matches "$detached_mutator_pattern" "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "Sumi/Managers/WebViewRuntime/DeferredWebViewCommandExecutor.swift" ]]; then
    printf 'error: detached repository mutation bypasses WebViewSessionHandle: %s\n' "$match" >&2
    status=1
  fi
done <<< "$detached_app_hits"

# Detached residence publication must enter through the exact installation or
# replacement authority. Tab setup stages may prepare candidates, but may not
# carry raw handle mutation capabilities.
raw_detached_handle_mutation_hits="$(
  guard_capture_matches '\.(replaceUntracked|adoptParkedAsUntracked)\s*\(' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "Sumi/Managers/WebViewRuntime/CanonicalWebViewPlacementService.swift" ]]; then
    printf 'error: detached handle mutation escaped canonical placement authority: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$raw_detached_handle_mutation_hits"

setup_stage_mutation_hits="$(
  guard_capture_matches '\b(adoptParkedWebViewAsCurrent|replaceUntrackedWebView)\b' \
    Sumi/Models/Tab/TabNormalWebViewSetupStages.swift \
    Sumi/Models/Tab/Tab+NormalWebViewSetupStages.swift \
    Sumi/Models/Tab/TabNormalWebViewSetupService.swift
)"
if [[ -n "$setup_stage_mutation_hits" ]]; then
  guard_record_failure "normal WebView setup regained raw detached residence mutation:
$setup_stage_mutation_hits"
fi

# The retired 24-role context may not return under a new owner or compatibility
# alias. Setup roles are phase-specific values; their declarations cannot reach
# a browser root, retain Tab, or start background work. Provisioning receives
# only request/configuration/preparation and exact profile/policy inputs.
for retired_context_source in \
  Sumi/Models/Tab/TabNormalWebViewRuntimeContext.swift \
  Sumi/Models/Tab/TabNormalWebViewRuntimeContextOwner.swift; do
  if [[ -e "$retired_context_source" ]]; then
    printf 'error: retired normal WebView context source returned: %s\n' \
      "$retired_context_source" >&2
    status=1
  fi
done

retired_context_hits="$(
  guard_capture_matches '\b(TabNormalWebViewRuntimeContext|TabNormalWebViewRuntimeContextOwner)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$retired_context_hits" ]]; then
  guard_record_failure "retired normal WebView context type returned:
$retired_context_hits"
fi

setup_stage_backreference_hits="$(
  guard_capture_matches '\b(BrowserManager|TabManager|TabBrowserRuntime)\b|\b(let|var)[[:space:]]+[A-Za-z0-9_]*tab[[:space:]]*:[[:space:]]*Tab\b' \
    Sumi/Models/Tab/TabNormalWebViewSetupStages.swift
)"
if [[ -n "$setup_stage_backreference_hits" ]]; then
  guard_record_failure "normal WebView setup stage gained a root/Tab backreference:
$setup_stage_backreference_hits"
fi

setup_stage_background_work_hits="$(
  guard_capture_matches '\b(Timer|Task|AnyCancellable|NotificationCenter|DispatchQueue|Publisher)\b' \
    Sumi/Models/Tab/TabNormalWebViewSetupStages.swift
)"
if [[ -n "$setup_stage_background_work_hits" ]]; then
  guard_record_failure "normal WebView setup stage gained background or observation work:
$setup_stage_background_work_hits"
fi

provisioning_stage_leak_hits="$(
  guard_capture_matches '\bTabNormalWebView(CreationAdmission|Residence|InitialDocument)Stage\b|\b(let|var)[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[[:space:]]*Tab\b|[,(][[:space:]]*Tab[?,)]' \
    Sumi/Models/Tab/TabWebViewProvisioningOwner.swift
)"
if [[ -n "$provisioning_stage_leak_hits" ]]; then
  guard_record_failure "normal WebView provisioning gained residence/lifecycle/document reach-through:
$provisioning_stage_leak_hits"
fi

exact_setup_identity_hits="$(
  guard_count_matches 'residence\.currentWebView\(\)[[:space:]]*===[[:space:]]*committedWebView' \
    Sumi/Models/Tab/TabNormalWebViewSetupService.swift
)"
if [[ "$exact_setup_identity_hits" -lt 2 ]]; then
  printf 'error: normal WebView setup must revalidate exact committed identity around effects (%s < 2)\n' \
    "$exact_setup_identity_hits" >&2
  status=1
fi

# Pending-cleanup ownership is a two-step transaction. A focused cleanup
# service acquires the lease before deferral; the exact lease is consumed only
# by that cleanup boundary, physical cleanup, or the protected-command
# executor immediately before shutdown.
pending_cleanup_hits="$(
  guard_capture_matches '\bwebViewSessions\.(beginPendingCleanup|consumePendingCleanup)\s*\(' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  case "$file" in
    Sumi/Managers/WebViewRuntime/DetachedWebViewCleanupService.swift|Sumi/Managers/WebViewRuntime/WebViewPhysicalCleanupService.swift|Sumi/Managers/WebViewRuntime/DeferredWebViewCommandExecutor.swift)
      ;;
    *)
      printf 'error: pending-cleanup lease mutation escaped WebView runtime lifecycle: %s\n' "$match" >&2
      status=1
      ;;
  esac
done <<< "$pending_cleanup_hits"

# Tab must not regain stored/computed WKWebView ownership mirrors or façade reads.
tab_mirror_hits="$(
  guard_capture_matches '\bvar\s+(_?webView|_?existingWebView|currentWebView|assignedWebView|parkedWebView)\s*:\s*WKWebView\??' \
    Sumi/Models/Tab/Tab.swift Sumi/Models/Tab/Tab+WebViewRuntime.swift \
    Sumi/Models/Tab/TabMainFrame*.swift \
    Sumi/Models/Tab/TabCommittedDocumentLedger.swift \
    "$recovery_marker_ledger"
)"
if [[ -n "$tab_mirror_hits" ]]; then
  guard_record_failure "Tab WKWebView ownership mirror/façade reintroduced:
$tab_mirror_hits"
fi

# The load runtime alone constructs and stores the raw intent ledger. The
# transaction constructs the exact load/lifecycle/recovery aggregate.
intent_ledger_construction_hits="$(
  guard_capture_matches '\bTabMainFrameIntentLedger\s*\(' \
    "${production_roots[@]}" -g '*.swift'
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
  guard_capture_matches '\b(let|var)\s+\w+\s*:\s*TabMainFrameIntentLedger\b' \
    "${production_roots[@]}" -g '*.swift'
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
  guard_count_matches \
    '^    private let ledger: TabMainFrameIntentLedger$' \
    "$main_frame_load_runtime"
)"
load_runtime_ledger_storage_count="${load_runtime_ledger_storage_count:-0}"
if [[ "$load_runtime_ledger_storage_count" -ne 1 ]]; then
  printf 'error: TabMainFrameLoadRuntime must privately retain exactly one intent ledger (%s != 1)\n' \
    "$load_runtime_ledger_storage_count" >&2
  status=1
fi

main_frame_aggregate_construction_hits="$(
  guard_capture_matches '\b(TabMainFrameLoadRuntime|TabMainFrameLifecycleMachine|TabWebContentRecoveryMarkerLedger)\s*\(' \
    "${production_roots[@]}" -g '*.swift'
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

recovery_marker_storage_hits="$(
  guard_capture_matches '\b(let|var)\s+\w+\s*:\s*TabWebContentRecoveryMarkerLedger\b' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "$main_frame_transaction" ]]; then
    printf 'error: WebContent recovery marker ledger stored outside transaction: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$recovery_marker_storage_hits"

transaction_recovery_marker_storage_count="$(
  guard_count_matches \
    '^    private let recoveryMarkers: TabWebContentRecoveryMarkerLedger$' \
    "$main_frame_transaction"
)"
transaction_recovery_marker_storage_count="${transaction_recovery_marker_storage_count:-0}"
if [[ "$transaction_recovery_marker_storage_count" -ne 1 ]]; then
  printf 'error: main-frame transaction must privately retain exactly one recovery marker ledger (%s != 1)\n' \
    "$transaction_recovery_marker_storage_count" >&2
  status=1
fi

recovery_marker_mutation_hits="$(
  guard_capture_matches '\brecoveryMarkers\.(markRequired|clear)\s*\(' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if [[ "$file" != "$main_frame_transaction" ]]; then
    printf 'error: WebContent recovery marker mutation escaped transaction: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$recovery_marker_mutation_hits"

tab_recovery_capability_storage_count="$(
  guard_count_matches \
    '^    let webContentRecoveryMarkers: any TabWebContentRecoveryMarkerQuery$' \
    Sumi/Models/Tab/Tab.swift
)"
tab_recovery_capability_storage_count="${tab_recovery_capability_storage_count:-0}"
if [[ "$tab_recovery_capability_storage_count" -ne 1 ]]; then
  printf 'error: Tab must retain exactly one read-only WebContent recovery query (%s != 1)\n' \
    "$tab_recovery_capability_storage_count" >&2
  status=1
fi

production_recovery_begin_hits="$(
  guard_capture_matches '\brecovery\.beginRecovery\s*\(' \
    "${production_roots[@]}" -g '*.swift'
)"
production_recovery_begin_count="$(
  printf '%s\n' "$production_recovery_begin_hits" | sed '/^$/d' | wc -l | tr -d ' '
)"
if [[ "$production_recovery_begin_count" -ne 1 ]] ||
   [[ "${production_recovery_begin_hits%%:*}" != \
     "Sumi/Models/Tab/Navigation/SumiTabLifecycleNavigationResponder.swift" ]]; then
  printf 'error: WebContent recovery admission must remain in the exact lifecycle callback (%s)\n' \
    "${production_recovery_begin_hits:-none}" >&2
  status=1
fi

tab_recovery_admission_hits="$(
  guard_capture_matches '\bTabWebContentRecoveryAdmission\b' Sumi/Models/Tab/Tab.swift
)"
if [[ -n "$tab_recovery_admission_hits" ]]; then
  guard_record_failure "Tab regained WebContent recovery admission authority:
$tab_recovery_admission_hits"
fi

recovery_admission_type_hits="$(
  guard_capture_matches '\bTabWebContentRecoveryAdmission\b' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  case "$file" in
    "$recovery_capabilities"|"$main_frame_transaction"|Sumi/Models/Tab/Navigation/SumiTabLifecycleNavigationResponder.swift)
      ;;
    *)
      printf 'error: recovery admission capability escaped transaction/responder boundary: %s\n' \
        "$match" >&2
      status=1
      ;;
  esac
done <<< "$recovery_admission_type_hits"

# Reducer decisions are applied by lifecycle orchestration. The reducer may
# inspect immutable participant entries, but cannot reach into participant or
# effect ledgers and mutate a second authority behind the caller's back.
reducer_cross_ledger_hits="$(
  guard_capture_matches '\b(TabMainFrameParticipantRegistry|TabMainFrameAuthorityEffectLedger|TabMainFrameParticipantEffectLedger)\b' \
    "$authority_reducer" \
    | guard_capture_matches 'TabMainFrameParticipantRegistry\.Entry|TabMainFrameAuthorityEffectLedger\.SharedCommitIdentity' -v --no-line-number -
)"
if [[ -n "$reducer_cross_ledger_hits" ]]; then
  guard_record_failure "main-frame authority reducer regained ledger reach-through:
$reducer_cross_ledger_hits"
fi

authority_reducer_count="$(
  guard_count_matches '^enum TabMainFrameAuthorityReducer \{' "$authority_reducer"
)"
if (( authority_reducer_count == 0 )); then
  printf 'error: main-frame authority reducer must remain a stateless enum\n' >&2
  status=1
fi
reducer_stored_state_hits="$(
  guard_capture_matches '^    (private )?(let|var) [a-zA-Z_]' "$authority_reducer"
)"
if [[ -n "$reducer_stored_state_hits" ]]; then
  guard_record_failure "main-frame authority reducer regained stored state:
$reducer_stored_state_hits"
fi

retired_decision_family_hits="$(
  guard_capture_matches '\bTabMainFrame(Effect|Commit|Finish|SameDocument)Decision\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$retired_decision_family_hits" ]]; then
  guard_record_failure "parallel main-frame callback decision family reintroduced:
$retired_decision_family_hits"
fi

retired_combined_effect_ledger_hits="$(
  guard_capture_matches '\bTabMainFrameEffectLedger\b' "${all_swift_roots[@]}" \
    -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$retired_combined_effect_ledger_hits" ]]; then
  guard_record_failure "combined authority/participant effect ledger reintroduced:
$retired_combined_effect_ledger_hits"
fi

effect_ledger_construction_hits="$(
  guard_capture_matches '\bTabMainFrame(Authority|Participant)EffectLedger\s*\(' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  if [[ "${match%%:*}" != "Sumi/Models/Tab/TabMainFrameLifecycleMachine.swift" ]]; then
    printf 'error: main-frame effect ledger constructed outside lifecycle composition: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$effect_ledger_construction_hits"

transition_applier_construction_hits="$(
  guard_capture_matches '\bTabMainFrame(Participant|Authority)TransitionApplier\s*\(' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  if [[ "${match%%:*}" != "Sumi/Models/Tab/TabMainFrameLifecycleMachine.swift" ]]; then
    printf 'error: main-frame transition applier constructed outside lifecycle composition: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$transition_applier_construction_hits"

lifecycle_direct_ledger_storage_hits="$(
  guard_capture_matches '^    private let [a-zA-Z_]+: TabMainFrame(ParticipantRegistry|AuthorityState|AuthorityEffectLedger|ParticipantEffectLedger)$' \
    Sumi/Models/Tab/TabMainFrameLifecycleMachine.swift
)"
if [[ -n "$lifecycle_direct_ledger_storage_hits" ]]; then
  guard_record_failure "lifecycle machine regained direct ledger storage:
$lifecycle_direct_ledger_storage_hits"
fi

rebuild_epoch_construction_hits="$(
  guard_capture_matches '\bTabWebViewRebuildEpoch\s*\(' \
    "${production_roots[@]}" -g '*.swift'
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
  guard_count_matches \
    '^    let webViewRebuildEpoch = TabWebViewRebuildEpoch\(\)$' \
    Sumi/Models/Tab/Tab.swift
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
  guard_capture_matches '\bmainFrameLoads\.(beginExplicitIntent|beginLifecycleIntent|beginRollbackIntent|updateTargetWithinRevision|consumeSubmittedLoad|failSubmittedLoad|restoreDeferredLoadAfterFailedSubmission|departure|promoteSubmittedAuthority)\s*\(' \
    "${production_roots[@]}" -g '*.swift'
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
  guard_capture_matches '\bTabCommittedDocumentRuntime\s*\(' \
    "${production_roots[@]}" -g '*.swift'
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
  guard_capture_matches '\bTabCommittedDocumentLedger\s*\(' \
    "${production_roots[@]}" -g '*.swift'
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
  guard_capture_matches '\b(let|var)\s+\w+\s*:\s*TabCommittedDocumentEvidence\b' \
    Sumi/Models/Tab/TabCommittedDocumentLedger.swift
)"
if [[ -n "$durable_webview_evidence_hits" ]]; then
  guard_record_failure "durable ledger regained strong WKWebView evidence storage:
$durable_webview_evidence_hits"
fi

committed_document_mutation_hits="$(
  guard_capture_matches '\bcommittedDocumentRuntime\.(performTransition|recordReplica|recordReplicas|recordCommit|adoptCanonicalDocument|updatePresentation|noteSurvivingDocument|removeWebView|removeWebViews|prepareRollbackSnapshot|adoptRehydratedEvidence)\s*\(' \
    "${production_roots[@]}" -g '*.swift'
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
  guard_capture_matches '\b(mainFrameDocumentLease|documentSuspensionDecision|recordDocumentSuspensionReport|documentSuspensionActivationToken|activatePendingDocumentSuspensionReports|reconcileDocumentSuspensionStateIfChanged)\b' \
    Sumi/Models/Tab/Tab.swift
)"
if [[ -n "$retired_document_facade_hits" ]]; then
  guard_record_failure "retired Tab committed-document façade reintroduced:
$retired_document_facade_hits"
fi

retired_main_frame_load_facade_hits="$(
  guard_capture_matches '\b(beginWebViewRebuildIntent|currentWebViewRebuildIntentRevision|isCurrentWebViewRebuildIntent|currentMainFrameNavigationIntent|isCurrentMainFrameNavigationIntent|claimDirectMainFrameLoad|claimDirectMainFrameLoadLease|claimDeferredMainFrameLoad|submittedMainFrameLoadLease|beginPreparedMainFrameLoad|finishPreparedMainFrameLoad|markDeferredMainFrameLoad|clearDeferredMainFrameLoad|hasOutstandingMainFrameLoad|mainFrameLoadingWebViews)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$retired_main_frame_load_facade_hits" ]]; then
  guard_record_failure "retired Tab main-frame load façade reintroduced:
$retired_main_frame_load_facade_hits"
fi

retired_tab_recovery_facade_hits="$(
  guard_capture_matches '^\s*func\s+(beginWebContentProcessRecovery|requiresWebContentProcessRecovery|retainWebContentProcessRecovery|reconcileWebContentProcessRecovery)\b' \
    Sumi/Models/Tab -g '*.swift'
)"
if [[ -n "$retired_tab_recovery_facade_hits" ]]; then
  guard_record_failure "retired Tab WebContent recovery façade reintroduced:
$retired_tab_recovery_facade_hits"
fi

# These nineteen forwarding methods were removed when navigation callbacks
# received narrow settlement capabilities. Only Tab façade definitions are
# tombstoned: lifecycle-machine/transaction internals remain free to use their
# domain names.
retired_tab_main_frame_settlement_facade_hits="$(
  guard_capture_matches '^\s*(public |private |internal |fileprivate )?func\s+(submittedMainFrameSemanticRevision|bindSubmittedMainFrameLoad|failSubmittedMainFrameLoad|restoreDeferredMainFrameLoadAfterFailedSubmission|mainFrameLifecycleRole|shouldAcceptMainFrameLifecycle|prepareMainFrameAuthorityForCommit|recordMainFrameCommitSnapshot|claimMainFrameTransactionStartEffects|claimMainFrameAuthorityTargetPreparation|claimMainFrameLocalStartEffects|claimMainFrameAuthorityForTerminalSuccess|claimSharedMainFrameFinishEffects|claimPromotedSharedCommitEffects|claimPromotedSharedFinishEffects|recordMainFrameResponse|mainFrameResponseIsPDF|finishMainFrameLifecycle|isCurrentMainFrameNavigationRevision)\b' \
    Sumi/Models/Tab/Tab.swift Sumi/Models/Tab/Tab+*.swift
)"
if [[ -n "$retired_tab_main_frame_settlement_facade_hits" ]]; then
  guard_record_failure "retired Tab main-frame settlement façade reintroduced:
$retired_tab_main_frame_settlement_facade_hits"
fi

document_script_tab_root_hits="$(
  guard_capture_matches '\b(private\s+)?weak\s+var\s+tab\s*:\s*Tab\?' \
    Sumi/UserScripts/SumiDocumentSuspensionSensorUserScript.swift \
    Sumi/UserScripts/SumiSubframePictureInPictureUserScript.swift
)"
if [[ -n "$document_script_tab_root_hits" ]]; then
  guard_record_failure "document sensor user script regained Tab root:
$document_script_tab_root_hits"
fi

tab_main_frame_component_storage_hits="$(
  guard_capture_matches '\b(let|var)\s+\w+\s*:\s*(TabMainFrameIntentLedger|TabMainFrameLifecycleMachine|TabCommittedDocumentLedger|TabWebContentRecoveryMarkerLedger)\b' \
    Sumi/Models/Tab/Tab.swift
)"
if [[ -n "$tab_main_frame_component_storage_hits" ]]; then
  guard_record_failure "Tab directly retains a main-frame state component:
$tab_main_frame_component_storage_hits"
fi

tab_facade_read_hits="$(
  guard_capture_matches '\btab\.(currentWebView|existingWebView|assignedWebView|parkedWebView|primaryWindowId)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$tab_facade_read_hits" ]]; then
  guard_record_failure "deleted Tab WebView ownership accessor used:
$tab_facade_read_hits"
fi

# Ownership-affecting Tab calls remain inside Tab internals, WebView runtime, or routing.
tab_mutator_hits="$(
  guard_capture_matches '\.(replaceUntrackedWebView|clearCurrentWebViewOwnership|clearAllWebViewOwnership|clearCurrentWebViewOwnershipIfIdentical|makeNormalTabWebView|prepareAssignedWebView)\s*\(' \
    "${production_roots[@]}" -g '*.swift'
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
  guard_capture_matches '(\.ensureWebView\(|func\s+ensureWebView\(|\.setupWebView\()' \
    "${production_roots[@]}" -g '*.swift'
)"
if [[ -n "$dead_ensure_hits" ]]; then
  guard_record_failure "dead Tab WebView construction API reintroduced:
$dead_ensure_hits"
fi

if (( status != 0 || guard_failures != 0 )); then
  echo "Tab WebView ownership boundary audit failed" >&2
  echo "Use WebViewSessionRepository as canonical placement, WebViewSessionHandle for detached Tab state, and focused placement/replacement/cleanup services for lifecycle changes." >&2
  exit 1
fi

echo "Tab WebView ownership boundary audit passed"
