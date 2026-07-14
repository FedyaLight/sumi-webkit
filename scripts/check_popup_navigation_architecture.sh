#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

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
child_window_opening="Sumi/Managers/BrowserManager/WebKitChildWindowOpeningService.swift"
auxiliary_factory="Sumi/AuxiliaryWindows/AuxiliaryWebViewFactory.swift"
browser_configuration="Sumi/Models/BrowserConfig/BrowserConfig.swift"
production_roots=(App Sumi Settings SidebarChrome FloatingBar UI)
status=0

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

require_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf 'error: popup navigation architecture file missing: %s\n' \
      "$file" >&2
    status=1
  fi
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if [[ ! -f "$file" ]] || ! rg -q "$pattern" "$file"; then
    printf 'error: %s\n' "$message" >&2
    status=1
  fi
}

require_test() {
  local test_name="$1"
  if ! rg -q "func[[:space:]]+${test_name}\\b" SumiTests -g '*.swift'; then
    printf 'error: required popup navigation regression missing: %s\n' \
      "$test_name" >&2
    status=1
  fi
}

enforce_service_boundary() {
  local file="$1"
  local max_lines="$2"
  local max_collaborators="$3"
  local line_count
  local collaborator_count
  line_count="$(wc -l < "$file" | tr -d ' ')"
  collaborator_count="$(
    rg -c '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' \
      "$file" || true
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
  "$child_window_opening" \
  "$auxiliary_factory" \
  "$browser_configuration"; do
  require_file "$required"
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
  rg -n '\b(TabPopupHandlingRuntime|TabPopupRuntimeFactory|popupHandlingRuntime)\b' \
    "${production_roots[@]}" SumiTests -g '*.swift' || true
)"
fail_matches "retired popup closure-bag surface reintroduced" \
  "$retired_surface_hits"

replacement_bag_hits="$(
  rg -n '\b(class|struct|enum)[[:space:]]+(PopupNavigationServices|PopupNavigationRuntime|PopupNavigationCapabilities)\b|\bstruct[[:space:]]+Dependencies\b' \
    "$runtime_state" "$responder" "$child_webview_transaction" \
    "$child_surface_router" "$glance_routing" "$extension_opening" \
    "$physical_popup" "$child_tab_opening" || true
)"
fail_matches "popup closure bag hidden behind a replacement container" \
  "$replacement_bag_hits"

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
    rg -c "^[[:space:]]*var[[:space:]]+${field}:" "$runtime_state" || true
  )"
  if [[ "$field_count" != "2" ]]; then
    printf 'error: %s must be stored directly once in TabBrowserRuntime and once in TabNavigationRuntime (found %s)\n' \
      "$field" "${field_count:-0}" >&2
    status=1
  fi
  require_pattern \
    "$delegate_bundle" \
    "tab\\.navigationRuntime\\.${field}" \
    "navigation delegate composition must inject ${field} explicitly"
done

responder_lookup_hits="$(
  rg -n '\b(tab|self\.tab)\.navigationRuntime\b|\bTabBrowserRuntime\b|\bTabNavigationRuntime\b' \
    "$responder" || true
)"
fail_matches "popup responder performs runtime/service lookup after composition" \
  "$responder_lookup_hits"

for protocol_name in \
  PopupPermissionEvaluating \
  ExtensionPopupRequestConsuming \
  ExtensionExternalTabOpening \
  PhysicalWebPopupOpening \
  WebKitChildTabOpening \
  WebKitChildWindowOpening; do
  require_pattern \
    "$capabilities" \
    "protocol[[:space:]]+${protocol_name}\\b" \
    "typed popup capability missing: ${protocol_name}"
done

require_pattern \
  "$runtime_factory" \
  'ExtensionExternalTabOpeningService\(' \
  "popup composition must construct the external extension Tab service"
require_pattern \
  "$runtime_factory" \
  'PhysicalWebPopupOpeningService\(' \
  "popup composition must construct the exact-source Web popup service"
require_pattern \
  "$runtime_factory" \
  'WebKitChildTabOpeningService\(' \
  "popup composition must construct the WebKit child Tab service"
require_pattern \
  "$runtime_factory" \
  'WebKitChildWindowOpeningService\(' \
  "popup composition must construct the WebKit child window transaction"

behavioral_service_hits="$(
  rg -n '\bBrowserManager\b|\bbrowserManager\b|\b(activeWindow|currentWindow)\b' \
    "$extension_opening" "$physical_popup" "$child_tab_opening" || true
)"
fail_matches "popup behavioral service depends on a browser root or current-window fallback" \
  "$behavioral_service_hits"

for service in "$extension_opening" "$physical_popup" "$child_tab_opening"; do
  stored_closure_count="$(
    rg -c '^[[:space:]]*private[[:space:]]+(let|var)[^:]*:.*->' \
      "$service" || true
  )"
  if (( ${stored_closure_count:-0} > 1 )); then
    printf 'error: popup behavioral service stores a closure bag: %s (%s closures)\n' \
      "$service" "$stored_closure_count" >&2
    status=1
  fi
done

enforce_service_boundary "$extension_opening" 80 3
enforce_service_boundary "$physical_popup" 80 2
enforce_service_boundary "$child_tab_opening" 160 6
enforce_service_boundary "$responder" 300 3
enforce_service_boundary "$child_webview_transaction" 250 4
enforce_service_boundary "$child_surface_router" 125 4
enforce_service_boundary "$glance_routing" 65 0

require_pattern \
  "$responder" \
  'childWebViewTransaction[[:space:]]*=[[:space:]]*WebKitChildWebViewTransaction\(' \
  "popup responder must compose the exact WebKit child transaction"
require_pattern \
  "$responder" \
  'childSurfaceRouter:[[:space:]]*WebKitChildSurfaceRouter\(' \
  "popup responder must compose disposition separately from admission"

responder_child_dispatch_hits="$(
  rg -n '\b(extensionTabs|webPopups|childTabs|childWindows)\?\.open\(' \
    "$responder" || true
)"
fail_matches "popup responder regained direct child-surface dispatch" \
  "$responder_child_dispatch_hits"

require_pattern \
  "$child_webview_transaction" \
  'let[[:space:]]+sourceDocumentLease[[:space:]]*=[[:space:]]*tab\.committedDocumentRuntime\.lease' \
  "WebKit child admission must capture the exact source document"
require_pattern \
  "$child_webview_transaction" \
  '==[[:space:]]*pending\.sourceDocumentLease' \
  "WebKit child commit must revalidate its exact source document"
require_pattern \
  "$child_webview_transaction" \
  'configuration\.websiteDataStore[[:space:]]*===' \
  "WebKit child admission must reject a cross-partition configuration"
require_pattern \
  "$child_webview_transaction" \
  'sourceWebView\.configuration\.websiteDataStore' \
  "WebKit child admission must bind partition validation to its source WebView"
require_pattern \
  "$browser_configuration" \
  'if[[:space:]]+let[[:space:]]+explicitClassification[[:space:]]*=[[:space:]]*objc_getAssociatedObject' \
  "WebView surface classification must let explicit auxiliary state override an inherited normal controller"
require_pattern \
  "$auxiliary_factory" \
  'webView\.configuration\.sumiIsNormalTabWebViewConfiguration[[:space:]]*=[[:space:]]*false' \
  "the auxiliary WebView factory must classify every materialized child explicitly"

popup_transaction_root_hits="$(
  rg -n '\bBrowserManager\b|\bbrowserManager\b|\bTabBrowserRuntime\b|\bTabNavigationRuntime\b' \
    "$child_webview_transaction" "$child_surface_router" \
    "$glance_routing" || true
)"
fail_matches "popup transaction performs browser-root or runtime lookup" \
  "$popup_transaction_root_hits"

require_pattern \
  "$extension_opening" \
  'guard[[:space:]]+let[[:space:]]+extensionTabs,' \
  "external extension Tab opening must acquire its registrar before mutation"
require_pattern \
  "$child_tab_opening" \
  'isExtensionOriginated[[:space:]]*==[[:space:]]*false[[:space:]]*\|\|[[:space:]]*extensionTabs[[:space:]]*!=[[:space:]]*nil' \
  "extension WebKit child opening must require a registrar before mutation"
require_pattern \
  "$child_tab_opening" \
  'configuration\.websiteDataStore[[:space:]]*===[[:space:]]*source\.dataStore' \
  "WebKit child Tabs must preserve the exact source data-store partition"
require_pattern \
  "$physical_popup" \
  'let[[:space:]]+sourceWindow[[:space:]]*=[[:space:]]*source\.appKitWindow' \
  "physical Web popups must require the exact published source shell"
require_pattern \
  "$physical_popup" \
  'explicitOpenerWindow:[[:space:]]*sourceWindow' \
  "physical Web popups must pass a non-optional exact source shell"

post_publication_child_registration_hits="$(
  rg -n '\bregisterExtensionTab\b|registerExtensionCreatedTabWithExtensionRuntimeIfLoaded' \
    "$child_window_opening" || true
)"
fail_matches "WebKit child Tab registered after its window publication" \
  "$post_publication_child_registration_hits"
require_pattern \
  "$runtime_factory" \
  'extensionPublication:[[:space:]]*browserManager\.windowExtensionPublication' \
  "WebKit child windows must share the window-registration publication transaction"
require_pattern \
  "$child_window_opening" \
  'extensionPublication\.stageInitialTab\(' \
  "WebKit child windows must stage their exact initial Tab before publication"
require_pattern \
  "$child_window_opening" \
  'extensionPublication\.validateStagedInitialTab\(' \
  "WebKit child windows must revalidate staged extension publication"
require_pattern \
  "$child_window_opening" \
  'source\.usesPresentationProfileForExecution[[:space:]]*==[[:space:]]*false' \
  "extension child windows must reject a known cross-profile source before mutation"
require_pattern \
  "$child_window_opening" \
  'case[[:space:]]+\.suppressed:' \
  "WebKit child publication must handle extension projection suppression explicitly"
require_pattern \
  "Sumi/Managers/BrowserManager/WebKitChildWindowShellTransaction.swift" \
  'validateChildBeforePublication' \
  "WebKit child publication must validate inside the pre-registry transaction"

require_pattern \
  "$runtime_ports_factory" \
  'tabBrowserRuntime:[[:space:]]*TabBrowserRuntimeFactory\.make\(for:[[:space:]]*browserManager\)' \
  "Tab runtime-port composition must inject one assembled runtime into lifecycle"
require_pattern \
  "$lifecycle_factory" \
  'attachBrowserRuntime\(tabBrowserRuntime\)' \
  "Tab lifecycle preparation must attach its shared runtime"
require_pattern \
  "$glance_runtime" \
  'let[[:space:]]+tabBrowserRuntime[[:space:]]*=[[:space:]]*TabBrowserRuntimeFactory\.make\(for:[[:space:]]*browserManager\)' \
  "Glance composition must share one assembled runtime"
require_pattern \
  "$glance_runtime" \
  'attachBrowserRuntime\(tabBrowserRuntime\)' \
  "Glance preview Tabs must attach the shared runtime"

for required_test in \
  testExtensionTabOpenersRejectUnavailableRegistrarBeforeMutation \
  testPhysicalWebPopupRejectsSourceWithoutPublishedShellBeforeMutation \
  testExtensionPopupExternalCreateWebViewRejectsMissingSourceResidence \
  testExtensionWebKitChildWindowRejectsCrossProfileSourceBeforeMutation \
  testExtensionWebKitChildWindowPublishesRegistryThenWindowThenExactTab \
  testExtensionWebKitChildWindowRejectsSuppressedProjectionAndRollsBack \
  testOrdinaryWebKitChildWindowAllowsSuppressedExtensionProjection \
  testWebKitChildWindowRejectsMismatchedDataStoreWithoutMutation \
  testWindowLocalShortcutLeaseRejectsWrongWindowClone \
  testPopupCreateWebViewRejectsDocumentChangedDuringSynchronousPermission \
  testPopupCreateWebViewRejectsDocumentChangedDuringAsyncPermission \
  testPopupCreateWebViewRejectsMismatchedDataStoreBeforePermission \
  testPopupChildKeepsCopiedNormalConfigurationButIsAuxiliarySurface; do
  require_test "$required_test"
done

if [[ "$status" -ne 0 ]]; then
  echo "popup navigation architecture audit failed" >&2
  exit "$status"
fi

echo "popup navigation architecture audit passed"
