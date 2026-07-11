#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

production_roots=(App Sumi Settings SidebarChrome FloatingBar UI)
all_swift_roots=("${production_roots[@]}" SumiTests SumiUITests)
focusable_web_view="Sumi/Utils/WebKit/FocusableWKWebView.swift"
interaction_state="Sumi/Utils/WebKit/WebViewInteractionState.swift"
link_script="Sumi/UserScripts/SumiLinkInteractionUserScript.swift"
context_menu_script="Sumi/UserScripts/SumiWebPageContextMenuUserScript.swift"
link_presentation_commands="Sumi/Models/Tab/TabLinkPresentationCommands.swift"
link_presentation_factory="Sumi/Managers/BrowserManager/TabLinkPresentationCommandsFactory.swift"
physical_source_receipt="Sumi/Managers/BrowserManager/PhysicalWebViewSourceReceipt.swift"
child_window_transaction="Sumi/Managers/BrowserManager/WebKitChildWindowOpeningService.swift"
child_shell_transaction="Sumi/Managers/BrowserManager/WebKitChildWindowShellTransaction.swift"
retired_tab_state="Sumi/Models/Tab/TabWebViewInteractionStateOwner.swift"
retired_script_owner="Sumi/Models/Tab/TabScriptMessageRuntimeOwner.swift"
popup_responder="Sumi/Models/Tab/Navigation/SumiPopupHandlingNavigationResponder.swift"
link_glance_routing="Sumi/Models/Tab/Navigation/LinkGlanceRouting.swift"
child_surface_router="Sumi/Models/Tab/Navigation/WebKitChildSurfaceRouter.swift"
navigation_protocols="Sumi/Models/Tab/Navigation/SumiNavigationResponding.swift"
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
    printf 'error: required physical WebView interaction source missing: %s\n' \
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
    printf 'error: required physical WebView regression missing: %s\n' \
      "$test_name" >&2
    status=1
  fi
}

for required in \
  "$focusable_web_view" \
  "$interaction_state" \
  "$link_script" \
  "$context_menu_script" \
  "$link_presentation_commands" \
  "$link_presentation_factory" \
  "$physical_source_receipt" \
  "$child_window_transaction" \
  "$child_shell_transaction" \
  "$link_glance_routing" \
  "$child_surface_router"; do
  require_file "$required"
done

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
  rg -n \
    '\b(TabWebViewInteractionStateOwner|TabScriptMessageRuntimeOwner|scriptMessageRuntimeOwner|webViewInteractionStateOwner|webViewInteractionCancellables|popupUserActivationTracker|setClickModifierFlags|clearWebViewInteractionEvent|recentWebViewInteractionModifierFlags|recentWebViewMouseDownModifierFlags|onLinkHover|lastHoveredLinkURL|lastWebPageContextMenuTarget)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "retired Tab-scoped WebView interaction API reintroduced" \
  "$retired_tab_api_hits"

retired_popup_route_hits="$(
  rg -n '\b(PendingGeneratedWindowRoutes|sumiLoadInNewWindow)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "uncorrelatable generated window.open route reintroduced" \
  "$retired_popup_route_hits"

ambiguous_navigation_protocol_hits="$(
  rg -n '\b(SumiNavigationActionWebViewResponding|SumiNavigationActionContextResponding)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "ambiguous navigation WebView role reintroduced" \
  "$ambiguous_navigation_protocol_hits"

registry_hits="$(
  rg -n '\bWebViewInteractionStateRegistry\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "parallel WebView interaction registry reintroduced" "$registry_hits"

# Do not hide a replacement interaction hub behind another generic Owner in
# the Tab model. Concrete gesture/link/context roles live beside WKWebView.
tab_interaction_owner_hits="$(
  rg -n '\b(class|struct|actor|enum)\s+[A-Za-z0-9_]*Interaction[A-Za-z0-9_]*Owner\b' \
    Sumi/Models/Tab -g '*.swift' || true
  rg --files Sumi/Models/Tab \
    | rg '/[^/]*Interaction[^/]*Owner\.swift$' || true
)"
fail_matches "generic interaction Owner reintroduced in Tab model" \
  "$tab_interaction_owner_hits"

require_pattern \
  "$focusable_web_view" \
  '^[[:space:]]*let[[:space:]]+gestures[[:space:]]*=[[:space:]]*WebViewGestureState\(\)' \
  "FocusableWKWebView must physically own its gesture state"
require_pattern \
  "$focusable_web_view" \
  '^[[:space:]]*let[[:space:]]+hoveredLink[[:space:]]*=[[:space:]]*WebViewHoveredLinkState\(\)' \
  "FocusableWKWebView must physically own its hovered-link state"
require_pattern \
  "$focusable_web_view" \
  '^[[:space:]]*let[[:space:]]+contextMenu[[:space:]]*=[[:space:]]*WebViewContextMenuState\(\)' \
  "FocusableWKWebView must physically own its context-menu state"
require_pattern \
  "$focusable_web_view" \
  '^[[:space:]]*let[[:space:]]+popupUserActivation[[:space:]]*=[[:space:]]*SumiPopupUserActivationTracker\(\)' \
  "FocusableWKWebView must physically own its popup user-activation state"

require_pattern \
  "$interaction_state" \
  '\bfinal[[:space:]]+class[[:space:]]+WebViewGestureState\b' \
  "physical WebView gesture state type is missing"
require_pattern \
  "$interaction_state" \
  '\bfinal[[:space:]]+class[[:space:]]+WebViewHoveredLinkState\b' \
  "physical WebView hovered-link state type is missing"
require_pattern \
  "$interaction_state" \
  '\bfinal[[:space:]]+class[[:space:]]+WebViewContextMenuState\b' \
  "physical WebView context-menu state type is missing"

require_pattern \
  "$popup_responder" \
  'linkPresentationCommands\.open\(' \
  "browser-level link routing must use the exact physical presentation command"
require_pattern \
  "$navigation_protocols" \
  '\bSumiNavigationActionSourceAndTargetWebViewResponding\b' \
  "navigation responders must expose explicit source/target WebView roles"

logical_tab_source_fallback_hits="$(
  rg -n 'sourceURL.*\?\?.*(tab|sourceTab)\.url|extensionOwnedSourceURL.*(tab|sourceTab)\.url' \
    "$popup_responder" Sumi/AuxiliaryWindows/AuxiliaryWindowUIDelegate.swift || true
)"
fail_matches "popup origin borrowed from logical Tab URL" \
  "$logical_tab_source_fallback_hits"

logical_tab_link_command_hits="$(
  rg -n '\b(TabBrowserActionService|browserActionService\.openLink|openURLInGlance)\b|var[[:space:]]+openLink:[[:space:]]*\(URL,[[:space:]]*Tab' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "link/Glance browser command routed from a logical Tab" \
  "$logical_tab_link_command_hits"

require_pattern \
  "$link_presentation_commands" \
  'case[[:space:]]+newTab\(selected:[[:space:]]*Bool\)' \
  "new-tab link disposition must preserve the selected flag"
require_pattern \
  "$link_presentation_commands" \
  'case[[:space:]]+newWindow\(selected:[[:space:]]*Bool\)' \
  "new-window link disposition must preserve the selected flag"
require_pattern \
  "$link_presentation_commands" \
  'resolveSource\(sourceWebView\)' \
  "link presentation commands must consume the exact physical source receipt"
require_pattern \
  "$link_presentation_commands" \
  'guard[[:space:]]+activateSource\(source\)' \
  "Glance must activate the exact validated physical source receipt before presentation"
require_pattern \
  "$link_presentation_factory" \
  'sourceResolver\.resolve\(webView\)' \
  "link presentation composition must use the shared physical source resolver"
require_pattern \
  "$physical_source_receipt" \
  'ownership\.webView\(' \
  "physical source resolution must verify the exact tracked WebView slot"
require_pattern \
  "$physical_source_receipt" \
  'registry\.windows\[tracked\.windowID\]' \
  "physical source resolution must bind the tracked physical window"
require_pattern \
  "$physical_source_receipt" \
  'let[[:space:]]+presentationProfile:[[:space:]]*Profile' \
  "physical source receipts must preserve the presentation profile"
require_pattern \
  "$physical_source_receipt" \
  'let[[:space:]]+executionProfile:[[:space:]]*Profile' \
  "physical source receipts must keep execution partition distinct from presentation"
require_pattern \
  "$link_glance_routing" \
  'linkPresentationCommands\.presentInGlance\(' \
  "Glance routing must use the exact WebKit navigation-action source"
require_pattern \
  "$link_glance_routing" \
  'from:[[:space:]]*sourceWebView' \
  "Glance routing must pass its exact physical source to presentation"
require_pattern \
  "$child_surface_router" \
  'childWindows\?\.open\(' \
  "WebKit child windows must return the exact WebKit-configured child"
require_pattern \
  "$child_surface_router" \
  'configuration:[[:space:]]*request\.configuration' \
  "WebKit child windows must preserve WebKit's exact child configuration"
require_pattern \
  "$child_shell_transaction" \
  'validateBeforeShell:' \
  "WebKit child Tab/WebView ownership must settle before shell publication"
require_pattern \
  "$child_shell_transaction" \
  'initialTabExecutionProfileID:' \
  "WebKit child shell transaction must publish the exact execution profile before registration"
require_pattern \
  "$child_window_transaction" \
  'configuration\.websiteDataStore[[:space:]]*===[[:space:]]*source\.dataStore' \
  "WebKit child windows must preserve the physical opener data-store partition"
require_pattern \
  "$child_window_transaction" \
  'sourceResolver\.isCurrent\(source\)' \
  "WebKit child windows must revalidate their physical source receipt"

child_shell_transaction_loc="$(wc -l < "$child_shell_transaction" | tr -d ' ')"
if (( child_shell_transaction_loc > 150 )); then
  printf 'error: WebKit child shell transaction exceeded focused boundary (%s > 150)\n' \
    "$child_shell_transaction_loc" >&2
  status=1
fi

late_webkit_child_window_hits="$(
  rg -n '\.createWindowForLink\(' \
    Sumi/Managers/BrowserManager/TabBrowserRuntimeFactory.swift \
    "$popup_responder" \
    "$child_window_transaction" || true
)"
fail_matches "WebKit child window reconstructed through URL-only shell routing" \
  "$late_webkit_child_window_hits"

stale_hover_command_hits="$(
  rg -n '\b(routeDynamicGlanceIfNeeded|dynamicGlanceURL|shouldSwallowNextMouseUpAfterDynamicGlance)\b' \
    "$focusable_web_view" || true
)"
fail_matches "hover snapshots must not authorize browser commands" \
  "$stale_hover_command_hits"

uncorrelated_context_route_hits="$(
  rg -n '\b(NativeContextMenuRoute|consumeNativeContextMenuRequest|preparedContextTarget|openNativeContextItemInNewTab|downloadNativeContextResource)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "uncorrelated context-menu routing reintroduced" \
  "$uncorrelated_context_route_hits"

if [[ ! -f "$link_script" ]] \
    || ! rg -q '\bmessage\.webView\b' "$link_script" \
    || ! rg -q 'as\?[[:space:]]+FocusableWKWebView' "$link_script" \
    || ! rg -q '\.hoveredLink\.update\(' "$link_script"; then
  printf 'error: link script handler must update the exact message.webView hovered-link state\n' >&2
  status=1
fi

if [[ -f "$context_menu_script" ]]; then
  if ! rg -q '\bmessage\.webView\b' "$context_menu_script" \
      || ! rg -q 'as\?[[:space:]]+FocusableWKWebView' "$context_menu_script" \
      || ! rg -q '\.contextMenu\.record\(' "$context_menu_script"; then
    printf 'error: context-menu script handler must update the exact message.webView context state\n' >&2
    status=1
  fi
fi

for required_test in \
  testPopupUserActivationCannotCrossCloneBoundary \
  testConsumingPopupActivationEvaluationAfterNewRecordPreservesNewActivation \
  testPopupActivationClaimCannotBeSpentTwiceByConcurrentRequests \
  testStaleGestureClearReceiptPreservesNewerGesture \
  testPopupOriginDoesNotBorrowLogicalTabURLWhenSourceFrameIsMissing \
  testFilePickerActivationCannotCrossFocusableWebViewCloneBoundary \
  testLinkHoverMessagesRemainScopedToPhysicalWebViewClones \
  testSameTabPhysicalHoverSessionsRemainIndependentWhenOneWindowTearsDown \
  testSplitHoverInactiveSourceNilDoesNotEraseActiveSource \
  testContextMenuSnapshotsRemainScopedToPhysicalWebViewClones \
  testGlanceTriggerUsesExactSourceWebViewGestureInsteadOfAnotherViewState \
  testReaderDOMHoverPublishesThroughMinimalPhysicalWebViewScriptAndStopsAfterDismissal \
  testExternalSchemeUsesSourcePermissionContextAndClosesCrossWebViewTarget \
  testDownloadResponderReadsModifiersFromCrossWebViewSource \
  testNewWindowLinkCopiesSourceProfileAndSpaceBeforeOpeningTab \
  testIncognitoNewWindowLinkCreatesOnlyEphemeralTargetState \
  testChildSurfaceRouterReturnsExactWindowChildAndWebKitConfiguration \
  testWebKitChildWindowPublishesExactTrackedChildBeforeRegistration \
  testWebKitChildWindowRejectsMismatchedDataStoreWithoutMutation \
  testPrivateWebKitChildWindowSharesPartitionUntilLastWindowCloses; do
  require_test "$required_test"
done

for required_test in \
  testResolverRejectsMismatchedExecutionDataStore \
  testWindowLocalShortcutLeaseRejectsWrongWindowClone \
  testEssentialAndSpacePinnedRoutesPreserveExecutionPartition; do
  require_test "$required_test"
done

for required_test in \
  testSameTabTwoWindowLinkCommandsUseExactPhysicalSourceWindow \
  testSameTabTwoWindowGlanceUsesExactPhysicalSourceWindow \
  testUntrackedOrMismatchedPhysicalSourceFailsClosed \
  testRejectedExactWindowActivationDoesNotPresentGlance \
  testExactWindowPresentationMovesSameURLBetweenPhysicalTabPresentations \
  testExactWindowPresentationReanchorsSameURLToNewSourceTab \
  testExactWindowPresentationReanchorsSameURLWhenOriginChanges; do
  require_test "$required_test"
done

if [[ "$status" -ne 0 ]]; then
  echo "WebView interaction-state boundary audit failed" >&2
  exit "$status"
fi

echo "WebView interaction-state boundary audit passed"
