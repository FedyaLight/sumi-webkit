#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

production_roots=(App Sumi Settings SidebarChrome CommandPalette UI)
all_swift_roots=("${production_roots[@]}" SumiTests SumiUITests)
focusable_web_view="Sumi/Utils/WebKit/FocusableWKWebView.swift"
interaction_state="Sumi/Utils/WebKit/WebViewInteractionState.swift"
link_script="Sumi/UserScripts/SumiLinkInteractionUserScript.swift"
context_menu_script="Sumi/UserScripts/SumiWebPageContextMenuUserScript.swift"
link_presentation_commands="Sumi/Models/Tab/TabLinkPresentationCommands.swift"
link_presentation_factory="Sumi/Managers/BrowserManager/TabLinkPresentationCommandsFactory.swift"
physical_source_receipt="Sumi/Managers/BrowserManager/PhysicalWebViewSourceReceipt.swift"
physical_source_context="Sumi/Managers/BrowserManager/BrowserWindowSourceContext.swift"
host_services_runtime="Sumi/Managers/BrowserManager/TabBrowserHostServicesRuntimeFactory.swift"
window_state="Sumi/Models/BrowserWindowState.swift"
tab_residence_authority="Sumi/Managers/BrowserManager/BrowserTabResidenceAuthority.swift"
retired_residence_admission="Sumi/Managers/BrowserManager/ExactTabResidenceAdmission.swift"
manager_free_window_transactions=(
  Sumi/Managers/BrowserManager/PhysicalSourceTabOpeningService.swift
  Sumi/Managers/BrowserManager/WebKitChildTabOpeningService.swift
  Sumi/Managers/BrowserManager/WebKitChildTabRollback.swift
  Sumi/Managers/BrowserManager/WebKitChildWindowOpeningService.swift
  Sumi/Managers/BrowserManager/WebKitChildWindowShellTransaction.swift
  Sumi/Managers/BrowserManager/WebKitChildWindowCloseTransaction.swift
  Sumi/Managers/BrowserManager/BrowserLinkWindowTransaction.swift
  Sumi/Managers/BrowserManager/BrowserLinkPrivateWindowRollbackReceipt.swift
  Sumi/Managers/BrowserManager/BrowserExtensionRequestedWindowTransaction.swift
  Sumi/Managers/ExtensionManager/ExtensionInitialTabResidenceAdmission.swift
  Sumi/Managers/ExtensionManager/ExtensionInitialTabPublicationValidator.swift
  Sumi/Managers/ExtensionManager/ExtensionActionPresentationTarget.swift
)
child_window_transaction="Sumi/Managers/BrowserManager/WebKitChildWindowOpeningService.swift"
child_shell_transaction="Sumi/Managers/BrowserManager/WebKitChildWindowShellTransaction.swift"
retired_tab_state="Sumi/Models/Tab/TabWebViewInteractionStateOwner.swift"
retired_script_owner="Sumi/Models/Tab/TabScriptMessageRuntimeOwner.swift"
popup_responder="Sumi/Models/Tab/Navigation/SumiPopupHandlingNavigationResponder.swift"
link_glance_routing="Sumi/Models/Tab/Navigation/LinkGlanceRouting.swift"
child_surface_router="Sumi/Models/Tab/Navigation/WebKitChildSurfaceRouter.swift"
navigation_protocols="Sumi/Models/Tab/Navigation/SumiNavigationResponding.swift"
status=0




for required in \
  "$focusable_web_view" \
  "$interaction_state" \
  "$link_script" \
  "$context_menu_script" \
  "$link_presentation_commands" \
  "$link_presentation_factory" \
  "$physical_source_receipt" \
  "$physical_source_context" \
  "$host_services_runtime" \
  "$window_state" \
  "$tab_residence_authority" \
  "${manager_free_window_transactions[@]}" \
  "$child_window_transaction" \
  "$child_shell_transaction" \
  "$link_glance_routing" \
  "$child_surface_router"; do
  guard_require_file "$required"
done

guard_expect_no_matches \
  'physical source and host runtime manager reachback' \
  '\b(BrowserManager|TabManager|browserManager|tabManager)\b' \
  "$physical_source_receipt" \
  "$physical_source_context" \
  "$host_services_runtime"

guard_expect_no_matches \
  'window residence and WebKit transaction manager reachback' \
  '\b(TabManager|tabManager)\b' \
  "$window_state" \
  "$tab_residence_authority" \
  "${manager_free_window_transactions[@]}"

if [[ -e "$retired_residence_admission" ]]; then
  guard_record_failure "manager-fed exact residence admission reintroduced: $retired_residence_admission"
fi

if [[ -e "$retired_tab_state" ]]; then
  printf 'error: retired Tab interaction-state path reintroduced: %s\n' \
    "$retired_tab_state" >&2
  status=1
fi
if [[ -e "$retired_script_owner" ]]; then
  printf 'error: retired Tab script-message owner path reintroduced: %s\n' \
    "$retired_script_owner" >&2
  status=1
fi

# Physical page-interaction state belongs to each concrete FocusableWKWebView.
# These Tab-scoped slots and forwarding APIs allow two window clones to mutate
# one another and must remain deleted from production and tests.
retired_tab_api_hits="$(
  guard_capture_matches \
    '\b(TabWebViewInteractionStateOwner|TabScriptMessageRuntimeOwner|scriptMessageRuntimeOwner|webViewInteractionStateOwner|webViewInteractionCancellables|popupUserActivationTracker|setClickModifierFlags|clearWebViewInteractionEvent|recentWebViewInteractionModifierFlags|recentWebViewMouseDownModifierFlags|onLinkHover|lastHoveredLinkURL|lastWebPageContextMenuTarget)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$retired_tab_api_hits" ]]; then
  guard_record_failure "retired Tab-scoped WebView interaction API reintroduced:
$retired_tab_api_hits"
fi

retired_popup_route_hits="$(
  guard_capture_matches '\b(PendingGeneratedWindowRoutes|sumiLoadInNewWindow)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$retired_popup_route_hits" ]]; then
  guard_record_failure "uncorrelatable generated window.open route reintroduced:
$retired_popup_route_hits"
fi

ambiguous_navigation_protocol_hits="$(
  guard_capture_matches '\b(SumiNavigationActionWebViewResponding|SumiNavigationActionContextResponding)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$ambiguous_navigation_protocol_hits" ]]; then
  guard_record_failure "ambiguous navigation WebView role reintroduced:
$ambiguous_navigation_protocol_hits"
fi

registry_hits="$(
  guard_capture_matches '\bWebViewInteractionStateRegistry\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$registry_hits" ]]; then
  guard_record_failure "parallel WebView interaction registry reintroduced:
$registry_hits"
fi

# Do not hide a replacement interaction hub behind another generic Owner in
# the Tab model. Concrete gesture/link/context roles live beside WKWebView.
tab_interaction_owner_hits="$(
  guard_capture_matches '\b(class|struct|actor|enum)\s+[A-Za-z0-9_]*Interaction[A-Za-z0-9_]*Owner\b' \
    Sumi/Models/Tab -g '*.swift'
  find Sumi/Models/Tab -type f -print \
    | guard_capture_matches '/[^/]*Interaction[^/]*Owner\.swift$' -
)"
if [[ -n "$tab_interaction_owner_hits" ]]; then
  guard_record_failure "generic interaction Owner reintroduced in Tab model:
$tab_interaction_owner_hits"
fi

contract_count="$(guard_count_matches '^[[:space:]]*let[[:space:]]+gestures[[:space:]]*=[[:space:]]*WebViewGestureState\(\)' "$focusable_web_view")"
if (( contract_count == 0 )); then
  guard_record_failure "FocusableWKWebView must physically own its gesture state"
fi
contract_count="$(guard_count_matches '^[[:space:]]*let[[:space:]]+hoveredLink[[:space:]]*=[[:space:]]*WebViewHoveredLinkState\(\)' "$focusable_web_view")"
if (( contract_count == 0 )); then
  guard_record_failure "FocusableWKWebView must physically own its hovered-link state"
fi
contract_count="$(guard_count_matches '^[[:space:]]*let[[:space:]]+contextMenu[[:space:]]*=[[:space:]]*WebViewContextMenuState\(\)' "$focusable_web_view")"
if (( contract_count == 0 )); then
  guard_record_failure "FocusableWKWebView must physically own its context-menu state"
fi
contract_count="$(guard_count_matches '^[[:space:]]*let[[:space:]]+popupUserActivation[[:space:]]*=[[:space:]]*SumiPopupUserActivationTracker\(\)' "$focusable_web_view")"
if (( contract_count == 0 )); then
  guard_record_failure "FocusableWKWebView must physically own its popup user-activation state"
fi

contract_count="$(guard_count_matches '\bfinal[[:space:]]+class[[:space:]]+WebViewGestureState\b' "$interaction_state")"
if (( contract_count == 0 )); then
  guard_record_failure "physical WebView gesture state type is missing"
fi
contract_count="$(guard_count_matches '\bfinal[[:space:]]+class[[:space:]]+WebViewHoveredLinkState\b' "$interaction_state")"
if (( contract_count == 0 )); then
  guard_record_failure "physical WebView hovered-link state type is missing"
fi
contract_count="$(guard_count_matches '\bfinal[[:space:]]+class[[:space:]]+WebViewContextMenuState\b' "$interaction_state")"
if (( contract_count == 0 )); then
  guard_record_failure "physical WebView context-menu state type is missing"
fi

contract_count="$(guard_count_matches 'linkPresentationCommands\.open\(' "$popup_responder")"
if (( contract_count == 0 )); then
  guard_record_failure "browser-level link routing must use the exact physical presentation command"
fi
contract_count="$(guard_count_matches '\bSumiNavigationActionSourceAndTargetWebViewResponding\b' "$navigation_protocols")"
if (( contract_count == 0 )); then
  guard_record_failure "navigation responders must expose explicit source/target WebView roles"
fi

logical_tab_source_fallback_hits="$(
  guard_capture_matches 'sourceURL.*\?\?.*(tab|sourceTab)\.url|extensionOwnedSourceURL.*(tab|sourceTab)\.url' \
    "$popup_responder" Sumi/AuxiliaryWindows/AuxiliaryWindowUIDelegate.swift
)"
if [[ -n "$logical_tab_source_fallback_hits" ]]; then
  guard_record_failure "popup origin borrowed from logical Tab URL:
$logical_tab_source_fallback_hits"
fi

logical_tab_link_command_hits="$(
  guard_capture_matches '\b(TabBrowserActionService|browserActionService\.openLink|openURLInGlance)\b|var[[:space:]]+openLink:[[:space:]]*\(URL,[[:space:]]*Tab' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$logical_tab_link_command_hits" ]]; then
  guard_record_failure "link/Glance browser command routed from a logical Tab:
$logical_tab_link_command_hits"
fi

contract_count="$(guard_count_matches 'case[[:space:]]+newTab\(selected:[[:space:]]*Bool\)' "$link_presentation_commands")"
if (( contract_count == 0 )); then
  guard_record_failure "new-tab link disposition must preserve the selected flag"
fi
contract_count="$(guard_count_matches 'case[[:space:]]+newWindow\(selected:[[:space:]]*Bool\)' "$link_presentation_commands")"
if (( contract_count == 0 )); then
  guard_record_failure "new-window link disposition must preserve the selected flag"
fi
contract_count="$(guard_count_matches 'resolveSource\(sourceWebView\)' "$link_presentation_commands")"
if (( contract_count == 0 )); then
  guard_record_failure "link presentation commands must consume the exact physical source receipt"
fi
contract_count="$(guard_count_matches 'guard[[:space:]]+activateSource\(source\)' "$link_presentation_commands")"
if (( contract_count == 0 )); then
  guard_record_failure "Glance must activate the exact validated physical source receipt before presentation"
fi
contract_count="$(guard_count_matches 'sourceResolver\.resolve\(webView\)' "$link_presentation_factory")"
if (( contract_count == 0 )); then
  guard_record_failure "link presentation composition must use the shared physical source resolver"
fi
contract_count="$(guard_count_matches 'ownership\.webView\(' "$physical_source_receipt")"
if (( contract_count == 0 )); then
  guard_record_failure "physical source resolution must verify the exact tracked WebView slot"
fi
contract_count="$(guard_count_matches 'registry\.windows\[tracked\.windowID\]' "$physical_source_receipt")"
if (( contract_count == 0 )); then
  guard_record_failure "physical source resolution must bind the tracked physical window"
fi
contract_count="$(guard_count_matches 'let[[:space:]]+presentationProfile:[[:space:]]*Profile' "$physical_source_receipt")"
if (( contract_count == 0 )); then
  guard_record_failure "physical source receipts must preserve the presentation profile"
fi
contract_count="$(guard_count_matches 'let[[:space:]]+executionProfile:[[:space:]]*Profile' "$physical_source_receipt")"
if (( contract_count == 0 )); then
  guard_record_failure "physical source receipts must keep execution partition distinct from presentation"
fi
contract_count="$(guard_count_matches 'linkPresentationCommands\.presentInGlance\(' "$link_glance_routing")"
if (( contract_count == 0 )); then
  guard_record_failure "Glance routing must use the exact WebKit navigation-action source"
fi
contract_count="$(guard_count_matches 'from:[[:space:]]*sourceWebView' "$link_glance_routing")"
if (( contract_count == 0 )); then
  guard_record_failure "Glance routing must pass its exact physical source to presentation"
fi
contract_count="$(guard_count_matches 'childWindows\?\.open\(' "$child_surface_router")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child windows must return the exact WebKit-configured child"
fi
contract_count="$(guard_count_matches 'configuration:[[:space:]]*request\.configuration' "$child_surface_router")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child windows must preserve WebKit's exact child configuration"
fi
contract_count="$(guard_count_matches 'validateBeforeShell:' "$child_shell_transaction")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child Tab/WebView ownership must settle before shell publication"
fi
contract_count="$(guard_count_matches 'initialTabExecutionProfileID:' "$child_shell_transaction")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child shell transaction must publish the exact execution profile before registration"
fi
contract_count="$(guard_count_matches 'configuration\.websiteDataStore[[:space:]]*===[[:space:]]*source\.dataStore' "$child_window_transaction")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child windows must preserve the physical opener data-store partition"
fi
contract_count="$(guard_count_matches 'sourceResolver\.isCurrent\(source\)' "$child_window_transaction")"
if (( contract_count == 0 )); then
  guard_record_failure "WebKit child windows must revalidate their physical source receipt"
fi

child_shell_transaction_loc="$(guard_count_lines "$child_shell_transaction")"
if (( child_shell_transaction_loc > 150 )); then
  printf 'error: WebKit child shell transaction exceeded focused boundary (%s > 150)\n' \
    "$child_shell_transaction_loc" >&2
  status=1
fi

late_webkit_child_window_hits="$(
  guard_capture_matches '\.createWindowForLink\(' \
    Sumi/Managers/BrowserManager/TabBrowserRuntimeFactory.swift \
    "$popup_responder" \
    "$child_window_transaction"
)"
if [[ -n "$late_webkit_child_window_hits" ]]; then
  guard_record_failure "WebKit child window reconstructed through URL-only shell routing:
$late_webkit_child_window_hits"
fi

stale_hover_command_hits="$(
  guard_capture_matches '\b(routeDynamicGlanceIfNeeded|dynamicGlanceURL|shouldSwallowNextMouseUpAfterDynamicGlance)\b' \
    "$focusable_web_view"
)"
if [[ -n "$stale_hover_command_hits" ]]; then
  guard_record_failure "hover snapshots must not authorize browser commands:
$stale_hover_command_hits"
fi

uncorrelated_context_route_hits="$(
  guard_capture_matches '\b(NativeContextMenuRoute|consumeNativeContextMenuRequest|preparedContextTarget|openNativeContextItemInNewTab|downloadNativeContextResource)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
if [[ -n "$uncorrelated_context_route_hits" ]]; then
  guard_record_failure "uncorrelated context-menu routing reintroduced:
$uncorrelated_context_route_hits"
fi

link_message_count="$(guard_count_matches '\bmessage\.webView\b' "$link_script")"
link_cast_count="$(guard_count_matches 'as\?[[:space:]]+FocusableWKWebView' "$link_script")"
link_update_count="$(guard_count_matches '\.hoveredLink\.update\(' "$link_script")"
if (( link_message_count == 0 || link_cast_count == 0 || link_update_count == 0 )); then
  printf 'error: link script handler must update the exact message.webView hovered-link state\n' >&2
  status=1
fi

context_message_count="$(guard_count_matches '\bmessage\.webView\b' "$context_menu_script")"
context_cast_count="$(guard_count_matches 'as\?[[:space:]]+FocusableWKWebView' "$context_menu_script")"
context_record_count="$(guard_count_matches '\.contextMenu\.record\(' "$context_menu_script")"
if (( context_message_count == 0 || context_cast_count == 0 || context_record_count == 0 )); then
  printf 'error: context-menu script handler must update the exact message.webView context state\n' >&2
  status=1
fi

if (( status != 0 || guard_failures != 0 )); then
  echo "WebView interaction-state boundary audit failed" >&2
  exit 1
fi

echo "WebView interaction-state boundary audit passed"
