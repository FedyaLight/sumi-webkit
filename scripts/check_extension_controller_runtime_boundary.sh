#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

old='Sumi/Managers/ExtensionManager/ExtensionControllerAttachmentOwner.swift'
old_runtime_bundle='Sumi/Managers/ExtensionManager/ExtensionRuntimeBundle.swift'
old_window_owner='Sumi/Managers/ExtensionManager/ExtensionWindowFocusResolutionOwner.swift'
query='Sumi/Managers/ExtensionManager/ExtensionNormalTabPublicationQueries.swift'
residence='Sumi/Managers/ExtensionManager/ExtensionExactTabWebViewQuery.swift'
admission='Sumi/Managers/ExtensionManager/ExtensionWebViewControllerAdmission.swift'
repair='Sumi/Managers/ExtensionManager/ExtensionTabWebViewRuntimeRepair.swift'
assembler='Sumi/Managers/ExtensionManager/ExtensionControllerRuntimeAssembler.swift'
resolver='Sumi/Managers/ExtensionManager/ExtensionTabWebViewResolver.swift'
provisioning='Sumi/Managers/ExtensionManager/ExtensionControllerProvisioningOwner.swift'
requested_materializer='Sumi/Managers/ExtensionManager/ExtensionRequestedTabWebViewMaterializer.swift'
cold_preparation='Sumi/Managers/ExtensionManager/ExtensionWebViewConfigurationPreparation.swift'
live_preparation='Sumi/Managers/ExtensionManager/ExtensionLiveWebViewRuntimePreparation.swift'
bridge='Sumi/Managers/ExtensionManager/ExtensionBridge.swift'
browser_composition='Sumi/Managers/BrowserManager/BrowserExtensionBridgeComposition.swift'
browser_runtime_factory='Sumi/Managers/BrowserManager/BrowserExtensionManagerRuntimeFactory.swift'
runtime_demand='Sumi/Managers/ExtensionManager/ExtensionRuntimeDemandCoordinator.swift'
runtime_attachment='Sumi/Managers/ExtensionManager/ExtensionManager+BrowserRuntimeAttachment.swift'
action_surface='Sumi/Managers/ExtensionManager/ExtensionActionSurfacePublisher.swift'
runtime_publication='Sumi/Managers/ExtensionManager/ExtensionManager+RuntimePublication.swift'

status=0

if [[ -e "$old" || -L "$old" ]]; then
  echo 'error: extension controller attachment god-object returned' >&2
  status=1
fi
for retired_surface in "$old_runtime_bundle" "$old_window_owner"; do
  if [[ -e "$retired_surface" || -L "$retired_surface" ]]; then
    echo "error: eager extension runtime aggregate returned: $retired_surface" >&2
    status=1
  fi
done
retired_runtime_hits="$(
  guard_capture_matches \
    '\bExtensionRuntimeBundle\b|\bExtensionWindowFocusResolutionOwner\b|\bruntimeBundle\b' \
    Sumi/Managers/ExtensionManager SumiTests
)"
if [[ -n "$retired_runtime_hits" ]]; then
  echo 'error: eager extension runtime aggregate or Owner surface returned' >&2
  status=1
fi
old_symbol_hits="$(
  guard_capture_matches '\bExtensionControllerAttachmentOwner\b' Sumi
)"
if [[ -n "$old_symbol_hits" ]]; then
  printf 'error: production still references the deleted controller god-object:\n%s\n' \
    "$old_symbol_hits" >&2
  status=1
fi

roles=("$query" "$residence" "$admission" "$repair" "$assembler" "$resolver")
for role in "${roles[@]}"; do
  if [[ ! -f "$role" ]]; then
    echo "error: extension controller runtime role missing: $role" >&2
    status=1
  fi
done

if (( status != 0 )); then
  exit "$status"
fi

role_reachthrough="$(
  guard_capture_matches \
    '\bExtensionManager(Runtime)?\b|\bBrowserManager\b|\bstruct (Dependencies|Actions)\b|\bclass [A-Za-z0-9_]*Owner\b' \
    "${roles[@]}"
)"
if [[ -n "$role_reachthrough" ]]; then
  printf 'error: extension controller role reached through a manager/bag/Owner:\n%s\n' \
    "$role_reachthrough" >&2
  status=1
fi

owner_storage_hits="$(
  guard_capture_matches \
    '^\s*(private\s+)?(weak\s+)?(var|let)\s+\w+\s*:\s*(any\s+)?[A-Za-z0-9_]+Owner\??\s*$|^\s+\w+\s*:\s*(any\s+)?[A-Za-z0-9_]+Owner[?,]?\s*$' \
    "${roles[@]}" -P
)"
if [[ -n "$owner_storage_hits" ]]; then
  printf 'error: controller runtime role stores or accepts a concrete Owner:\n%s\n' \
    "$owner_storage_hits" >&2
  status=1
fi

for preparation_class in \
  'ExtensionWebViewConfigurationPreparation' \
  'ExtensionLiveWebViewRuntimePreparation'; do
  preparation_file="$cold_preparation"
  if [[ "$preparation_class" == 'ExtensionLiveWebViewRuntimePreparation' ]]; then
    preparation_file="$live_preparation"
  fi
  preparation_body="$(
    sed -n "/final class $preparation_class:/,/^}/p" "$preparation_file"
  )"
  preparation_reachthrough_hits="$(
    guard_capture_matches \
      '\bExtensionManager(Runtime)?\b|\bBrowserManager\b|\bstruct (Dependencies|Actions)\b|\bclass [A-Za-z0-9_]*Owner\b' \
      - <<<"$preparation_body"
  )"
  if [[ -n "$preparation_reachthrough_hits" ]]; then
    echo "error: WebView preparation role reached through a root/bag/Owner: $preparation_class" >&2
    status=1
  fi
done

query_body="$(sed -n '/final class ExtensionExistingExactTabControllerQuery:/,/^}/p' "$query")"
query_mutation_hits="$(
  guard_capture_matches \
    'ensure|provision|setController|makeExtensionController' - <<<"$query_body"
)"
if [[ -n "$query_mutation_hits" ]]; then
  echo 'error: existing-controller query can provision or mutate controllers' >&2
  status=1
fi
query_identity_count="$(
  guard_count_matches 'extensionTab(for: tab.id) === tab' - -F <<<"$query_body"
)"
if (( query_identity_count == 0 )); then
  echo 'error: existing-controller query lacks exact canonical Tab proof' >&2
  status=1
fi

residence_identity_count="$(
  guard_count_matches 'extensionTab(for: tab.id) === tab' "$residence" -F
)"
if (( residence_identity_count == 0 )); then
  echo 'error: WebView residence query lacks exact canonical Tab proof' >&2
  status=1
fi
residence_ownership_count="$(
  guard_count_matches 'owningTab === tab' "$residence" -F
)"
if (( residence_ownership_count == 0 )); then
  echo 'error: WebView residence query lacks exact physical WebView ownership proof' >&2
  status=1
fi

admission_identity_count="$(
  guard_count_matches 'extensionTab(for: tab.id) === tab' "$admission" -F
)"
admission_ownership_count="$(
  guard_count_matches 'owningTab === tab' "$admission" -F
)"
admission_residence_count="$(
  guard_count_matches \
    'webViews?.contains(webView, for: tab) == true' "$admission" -F
)"
if (( admission_identity_count == 0 \
    || admission_ownership_count == 0 \
    || admission_residence_count == 0 )); then
  echo 'error: controller admission can accept a stale Tab or foreign WebView' >&2
  status=1
fi
concrete_prelude_hits="$(
  guard_capture_matches \
    'ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner' \
    "$admission" -F
)"
if [[ -n "$concrete_prelude_hits" ]]; then
  echo 'error: controller admission stores the concrete compatibility prelude owner' >&2
  status=1
fi
late_bind_hits="$(
  guard_capture_matches \
    'canLateBindController|webView\.configuration\.webExtensionController\s*=(?!=)' \
    Sumi/Managers/ExtensionManager -P
)"
if [[ -n "$late_bind_hits" ]]; then
  printf 'error: impossible post-construction WebKit controller mutation returned:\n%s\n' \
    "$late_bind_hits" >&2
  status=1
fi

aggregate_protocol_hits="$(
  guard_capture_matches \
    'protocol ExtensionControllerBinding(Query)?\b|\bExtensionControllerBinding(Query)?\b' \
    Sumi/Managers/ExtensionManager
)"
if [[ -n "$aggregate_protocol_hits" ]]; then
  printf 'error: deleted aggregate controller binding capability returned:\n%s\n' \
    "$aggregate_protocol_hits" >&2
  status=1
fi

provisioning_reentry_hits="$(
  guard_capture_matches \
    'updateWebViewsForProfile|reconcile(Profile|WebViews)' "$provisioning"
)"
if [[ -n "$provisioning_reentry_hits" ]]; then
  echo 'error: controller provisioning can synchronously re-enter profile reconciliation' >&2
  status=1
fi
runtime_demand_reentry_hits="$(
  guard_capture_matches 'reconcile(Profile)?|runtimeReconciler' "$runtime_demand"
)"
if [[ -n "$runtime_demand_reentry_hits" ]]; then
  echo 'error: extension runtime demand can synchronously re-enter reconciliation' >&2
  status=1
fi
reload_body="$(
  sed -n '/func reloadRuntimePublications(/,/^    }/p' \
    "$runtime_publication"
)"
reload_attachment_count="$(
  guard_count_matches 'guard attachedBrowserManager != nil' - -F <<<"$reload_body"
)"
reload_composition_count="$(
  guard_count_matches 'controllerRuntimeComposition != nil' - -F <<<"$reload_body"
)"
if (( reload_attachment_count == 0 || reload_composition_count == 0 )); then
  echo 'error: cold install/enable can materialize browser runtime publication' >&2
  status=1
fi
for attached_admission in \
  'Sumi/Managers/ExtensionManager/ExtensionWindowRequestRouter.swift'; do
  attached_admission_count="$(
    guard_count_matches 'attachedBrowserManager != nil' "$attached_admission" -F
  )"
  if (( attached_admission_count == 0 )); then
    echo "error: stale browser attachment remains admitted: $attached_admission" >&2
    status=1
  fi
done
callback_handler='Sumi/Managers/ExtensionManager/ExtensionControllerOpeningCallbackHandler.swift'
callback_evidence_count="$(
  guard_count_matches 'ExtensionControllerCallbackEvidence' "$callback_handler" -F
)"
callback_manager_hits="$(
  guard_capture_matches '\bExtensionManager\b' "$callback_handler"
)"
if (( callback_evidence_count == 0 )) || [[ -n "$callback_manager_hits" ]]; then
  echo 'error: opening callbacks no longer use manager-free exact evidence' >&2
  status=1
fi
strong_runtime_root_hits="$(
  guard_capture_matches \
    'let (ownershipQuery|rebuild|websiteDataCleanup) = browserManager|\[(ownershipQuery|rebuild|websiteDataCleanup)\]' \
    "$browser_runtime_factory"
)"
if [[ -n "$strong_runtime_root_hits" ]]; then
  printf 'error: extension runtime retains browser WebView services:\n%s\n' \
    "$strong_runtime_root_hits" >&2
  status=1
fi
attach_body="$(
  sed -n '/func attach(browserManager: BrowserManager)/,/^    }/p' \
    "$runtime_attachment"
)"
attach_new_graph_count="$(
  guard_count_matches 'controllerRuntimeComposition == nil' - -F <<<"$attach_body"
)"
attach_same_browser_count="$(
  guard_count_matches \
    'attachedBrowserManager === browserManager' - -F <<<"$attach_body"
)"
if (( attach_new_graph_count == 0 || attach_same_browser_count == 0 )); then
  echo 'error: controller runtime attachment can silently replace live role graphs' >&2
  status=1
fi
dead_tracing_hits="$(
  guard_capture_matches 'traceNativeMessagingContextBinding' \
    "$cold_preparation" "$live_preparation" -F
)"
if [[ -n "$dead_tracing_hits" ]]; then
  echo 'error: split WebView preparation contains dead manager-less tracing' >&2
  status=1
fi

for old_surface in \
  'func extensionController(for tab:' \
  'func tabMatchesExtensionContext(' \
  'func resolvedLiveWebView(for tab:' \
  'func ownedUntrackedCurrentWebView(for tab:' \
  'func attachExtensionControllerIfNeeded(' \
  'func ensureExtensionControllerAttachedForTab(' \
  'updateWebViewsForProfile'; do
  hits="$(
    guard_capture_matches "$old_surface" Sumi/Managers/ExtensionManager -F
  )"
  if [[ -n "$hits" ]]; then
    printf 'error: deleted controller capability returned (%s):\n%s\n' \
      "$old_surface" "$hits" >&2
    status=1
  fi
done

for old_facade in \
  'func extensionController(for tab:' \
  'func tabMatchesExtensionContext(' \
  'func resolvedLiveWebView(for tab:' \
  'func ownedUntrackedCurrentWebView(for tab:' \
  'func attachExtensionControllerIfNeeded(' \
  'func ensureExtensionControllerAttachedForTab(' \
  'func webViewNeedsExtensionRuntimeRebuild(' \
  'func updateWebViewsForProfile('; do
  hits="$(
    guard_capture_matches \
      "$old_facade" Sumi/Managers/ExtensionManager/ExtensionManager*.swift -F
  )"
  if [[ -n "$hits" ]]; then
    printf 'error: deleted controller manager facade returned (%s):\n%s\n' \
      "$old_facade" "$hits" >&2
    status=1
  fi
done

repair_identity_count="$(
  guard_count_matches 'tabs?.extensionTab(for: tab.id) === tab' "$repair" -F
)"
if (( repair_identity_count < 2 )); then
  echo 'error: repair/reconcile roles lack exact physical Tab proofs' >&2
  status=1
fi
rebuild_port_count="$(
  guard_count_matches 'rebuildExtensionLiveWebViews(' "$repair" -F
)"
if (( rebuild_port_count == 0 )); then
  echo 'error: runtime repair lost its explicit browser rebuild port' >&2
  status=1
fi
flattened_submission_hits="$(
  guard_capture_matches '\.didCommit' \
    "$bridge" "$repair" "$browser_composition"
)"
if [[ -n "$flattened_submission_hits" ]]; then
  echo 'error: extension rebuild boundary flattened typed submission state to Bool' >&2
  status=1
fi
rebuild_protocol_body="$(
  sed -n '/protocol ExtensionTabWebViewRebuilding:/,/^}/p' "$bridge"
)"
rebuild_adapter_body="$(
  sed -n '/func rebuildExtensionLiveWebViews(/,/^    }/p' \
    Sumi/Managers/ExtensionManager/BrowserExtensionWebViewAdapter.swift
)"
for rebuild_body in "$rebuild_protocol_body" "$rebuild_adapter_body"; do
  typed_outcome_count="$(
    guard_count_matches \
      ') -> ExtensionTabWebViewRebuildSubmissionOutcome' - -F <<<"$rebuild_body"
  )"
  if (( typed_outcome_count == 0 )); then
    echo 'error: extension rebuild boundary lost its typed submission outcome' >&2
    status=1
  fi
done
for rebuild_case in committed deferred noLiveWindows failed; do
  rebuild_case_count="$(
    guard_count_matches "case .$rebuild_case" "$browser_composition" -F
  )"
  if (( rebuild_case_count == 0 )); then
    echo "error: browser bridge does not map rebuild result: $rebuild_case" >&2
    status=1
  fi
done

profile_resolver_count="$(
  guard_count_matches \
    'resolveProfileID: @MainActor (UUID?) -> UUID?' "$cold_preparation" -F
)"
if (( profile_resolver_count == 0 )); then
  echo 'error: cold configuration preparation lacks narrow profile resolver' >&2
  status=1
fi
runtime_request_count="$(
  guard_count_matches \
    'requestRuntime: @MainActor (UUID) -> Void' "$cold_preparation" -F
)"
if (( runtime_request_count == 0 )); then
  echo 'error: cold configuration demand does not preserve its resolved profile' >&2
  status=1
fi
cold_root_hits="$(
  guard_capture_matches \
    '\(\) -> ExtensionManagerRuntime|ExtensionControllerProvisioningOwner' \
    "$cold_preparation"
)"
if [[ -n "$cold_root_hits" ]]; then
  echo 'error: cold configuration preparation stores a broad runtime/concrete owner' >&2
  status=1
fi
live_bag_hits="$(
  guard_capture_matches \
    '\bstruct (Dependencies|Actions)\b|installPreludes\(' "$live_preparation"
)"
if [[ -n "$live_bag_hits" ]]; then
  echo 'error: live WebView preparation regained a closure bag or foreign prelude mutation' >&2
  status=1
fi
live_late_binding_hits="$(
  guard_capture_matches '\bfunc bind\b|\brepair\?*\.repair\(' "$live_preparation"
)"
live_registration_count="$(
  guard_count_matches \
    'tabRegistration: ExtensionNormalTabRegistration' "$live_preparation" -F
)"
if [[ -n "$live_late_binding_hits" ]] || (( live_registration_count == 0 )); then
  echo 'error: live WebView preparation regained two-phase or fallback repair wiring' >&2
  status=1
fi

prepared_candidate_body="$(
  sed -n '/private func preparedNormalTabWebViewIsUsable(/,/^    }/p' \
    "$requested_materializer"
)"
prepared_canonical_count="$(
  guard_count_matches 'webViews.isCanonical(tab)' - -F <<<"$prepared_candidate_body"
)"
prepared_ownership_count="$(
  guard_count_matches 'owningTab === tab' - -F <<<"$prepared_candidate_body"
)"
prepared_controller_count="$(
  guard_count_matches \
    'webView.configuration.webExtensionController === controller' \
    - -F <<<"$prepared_candidate_body"
)"
if [[ -z "$prepared_candidate_body" ]] \
    || (( prepared_canonical_count == 0 \
      || prepared_ownership_count == 0 \
      || prepared_controller_count == 0 )); then
  echo 'error: requested replacement lacks exact pre-commit construction proof' >&2
  status=1
fi
committed_residence_hits="$(
  guard_capture_matches \
    'controllerAdmission\.admit|webViews\.contains' - <<<"$prepared_candidate_body"
)"
if [[ -n "$committed_residence_hits" ]]; then
  echo 'error: pre-commit candidate validation incorrectly requires committed residence' >&2
  status=1
fi

composition_fields="$(
  sed -n '/struct ExtensionControllerRuntimeComposition {/,/^}/p' "$assembler" \
    | guard_count_matches '^    let ' -
)"
composition_fields="${composition_fields:-0}"
if (( composition_fields > 9 )); then
  echo "error: controller lifetime composition grew beyond 9 leaves ($composition_fields)" >&2
  status=1
fi
resolver_leaf_count="$(
  guard_count_matches \
    'let tabWebViewResolver: ExtensionTabWebViewResolver' "$assembler" -F
)"
forced_resolver_hits="$(
  guard_capture_matches 'tabWebViewResolver.*!' \
    Sumi/Managers/ExtensionManager/ExtensionManager.swift
)"
if (( resolver_leaf_count == 0 )) || [[ -n "$forced_resolver_hits" ]]; then
  echo 'error: unattached Tab WebView projection is no longer a safe read-only capability' >&2
  status=1
fi
action_attachment_count="$(
  guard_count_matches 'manager?.attachedBrowserManager != nil' "$action_surface" -F
)"
action_composition_count="$(
  guard_count_matches \
    'manager?.controllerRuntimeComposition != nil' "$action_surface" -F
)"
if (( action_attachment_count == 0 || action_composition_count == 0 )); then
  echo 'error: cold extension load can materialize browser publication roles before attachment' >&2
  status=1
fi
window_router='Sumi/Managers/ExtensionManager/ExtensionWindowRequestRouter.swift'
window_attachment_count="$(
  guard_count_matches 'guard attachedBrowserManager != nil' "$window_router" -F
)"
window_composition_count="$(
  guard_count_matches 'controllerRuntimeComposition != nil' "$window_router" -F
)"
window_resolver_count="$(
  guard_count_matches 'ExtensionWindowVisibilityResolver(manager: self)' \
    Sumi/Managers/ExtensionManager/ExtensionManager.swift -F
)"
if (( window_attachment_count == 0 \
    || window_composition_count == 0 \
    || window_resolver_count == 0 )); then
  echo 'error: attached-only extension window graph can materialize on a cold manager' >&2
  status=1
fi
opening_manager_hits="$(
  guard_capture_matches '\bExtensionManager\b' "$callback_handler"
)"
opening_admission_count="$(
  guard_count_matches 'admission.isCurrent' "$callback_handler" -F
)"
if [[ -n "$opening_manager_hits" ]] || (( opening_admission_count == 0 )); then
  echo 'error: extension opening callback escaped exact manager-free admission' >&2
  status=1
fi

composition_refs="$(
  guard_capture_files 'ExtensionControllerRuntimeComposition' Sumi \
    | wc -l | tr -d ' '
)"
if (( composition_refs > 2 )); then
  echo "error: controller lifetime composition escaped assembler/store boundary ($composition_refs files)" >&2
  status=1
fi
aggregate_runtime_hits="$(
  guard_capture_matches '\brequiredControllerRuntime\b' Sumi
)"
if [[ -n "$aggregate_runtime_hits" ]]; then
  echo 'error: aggregate controller runtime capability escaped composition' >&2
  status=1
fi

prepared_normal_query_count="$(
  sed -n '/final class ExtensionPreparedNormalTabQuery/,/^}/p' "$query" \
    | guard_count_matches 'tab.isEphemeral == false' - -F
)"
if (( prepared_normal_query_count == 0 )); then
  echo 'error: normal prepared-Tab query no longer rejects ephemeral Tabs' >&2
  status=1
fi

materializer_body="$(
  sed -n '/struct ExtensionRequestedTabWebViewMaterializer {/,/^}/p' \
    "$requested_materializer"
)"
retired_runtime_session='ExtensionRuntime''Session'
materializer_authority_hits="$(
  guard_capture_matches \
    "$retired_runtime_session|runtimeSession|ExtensionRuntime[A-Za-z]+Authority" \
    - <<<"$materializer_body"
)"
materializer_trap_hits="$(
  guard_capture_matches 'preconditionFailure(' - -F <<<"$materializer_body"
)"
if [[ -n "$materializer_authority_hits" || -n "$materializer_trap_hits" ]]; then
  echo 'error: retained requested-Tab materializer regained aggregate runtime authority' >&2
  status=1
fi

repair_witness_count="$(
  guard_count_matches 'openPublicationInvalidationWitness()' "$repair" -F
)"
prepared_token_identity_count="$(
  guard_count_matches 'preparedTokenIdentity' \
    Sumi/Models/Tab/TabExtensionPageRuntimeOwner.swift -F
)"
prepared_token_phase_count="$(
  guard_count_matches 'preparedTokenPhase' \
    Sumi/Models/Tab/TabExtensionPageRuntimeOwner.swift -F
)"
if (( repair_witness_count == 0 \
    || prepared_token_identity_count == 0 \
    || prepared_token_phase_count == 0 )); then
  echo 'error: runtime repair lacks exact open/prepublication invalidation authority' >&2
  status=1
fi

role_caps=(
  "$residence:110" "$admission:145" "$repair:270" "$assembler:135"
  "$cold_preparation:115" "$live_preparation:135"
)
for role_cap in "${role_caps[@]}"; do
  role="${role_cap%:*}"
  cap="${role_cap##*:}"
  lines="$(wc -l < "$role" | tr -d ' ')"
  if (( lines > cap )); then
    echo "error: $role grew beyond $cap LOC ($lines)" >&2
    status=1
  fi
done

if (( status != 0 )); then
  exit "$status"
fi
echo 'extension controller runtime boundary passed'
