#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

capabilities="Sumi/Models/Tab/Navigation/PopupNavigationCapabilities.swift"
runtime_state="Sumi/Models/Tab/TabRuntimeState.swift"
responder="Sumi/Models/Tab/Navigation/SumiPopupHandlingNavigationResponder.swift"
child_webview_transaction="Sumi/Models/Tab/Navigation/WebKitChildWebViewTransaction.swift"
child_surface_router="Sumi/Models/Tab/Navigation/WebKitChildSurfaceRouter.swift"
glance_routing="Sumi/Models/Tab/Navigation/LinkGlanceRouting.swift"
delegate_bundle="Sumi/Models/Tab/Navigation/SumiTabNavigationDelegateBundle.swift"
runtime_factory="Sumi/Managers/BrowserManager/TabBrowserRuntimeFactory.swift"
lifecycle_factory="Sumi/Managers/BrowserManager/BrowserTabManagerWebViewLifecycleFactory.swift"
runtime_ports_factory="Sumi/Managers/BrowserManager/BrowserTabManagerRuntimePortsFactory.swift"
glance_runtime="Sumi/Managers/BrowserManager/BrowserGlanceRuntimeService.swift"
extension_opening="Sumi/Managers/BrowserManager/ExtensionExternalTabOpeningService.swift"
physical_popup="Sumi/Managers/BrowserManager/PhysicalWebPopupOpeningService.swift"
child_tab_opening="Sumi/Managers/BrowserManager/WebKitChildTabOpeningService.swift"
child_tab_creation="Sumi/Managers/BrowserManager/WebKitChildTabCreationTransaction.swift"
child_tab_settlement="Sumi/Managers/BrowserManager/WebKitChildTabSettlementTransaction.swift"
child_window_opening="Sumi/Managers/BrowserManager/WebKitChildWindowOpeningService.swift"
auxiliary_factory="Sumi/AuxiliaryWindows/AuxiliaryWebViewFactory.swift"
browser_configuration="Sumi/Models/BrowserConfig/BrowserConfig.swift"
production_roots=(App Sumi Settings SidebarChrome CommandPalette UI)
status=0




enforce_service_boundary() {
  local file="$1"
  local max_lines="$2"
  local max_collaborators="$3"
  local line_count
  local collaborator_count
  line_count="$(guard_count_lines "$file")"
  collaborator_count="$(
    guard_count_matches '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' \
      "$file"
  )"
  if (( line_count > max_lines )); then
    printf 'error: popup behavioral service exceeded its focused boundary: %s (%s > %s lines)\n' \
      "$file" "$line_count" "$max_lines" >&2
    status=1
  fi
  if (( ${collaborator_count:-0} > max_collaborators )); then
    printf 'error: popup behavioral service became a collaboration hub: %s (%s > %s collaborators)\n' \
      "$file" "$collaborator_count" "$max_collaborators" >&2
    status=1
  fi
}

for required in \
  "$capabilities" \
  "$runtime_state" \
  "$responder" \
  "$child_webview_transaction" \
  "$child_surface_router" \
  "$glance_routing" \
  "$delegate_bundle" \
  "$runtime_factory" \
  "$lifecycle_factory" \
  "$runtime_ports_factory" \
  "$glance_runtime" \
  "$extension_opening" \
  "$physical_popup" \
  "$child_tab_opening" \
  "$child_tab_creation" \
  "$child_tab_settlement" \
  "$child_window_opening" \
  "$auxiliary_factory" \
  "$browser_configuration"; do
  guard_require_file "$required"
done

for retired_path in \
  Sumi/Managers/BrowserManager/TabPopupRuntimeFactory.swift \
  Sumi/Models/Tab/Navigation/TabPopupHandlingRuntime.swift; do
  if [[ -e "$retired_path" ]]; then
    printf 'error: retired popup closure-bag path reintroduced: %s\n' \
      "$retired_path" >&2
    status=1
  fi
done

retired_surface_hits="$(
  guard_capture_matches '\b(TabPopupHandlingRuntime|TabPopupRuntimeFactory|popupHandlingRuntime)\b' \
    "${production_roots[@]}" SumiTests -g '*.swift'
)"
if [[ -n "$retired_surface_hits" ]]; then
  guard_record_failure "retired popup closure-bag surface reintroduced:
$retired_surface_hits"
fi

replacement_bag_hits="$(
  guard_capture_matches '\b(class|struct|enum)[[:space:]]+(PopupNavigationServices|PopupNavigationRuntime|PopupNavigationCapabilities)\b|\bstruct[[:space:]]+Dependencies\b' \
    "$runtime_state" "$responder" "$child_webview_transaction" \
    "$child_surface_router" "$glance_routing" "$extension_opening" \
    "$physical_popup" "$child_tab_opening" "$child_tab_creation" \
    "$child_tab_settlement"
)"
if [[ -n "$replacement_bag_hits" ]]; then
  guard_record_failure "popup closure bag hidden behind a replacement container:
$replacement_bag_hits"
fi

runtime_fields=(
  popupPermissionEvaluator
  extensionPopupRequestConsumer
  extensionExternalTabOpening
  physicalWebPopupOpening
  webKitChildTabOpening
  webKitChildWindowOpening
)
for field in "${runtime_fields[@]}"; do
  field_count="$(
    guard_count_matches "^[[:space:]]*var[[:space:]]+${field}:" "$runtime_state"
  )"
  if [[ "$field_count" != "2" ]]; then
    printf 'error: %s must be stored directly once in TabBrowserRuntime and once in TabNavigationRuntime (found %s)\n' \
      "$field" "${field_count:-0}" >&2
    status=1
  fi
  contract_count="$(
    guard_count_matches "tab\\.navigationRuntime\\.${field}" "$delegate_bundle"
  )"
  if (( contract_count == 0 )); then
    guard_record_failure "navigation delegate composition must inject ${field} explicitly"
  fi
done

responder_lookup_hits="$(
  guard_capture_matches '\b(tab|self\.tab)\.navigationRuntime\b|\bTabBrowserRuntime\b|\bTabNavigationRuntime\b' \
    "$responder"
)"
if [[ -n "$responder_lookup_hits" ]]; then
  guard_record_failure "popup responder performs runtime/service lookup after composition:
$responder_lookup_hits"
fi

for protocol_name in \
  PopupPermissionEvaluating \
  ExtensionPopupRequestConsuming \
  ExtensionExternalTabOpening \
  PhysicalWebPopupOpening \
  WebKitChildTabOpening \
  WebKitChildWindowOpening; do
  contract_count="$(
    guard_count_matches "protocol[[:space:]]+${protocol_name}\\b" "$capabilities"
  )"
  if (( contract_count == 0 )); then
    guard_record_failure "typed popup capability missing: ${protocol_name}"
  fi
done

contract_count="$(guard_count_matches 'ExtensionExternalTabOpeningService\(' "$runtime_factory")"
if (( contract_count == 0 )); then
  guard_record_failure "popup composition must construct the external extension Tab service"
fi
contract_count="$(guard_count_matches 'PhysicalWebPopupOpeningService\(' "$runtime_factory")"
if (( contract_count == 0 )); then
  guard_record_failure "popup composition must construct the exact-source Web popup service"
fi
contract_count="$(guard_count_matches 'WebKitChildTabOpeningService\(' "$runtime_factory")"
if (( contract_count == 0 )); then
  guard_record_failure "popup composition must construct the WebKit child Tab service"
fi
contract_count="$(guard_count_matches 'WebKitChildWindowOpeningService\(' "$runtime_factory")"
if (( contract_count == 0 )); then
  guard_record_failure "popup composition must construct the WebKit child window transaction"
fi

behavioral_service_hits="$(
  guard_capture_matches '\bBrowserManager\b|\bbrowserManager\b|\b(activeWindow|currentWindow)\b' \
    "$extension_opening" "$physical_popup" "$child_tab_opening" \
    "$child_tab_creation" "$child_tab_settlement"
)"
if [[ -n "$behavioral_service_hits" ]]; then
  guard_record_failure "popup behavioral service depends on a browser root or current-window fallback:
$behavioral_service_hits"
fi

for service in "$extension_opening" "$physical_popup" "$child_tab_opening" \
  "$child_tab_creation" "$child_tab_settlement"; do
  stored_closure_count="$(
    guard_count_matches '^[[:space:]]*private[[:space:]]+(let|var)[^:]*:.*->' \
      "$service"
  )"
  if (( ${stored_closure_count:-0} > 1 )); then
    printf 'error: popup behavioral service stores a closure bag: %s (%s closures)\n' \
      "$service" "$stored_closure_count" >&2
    status=1
  fi
done

enforce_service_boundary "$extension_opening" 80 3
enforce_service_boundary "$physical_popup" 80 2
enforce_service_boundary "$child_tab_opening" 80 3
enforce_service_boundary "$child_tab_creation" 120 4
enforce_service_boundary "$child_tab_settlement" 160 5
enforce_service_boundary "$responder" 300 3
enforce_service_boundary "$child_webview_transaction" 250 4
enforce_service_boundary "$child_surface_router" 125 4
enforce_service_boundary "$glance_routing" 65 0

contract_count="$(guard_count_matches 'childWebViewTransaction[[:space:]]*=[[:space:]]*WebKitChildWebViewTransaction\(' "$responder")"
if (( contract_count == 0 )); then
  guard_record_failure "popup responder must compose the exact WebKit child transaction"
fi
contract_count="$(guard_count_matches 'childSurfaceRouter:[[:space:]]*WebKitChildSurfaceRouter\(' "$responder")"
if (( contract_count == 0 )); then
  guard_record_failure "popup responder must compose disposition separately from admission"
fi

responder_child_dispatch_hits="$(
  guard_capture_matches '\b(extensionTabs|webPopups|childTabs|childWindows)\?\.open\(' \
    "$responder"
)"
if [[ -n "$responder_child_dispatch_hits" ]]; then
  guard_record_failure "popup responder regained direct child-surface dispatch:
$responder_child_dispatch_hits"
fi

contract_count="$(guard_count_matches 'let[[:space:]]+sourceDocumentLease[[:space:]]*=[[:space:]]*tab\.committedDocumentRuntime\.lease' "$child_webview_transaction")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child admission must capture the exact source document"
fi
contract_count="$(guard_count_matches '==[[:space:]]*pending\.sourceDocumentLease' "$child_webview_transaction")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child commit must revalidate its exact source document"
fi
contract_count="$(guard_count_matches 'configuration\.websiteDataStore[[:space:]]*===' "$child_webview_transaction")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child admission must reject a cross-partition configuration"
fi
contract_count="$(guard_count_matches 'sourceWebView\.configuration\.websiteDataStore' "$child_webview_transaction")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child admission must bind partition validation to its source WebView"
fi
contract_count="$(guard_count_matches 'if[[:space:]]+let[[:space:]]+explicitClassification[[:space:]]*=[[:space:]]*objc_getAssociatedObject' "$browser_configuration")"
if (( contract_count == 0 )); then
  guard_record_failure "WebView surface classification must let explicit auxiliary state override an inherited normal controller"
fi
contract_count="$(guard_count_matches 'webView\.configuration\.sumiIsNormalTabWebViewConfiguration[[:space:]]*=[[:space:]]*false' "$auxiliary_factory")"
if (( contract_count == 0 )); then
  guard_record_failure "the auxiliary WebView factory must classify every materialized child explicitly"
fi

popup_transaction_root_hits="$(
  guard_capture_matches '\bBrowserManager\b|\bbrowserManager\b|\bTabBrowserRuntime\b|\bTabNavigationRuntime\b' \
    "$child_webview_transaction" "$child_surface_router" \
    "$glance_routing"
)"
if [[ -n "$popup_transaction_root_hits" ]]; then
  guard_record_failure "popup transaction performs browser-root or runtime lookup:
$popup_transaction_root_hits"
fi

contract_count="$(guard_count_matches 'guard[[:space:]]+let[[:space:]]+extensionTabs,' "$extension_opening")"
if (( contract_count == 0 )); then
  guard_record_failure "external extension Tab opening must acquire its registrar before mutation"
fi
contract_count="$(guard_count_matches 'isExtensionOriginated[[:space:]]*==[[:space:]]*false[[:space:]]*\|\|[[:space:]]*extensionTabs[[:space:]]*!=[[:space:]]*nil' "$child_tab_settlement")"
if (( contract_count == 0 )); then
  guard_record_failure "extension WebKit child opening must require a registrar before mutation"
fi
child_admission_line="$(
  guard_capture_matches 'let admission = settlement\.admit' "$child_tab_opening" \
    | cut -d: -f1
)"
child_creation_line="$(
  guard_capture_matches 'let prepared = creation\.prepare' "$child_tab_opening" \
    | cut -d: -f1
)"
if [[ -z "$child_admission_line" || -z "$child_creation_line" ]] \
  || (( child_admission_line >= child_creation_line )); then
  guard_record_failure "WebKit child settlement admission must precede model creation"
fi
contract_count="$(guard_count_matches 'configuration\.websiteDataStore[[:space:]]*===[[:space:]]*source\.dataStore' "$child_tab_opening")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child Tabs must preserve the exact source data-store partition"
fi
contract_count="$(guard_count_matches 'let[[:space:]]+sourceWindow[[:space:]]*=[[:space:]]*source\.appKitWindow' "$physical_popup")"
if (( contract_count == 0 )); then
  guard_record_failure "physical Web popups must require the exact published source shell"
fi
contract_count="$(guard_count_matches 'explicitOpenerWindow:[[:space:]]*sourceWindow' "$physical_popup")"
if (( contract_count == 0 )); then
  guard_record_failure "physical Web popups must pass a non-optional exact source shell"
fi

post_publication_child_registration_hits="$(
  guard_capture_matches '\bregisterExtensionTab\b|registerExtensionCreatedTabWithExtensionRuntimeIfLoaded' \
    "$child_window_opening"
)"
if [[ -n "$post_publication_child_registration_hits" ]]; then
  guard_record_failure "WebKit child Tab registered after its window publication:
$post_publication_child_registration_hits"
fi
contract_count="$(guard_count_matches 'extensionPublication:[[:space:]]*browserManager\.windowExtensionPublication' "$runtime_factory")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child windows must share the window-registration publication transaction"
fi
contract_count="$(guard_count_matches 'extensionPublication\.stageInitialTab\(' "$child_window_opening")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child windows must stage their exact initial Tab before publication"
fi
contract_count="$(guard_count_matches 'extensionPublication\.validateStagedInitialTab\(' "$child_window_opening")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child windows must revalidate staged extension publication"
fi
contract_count="$(guard_count_matches 'source\.usesPresentationProfileForExecution[[:space:]]*==[[:space:]]*false' "$child_window_opening")"
if (( contract_count == 0 )); then
  guard_record_failure "extension child windows must reject a known cross-profile source before mutation"
fi
contract_count="$(guard_count_matches 'case[[:space:]]+\.suppressed:' "$child_window_opening")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child publication must handle extension projection suppression explicitly"
fi
contract_count="$(guard_count_matches 'validateChildBeforePublication' \
  Sumi/Managers/BrowserManager/WebKitChildWindowShellTransaction.swift)"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child publication must validate inside the pre-registry transaction"
fi

contract_count="$(guard_count_matches 'tabBrowserRuntime:[[:space:]]*browserManager\.tabBrowserRuntimeReference' "$runtime_ports_factory")"
if (( contract_count == 0 )); then
  guard_record_failure "Tab runtime-port composition must inject the browser's shared runtime reference into lifecycle"
fi
contract_count="$(guard_count_matches 'attachBrowserRuntime\(tabBrowserRuntime\)' "$lifecycle_factory")"
if (( contract_count == 0 )); then
  guard_record_failure "Tab lifecycle preparation must attach its shared runtime"
fi
contract_count="$(guard_count_matches 'let[[:space:]]+tabBrowserRuntime[[:space:]]*=[[:space:]]*TabBrowserRuntimeFactory\.make\(for:[[:space:]]*browserManager\)' "$glance_runtime")"
if (( contract_count == 0 )); then
  guard_record_failure "Glance composition must share one assembled runtime"
fi
contract_count="$(guard_count_matches 'attachBrowserRuntime\(tabBrowserRuntime\)' "$glance_runtime")"
if (( contract_count == 0 )); then
  guard_record_failure "Glance preview Tabs must attach the shared runtime"
fi
contract_count="$(guard_count_matches 'beginReferenceMutation\(' "$glance_runtime")"
if (( contract_count != 1 )); then
  guard_record_failure "Glance preview publication must begin one profile-reference mutation lease"
fi
contract_count="$(guard_count_matches 'validate\(lease,[[:space:]]*covers:[[:space:]]*referencedProfileIDs\)' "$glance_runtime")"
if (( contract_count != 1 )); then
  guard_record_failure "Glance preview publication must validate its exact profile-reference lease"
fi
contract_count="$(guard_count_matches 'endReferenceMutation\(lease\)' "$glance_runtime")"
if (( contract_count != 1 )); then
  guard_record_failure "Glance preview publication must close its profile-reference mutation lease"
fi

if (( status != 0 || guard_failures != 0 )); then
  echo "popup navigation architecture audit failed" >&2
  exit 1
fi

echo "popup navigation architecture audit passed"
