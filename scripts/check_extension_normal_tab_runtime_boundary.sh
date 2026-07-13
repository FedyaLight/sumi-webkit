#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

old='Sumi/Managers/ExtensionManager/ExtensionNormalTabRuntimeBindingOwner.swift'
open='Sumi/Managers/ExtensionManager/ExtensionNormalTabOpenTransaction.swift'
queries='Sumi/Managers/ExtensionManager/ExtensionNormalTabPublicationQueries.swift'
registration='Sumi/Managers/ExtensionManager/ExtensionNormalTabRegistration.swift'
properties='Sumi/Managers/ExtensionManager/ExtensionTabPropertyPublisher.swift'
rebind='Sumi/Managers/ExtensionManager/ExtensionTabLifecycleRebindTransaction.swift'
deferred='Sumi/Managers/ExtensionManager/ExtensionDeferredTabRegistration.swift'
events='Sumi/Managers/ExtensionManager/ExtensionTabLifecycleEmitter.swift'
policy='Sumi/Managers/ExtensionManager/ExtensionContentScriptBindingPolicy.swift'
visibility='Sumi/Managers/ExtensionManager/ExtensionPreparedTabVisibility.swift'
bridge='Sumi/Managers/ExtensionManager/ExtensionBridge.swift'
composition='Sumi/Managers/ExtensionManager/ExtensionManager+RuntimePublicationComposition.swift'
assembler='Sumi/Managers/ExtensionManager/ExtensionNormalTabRuntimeAssembler.swift'
controller='Sumi/Managers/ExtensionManager/ExtensionControllerAttachmentOwner.swift'
webview_preparation='Sumi/Managers/ExtensionManager/ExtensionWebViewRuntimePreparationOwner.swift'

status=0

if [[ -e "$old" ]]; then
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
  rg -n '\bExtensionManager(Runtime)?\b|\bBrowserManager\b|\bstruct (Dependencies|Actions)\b|\bclass [A-Za-z0-9_]*Owner\b' \
    "${roles[@]}" || true
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
  hits="$(rg -n -F "$old_facade" Sumi/Managers/ExtensionManager || true)"
  if [[ -n "$hits" ]]; then
    printf 'error: deleted normal Tab manager facade returned (%s):\n%s\n' \
      "$old_facade" "$hits" >&2
    status=1
  fi
done

if (( $(rg -Fc 'tabs?.extensionTab(for: tab.id) === tab' "$open") < 2 )); then
  echo 'error: open transaction lacks pre/post exact physical Tab proof' >&2
  status=1
fi
if (( $(rg -Fc 'remainsCurrent(' "$open") < 3 )); then
  echo 'error: open transaction lacks pre/post callback validation' >&2
  status=1
fi
if ! rg -Fq 'claimDidOpenTabNotificationForClose(' "$open"; then
  echo 'error: rejected open is not balanced through its exact claim' >&2
  status=1
fi

claim_line="$(rg -n 'claimDidOpenTabNotificationForClose\(' "$rebind" | head -1 | cut -d: -f1)"
close_line="$(rg -n 'events\.emitDidCloseTab\(' "$rebind" | head -1 | cut -d: -f1)"
if [[ -z "$claim_line" || -z "$close_line" ]] || (( claim_line >= close_line )); then
  echo 'error: navigation rebind must claim close before didCloseTab' >&2
  status=1
fi

if (( $(rg -Fc 'tabs?.extensionTab(for: tabID) === tab' "$deferred") < 2 )); then
  echo 'error: deferred registration can admit a same-UUID replacement' >&2
  status=1
fi

published_last="$(rg -n -F 'publishedTabs?.containsPublishedTab(tab) == true' "$properties" | tail -1 | cut -d: -f1 || true)"
cache_first="$(rg -n 'recordReported(URL|LoadingComplete|Title)IfChanged' "$properties" | head -1 | cut -d: -f1 || true)"
if [[ -z "$published_last" || -z "$cache_first" ]] || (( published_last >= cache_first )); then
  echo 'error: property cache can mutate before post-resolution publication proof' >&2
  status=1
fi

if rg -n 'tabNeedsExtensionContentScriptRebind|registerTabWithExtensionRuntime' \
    "$controller" "$webview_preparation" >/dev/null; then
  echo 'error: controller/WebView closure cycle into normal Tab runtime returned' >&2
  status=1
fi

if ! rg -Fq 'publishedExtensionTabs.containsPublishedTab(tab)' "$bridge" \
    || ! rg -Fq 'preparedTabVisibility.allowsPreparedTabRead(' "$bridge"; then
  echo 'error: extension window Tab reads lack published-or-scoped authority' >&2
  status=1
fi
scope_line="$(rg -n -F 'guard tabScopes.isEmpty == false' "$visibility" | cut -d: -f1 || true)"
handoff_line="$(rg -n -F 'isBrowserEventHandoffActive == true' "$visibility" | cut -d: -f1 || true)"
if [[ -z "$scope_line" || -z "$handoff_line" ]] || (( scope_line >= handoff_line )); then
  echo 'error: reload handoff can grant prepared Tab reads outside a Tab callback' >&2
  status=1
fi

composition_declarations="$(rg -Fc 'struct ExtensionNormalTabRuntimeComposition' "$assembler" || true)"
composition_declarations="${composition_declarations:-0}"
if (( composition_declarations != 1 )); then
  echo 'error: normal Tab leaf lifetime composition missing' >&2
  status=1
fi
composition_refs="$(rg -l 'ExtensionNormalTabRuntimeComposition' Sumi | wc -l | tr -d ' ')"
if (( composition_refs > 2 )); then
  echo 'error: normal Tab lifetime composition escaped its builder/store boundary' >&2
  status=1
fi
assembler_lines="$(wc -l < "$assembler" | tr -d ' ')"
if (( assembler_lines > 240 )); then
  echo "error: normal Tab assembler grew beyond 240 LOC ($assembler_lines)" >&2
  status=1
fi
composition_fields="$(sed -n '/struct ExtensionNormalTabRuntimeComposition {/,/^}/p' "$assembler" | rg -c '^    let ' || true)"
composition_fields="${composition_fields:-0}"
if (( composition_fields > 10 )); then
  echo "error: normal Tab lifetime composition grew beyond 10 leaves ($composition_fields)" >&2
  status=1
fi

role_caps=(
  "$open:330" "$queries:170" "$registration:150"
  "$properties:110" "$rebind:210" "$deferred:145"
  "$events:80" "$policy:65" "$visibility:85"
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
echo 'extension normal Tab runtime boundary passed'
