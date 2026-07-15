#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

old='Sumi/Managers/ExtensionManager/ExtensionNormalTabRuntimeBindingOwner.swift'
open='Sumi/Managers/ExtensionManager/ExtensionNormalTabOpenTransaction.swift'
close='Sumi/Managers/ExtensionManager/ExtensionNormalTabCloseTransaction.swift'
close_receipt='Sumi/Managers/ExtensionManager/ExtensionNormalTabCloseReceipt.swift'
queries='Sumi/Managers/ExtensionManager/ExtensionNormalTabPublicationQueries.swift'
registration='Sumi/Managers/ExtensionManager/ExtensionNormalTabRegistration.swift'
properties='Sumi/Managers/ExtensionManager/ExtensionTabPropertyPublisher.swift'
rebind='Sumi/Managers/ExtensionManager/ExtensionTabLifecycleRebindTransaction.swift'
deferred='Sumi/Managers/ExtensionManager/ExtensionDeferredTabRegistration.swift'
events='Sumi/Managers/ExtensionManager/ExtensionTabLifecycleEmitter.swift'
policy='Sumi/Managers/ExtensionManager/ExtensionContentScriptBindingPolicy.swift'
visibility='Sumi/Managers/ExtensionManager/ExtensionPreparedTabVisibility.swift'
lifecycle='Sumi/Managers/ExtensionManager/ExtensionNormalWindowLifecycle.swift'
tab_state='Sumi/Models/Tab/TabExtensionPageRuntimeOwner.swift'
bridge='Sumi/Managers/ExtensionManager/ExtensionBridge.swift'
composition='Sumi/Managers/ExtensionManager/ExtensionManager+RuntimePublicationComposition.swift'
assembler='Sumi/Managers/ExtensionManager/ExtensionNormalTabRuntimeAssembler.swift'
controller='Sumi/Managers/ExtensionManager/ExtensionWebViewControllerAdmission.swift'
cold_webview_preparation='Sumi/Managers/ExtensionManager/ExtensionWebViewConfigurationPreparation.swift'
live_webview_preparation='Sumi/Managers/ExtensionManager/ExtensionLiveWebViewRuntimePreparation.swift'
requested_webview_materializer='Sumi/Managers/ExtensionManager/ExtensionRequestedTabWebViewMaterializer.swift'
old_webview_preparation='Sumi/Managers/ExtensionManager/ExtensionWebViewRuntimePreparationOwner.swift'

status=0

retired_preparation_hits="$(
  guard_capture_matches '\bExtensionWebViewRuntimePreparationOwner\b' Sumi
)"
if [[ -e "$old_webview_preparation" || -L "$old_webview_preparation" \
   || -n "$retired_preparation_hits" ]]; then
  echo 'error: combined WebView runtime preparation owner returned' >&2
  status=1
fi

for preparation in \
  "$cold_webview_preparation" "$live_webview_preparation"; do
  if [[ ! -f "$preparation" ]]; then
    echo "error: split WebView runtime preparation role missing: $preparation" >&2
    status=1
  fi
done

if [[ -e "$old" || -L "$old" ]]; then
  echo 'error: normal Tab runtime god-object returned' >&2
  status=1
fi

roles=(
  "$open" "$queries" "$registration" "$properties" "$rebind"
  "$deferred" "$events" "$policy" "$visibility"
)
for role in "${roles[@]}"; do
  if [[ ! -f "$role" ]]; then
    echo "error: normal Tab runtime role missing: $role" >&2
    status=1
  fi
done

role_reachthrough="$(
  guard_capture_matches \
    '\bExtensionManager(Runtime)?\b|\bBrowserManager\b|\bstruct (Dependencies|Actions)\b|\bclass [A-Za-z0-9_]*Owner\b' \
    "${roles[@]}"
)"
if [[ -n "$role_reachthrough" ]]; then
  printf 'error: normal Tab runtime role reached through a manager/bag/Owner:\n%s\n' \
    "$role_reachthrough" >&2
  status=1
fi

for old_facade in \
  'func notifyTabOpened(' \
  'func notifyTabPropertiesChanged(' \
  'func tabNeedsExtensionContentScriptRebind(' \
  'func registerTabWithExtensionRuntime(' \
  'func markTabEligibleAfterCommittedNavigation(' \
  'func isTabEligibleForCurrentExtensionRuntime('; do
  hits="$(
    guard_capture_matches "$old_facade" Sumi/Managers/ExtensionManager -F
  )"
  if [[ -n "$hits" ]]; then
    printf 'error: deleted normal Tab manager facade returned (%s):\n%s\n' \
      "$old_facade" "$hits" >&2
    status=1
  fi
done

open_identity_count="$(
  guard_count_matches 'tabs?.extensionTab(for: tab.id) === tab' "$open" -F
)"
if (( open_identity_count < 2 )); then
  echo 'error: open transaction lacks pre/post exact physical Tab proof' >&2
  status=1
fi
open_validation_count="$(guard_count_matches 'remainsCurrent(' "$open" -F)"
if (( open_validation_count < 3 )); then
  echo 'error: open transaction lacks pre/post callback validation' >&2
  status=1
fi
open_close_claim_count="$(
  guard_count_matches 'claimDidOpenTabNotificationForClose(' "$open" -F
)"
if (( open_close_claim_count == 0 )); then
  echo 'error: rejected open is not balanced through its exact claim' >&2
  status=1
fi

claim_line="$(
  guard_capture_matches 'claimDidOpenTabNotificationForClose\(' "$rebind" \
    | head -1 | cut -d: -f1
)"
close_line="$(
  guard_capture_matches 'events\.emitDidCloseTab\(' "$rebind" \
    | head -1 | cut -d: -f1
)"
if [[ -z "$claim_line" || -z "$close_line" ]] || (( claim_line >= close_line )); then
  echo 'error: navigation rebind must claim close before didCloseTab' >&2
  status=1
fi

deferred_identity_count="$(
  guard_count_matches 'tabs?.extensionTab(for: tabID) === tab' "$deferred" -F
)"
if (( deferred_identity_count < 2 )); then
  echo 'error: deferred registration can admit a same-UUID replacement' >&2
  status=1
fi

published_last="$(
  guard_capture_matches \
    'publishedTabs?.containsPublishedTab(tab) == true' "$properties" -F \
    | tail -1 | cut -d: -f1
)"
cache_first="$(
  guard_capture_matches \
    'recordReported(URL|LoadingComplete|Title)IfChanged' "$properties" \
    | head -1 | cut -d: -f1
)"
if [[ -z "$published_last" || -z "$cache_first" ]] || (( published_last >= cache_first )); then
  echo 'error: property cache can mutate before post-resolution publication proof' >&2
  status=1
fi

closure_cycle_hits="$(
  guard_capture_matches \
    'tabNeedsExtensionContentScriptRebind|registerTabWithExtensionRuntime' \
    "$controller" "$cold_webview_preparation" "$live_webview_preparation"
)"
if [[ -n "$closure_cycle_hits" ]]; then
  echo 'error: controller/WebView closure cycle into normal Tab runtime returned' >&2
  status=1
fi
late_binding_hits="$(
  guard_capture_matches '\bfunc bind\b|\brepair\?*\.repair\(' \
    "$live_webview_preparation"
)"
live_preparation_leaf_count="$(
  guard_count_matches \
    'let liveWebViewPreparation: ExtensionLiveWebViewRuntimePreparation' \
    "$assembler" -F
)"
if [[ -n "$late_binding_hits" ]] || (( live_preparation_leaf_count == 0 )); then
  echo 'error: live WebView preparation is not an atomic normal-runtime leaf' >&2
  status=1
fi

published_read_count="$(
  guard_count_matches 'publishedExtensionTabs.containsPublishedTab(tab)' "$bridge" -F
)"
prepared_read_count="$(
  guard_count_matches 'preparedTabVisibility.allowsPreparedTabRead(' "$bridge" -F
)"
if (( published_read_count == 0 || prepared_read_count == 0 )); then
  echo 'error: extension window Tab reads lack published-or-scoped authority' >&2
  status=1
fi
scope_line="$(
  guard_capture_matches 'guard tabScopes.isEmpty == false' "$visibility" -F \
    | cut -d: -f1
)"
handoff_line="$(
  guard_capture_matches 'isBrowserEventHandoffActive == true' "$visibility" -F \
    | cut -d: -f1
)"
if [[ -z "$scope_line" || -z "$handoff_line" ]] || (( scope_line >= handoff_line )); then
  echo 'error: reload handoff can grant prepared Tab reads outside a Tab callback' >&2
  status=1
fi
close_authority_boundaries=(
  "$visibility|controllerExposingPreparedAdapter("
  "$lifecycle|controller: projection.controller"
  "$close_receipt|let published: Publication?"
  "$close_receipt|let implicit: Publication?"
  "$close|claim.publicationAuthority()"
  "$close|claim.representsPublication("
  "$open|publisher: controller"
  "$open|adapter: adapter"
  "$tab_state|self.publisher === publisher"
  "$tab_state|self.adapter === adapter"
  "$close|guard receipt.beginClose() else { return }"
  "$close|private var inFlightCloses: Set<InFlightClose>"
  "$close|controller.extensionContexts.contains"
  "$close|ifIdenticalTo: storedAdapter"
)
for close_authority_boundary in "${close_authority_boundaries[@]}"; do
  authority_file="${close_authority_boundary%%|*}"
  authority_pattern="${close_authority_boundary#*|}"
  authority_count="$(
    guard_count_matches "$authority_pattern" "$authority_file" -F
  )"
  if (( authority_count == 0 )); then
    printf 'error: implicit WebKit-open Tab close authority is incomplete: %s\n' \
      "$authority_pattern" >&2
    status=1
  fi
done
stale_reservation_hits="$(
  guard_capture_matches \
    'hasPreparedWindowExposure|claimPreparedWindowExposureForClose|reserveImplicitOpenClaim|implicitOpenClaims' \
    "$visibility" "$close"
)"
if [[ -n "$stale_reservation_hits" ]]; then
  echo 'error: stale prepared-visibility close reservation returned' >&2
  status=1
fi
implicit_capture_line="$(
  guard_capture_matches \
    'preparedTabVisibility.controllerExposingPreparedAdapter(adapter)' "$close" -F \
    | cut -d: -f1
)"
implicit_close_line="$(
  guard_capture_matches 'events.emitDidCloseTab(' "$close" -F | cut -d: -f1
)"
if [[ -z "$implicit_capture_line" || -z "$implicit_close_line" ]] \
    || (( implicit_capture_line >= implicit_close_line )); then
  echo 'error: exact callback controller is not captured before didCloseTab' >&2
  status=1
fi
retirement_line="$(
  guard_capture_matches 'retireFutureOpenPublications()' "$close" -F \
    | cut -d: -f1
)"
store_read_line="$(
  guard_capture_matches 'let storedAdapter = adapterStore.tabAdapters' "$close" -F \
    | cut -d: -f1
)"
if [[ -z "$retirement_line" || -z "$store_read_line" ]] \
    || (( retirement_line >= store_read_line )); then
  echo 'error: physical Tab retirement still depends on current adapter-store membership' >&2
  status=1
fi
runtime_reconstruction_hits="$(
  guard_capture_matches \
    '\bprofileRuntime\b|controllers\.existingController\(for: tab\)' "$close"
)"
if [[ -n "$runtime_reconstruction_hits" ]]; then
  echo 'error: physical Tab close reconstructs publication from current runtime binding' >&2
  status=1
fi

composition_declarations="$(
  guard_count_matches 'struct ExtensionNormalTabRuntimeComposition' "$assembler" -F
)"
composition_declarations="${composition_declarations:-0}"
if (( composition_declarations != 1 )); then
  echo 'error: normal Tab leaf lifetime composition missing' >&2
  status=1
fi
composition_refs="$(
  guard_capture_files 'ExtensionNormalTabRuntimeComposition' Sumi \
    | wc -l | tr -d ' '
)"
if (( composition_refs > 2 )); then
  echo 'error: normal Tab lifetime composition escaped its builder/store boundary' >&2
  status=1
fi
assembler_lines="$(
  sed -n '/enum ExtensionNormalTabRuntimeAssembler {/,/^}/p' "$assembler" \
    | wc -l | tr -d ' '
)"
if (( assembler_lines > 180 )); then
  echo "error: normal Tab composition root grew beyond 180 LOC ($assembler_lines)" >&2
  status=1
fi
composition_fields="$(
  sed -n '/struct ExtensionNormalTabRuntimeComposition {/,/^}/p' "$assembler" \
    | guard_count_matches '^    let ' -
)"
composition_fields="${composition_fields:-0}"
if (( composition_fields > 10 )); then
  echo "error: normal Tab lifetime composition grew beyond 10 leaves ($composition_fields)" >&2
  status=1
fi

late_bound_materializer_hits="$(
  guard_capture_matches \
    '@MainActor \(\) -> \(any Extension(TabWebViewHosting|LiveWebViewRuntimePreparing)\)\?' \
    "$requested_webview_materializer"
)"
late_bound_preparation_hits="$(
  guard_capture_matches 'func bind\(tabRegistration:' "$live_webview_preparation"
)"
if [[ -n "$late_bound_materializer_hits" \
    || -n "$late_bound_preparation_hits" ]]; then
  echo 'error: normal Tab WebView roles regained late-bound closure wiring' >&2
  status=1
fi
browser_context_count="$(
  guard_count_matches \
    'private weak var browserContext:' "$requested_webview_materializer" -F
)"
live_preparation_count="$(
  guard_count_matches \
    'private weak var livePreparation:' "$requested_webview_materializer" -F
)"
materializer_leaf_count="$(
  guard_count_matches 'let requestedTabWebViewMaterializer:' "$assembler" -F
)"
if (( browser_context_count == 0 \
    || live_preparation_count == 0 \
    || materializer_leaf_count == 0 )); then
  echo 'error: requested Tab WebView materializer escaped typed normal-runtime composition' >&2
  status=1
fi
materializer_constructions="$(
  guard_count_matches 'ExtensionRequestedTabWebViewMaterializer\(' \
    Sumi/Managers/ExtensionManager
)"
materializer_constructions="${materializer_constructions:-0}"
if (( materializer_constructions != 1 )); then
  echo "error: requested Tab WebView materializer must have one composition root ($materializer_constructions)" >&2
  status=1
fi

role_caps=(
  "$open:330" "$close:180" "$queries:170" "$registration:150"
  "$properties:110" "$rebind:210" "$deferred:145"
  "$events:80" "$policy:65" "$visibility:90"
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

for preparation_class in \
  'ExtensionWebViewConfigurationPreparation' \
  'ExtensionLiveWebViewRuntimePreparation'; do
  preparation_file="$cold_webview_preparation"
  if [[ "$preparation_class" == 'ExtensionLiveWebViewRuntimePreparation' ]]; then
    preparation_file="$live_webview_preparation"
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
    echo "error: split WebView preparation reached through a root/bag/Owner: $preparation_class" >&2
    status=1
  fi
done

if (( status != 0 )); then
  exit "$status"
fi
echo 'extension normal Tab runtime boundary passed'
