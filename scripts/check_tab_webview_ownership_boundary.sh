#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# External production code must not treat Tab as the live WKWebView source of truth.
# Live lookup/assignment goes through WebViewCoordinator / BrowserWebViewRoutingService.
# Untracked create goes through ensureUntrackedNormalWebView / coordinator ensureUntrackedOwnedWebView.
#
# T2 (accessor removal):
# - Tab no longer exposes public currentWebView / assignedWebView / parkedWebView /
#   existingWebView / primaryWindowId getters.
# - Tab-internal owners use resolved* helpers or injected @MainActor () -> WKWebView? closures.
# - TabWebViewOwnershipOwner holds only a pre-runtime local TabWebViewSession (no façade vars).
# - Coordinator must not fall back to Tab accessors; promoteLocalSessionIfNeeded bridges pre-attach.
#
# Allowlist: Tab internals + WebViewCoordinator (+ BrowserWebViewRoutingService for façade).
scan_roots=(App Sumi Navigation FloatingBar Settings UI)
allow_prefixes=(
  "Sumi/Models/Tab/"
  "Sumi/Managers/WebViewCoordinator/"
  "Sumi/Services/BrowserWebViewRoutingService.swift"
  "Packages/SumiWebRuntime/Sources/"
)

status=0

# T2: forbid deleted Tab public WebView accessors / primaryWindowId property usages.
# Resolve helpers (resolvedCurrentWebView / resolvedPrimaryWindowId) and session APIs remain.
deleted_accessor_matches="$(
  grep -rEn --include='*.swift' \
    -e '\.currentWebView\b' \
    -e '\.existingWebView\b' \
    -e '\.assignedWebView\b' \
    -e '\.parkedWebView\b' \
    -e '\.primaryWindowId\b' \
    "${scan_roots[@]}" || [[ $? -eq 1 ]]
)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  relative_path="${match%%:*}"
  line_body="${match#*:}"
  line_body="${line_body#*:}"

  # Session / localSession / context closures / store APIs may still use these names.
  if [[ "$line_body" =~ (localSession|session|store|context|environment|owner)\.(current|existing|assigned|parked)WebView ]]; then
    continue
  fi
  if [[ "$line_body" =~ (localSession|session|store)\.primaryWindowId ]]; then
    continue
  fi
  if [[ "$line_body" =~ (sessionPrimaryWindowId|primaryTrackedWindowId|primaryWindowIdForClone|notePrimaryAssignment|clearPrimaryAssignment) ]]; then
    continue
  fi
  if [[ "$line_body" =~ (resolvedCurrentWebView|resolvedParkedWebView|resolvedAssignedWebView|resolvedPrimaryWindowId|currentWebViewIsIdentical|hasCurrentWebView|hasParkedWebView|currentWebViewIdentity) ]]; then
    continue
  fi
  # Struct/property definitions and comments inside allowlisted ownership files.
  allowed=0
  for prefix in "${allow_prefixes[@]}"; do
    if [[ "$relative_path" == "$prefix"* ]]; then
      # Inside Tab/Coordinator/routing: still forbid Tab public accessor *reads*
      # of the deleted API shape `tab.currentWebView` / `tab.primaryWindowId`.
      if [[ "$line_body" =~ tab\.(current|existing|assigned|parked)WebView([^I]|$) ]] \
        || [[ "$line_body" =~ tab\.primaryWindowId ]]; then
        printf 'disallowed Tab WebView accessor (deleted in T2): %s\n' "$match" >&2
        status=1
      fi
      allowed=1
      break
    fi
  done
  if [[ "$allowed" -eq 0 ]]; then
    # Outside allowlist: any .currentWebView / .primaryWindowId style hit is forbidden
    # unless it is clearly a non-Tab identifier (already filtered above loosely).
    printf 'disallowed Tab WKWebView ownership API outside coordinator/Tab/routing: %s\n' "$match" >&2
    status=1
  fi
done <<< "$deleted_accessor_matches"

# Mutator / ensure APIs remain allowlisted to Tab + coordinator + routing.
mutator_matches="$(
  grep -rEn --include='*.swift' \
    -e '\.ensureWebView\(' \
    -e '\.assignWebViewToWindow\(' \
    -e '\.replaceUntrackedWebView\(' \
    -e '\.parkExistingWebView\(' \
    -e '\.adoptParkedWebViewAsCurrent\(' \
    -e '\.assignPrimaryWebView\(' \
    -e '\.clearCurrentWebViewOwnershipIfIdentical\(' \
    -e '\.clearParkedExistingWebView\(' \
    -e '\.setPrimaryWindowId\(' \
    -e '\.setCurrentWebView\(' \
    -e '\.setExistingWebView\(' \
    "${scan_roots[@]}" || [[ $? -eq 1 ]]
)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  relative_path="${match%%:*}"
  allowed=0
  for prefix in "${allow_prefixes[@]}"; do
    if [[ "$relative_path" == "$prefix"* ]]; then
      allowed=1
      break
    fi
  done
  if [[ "$allowed" -eq 0 ]]; then
    printf 'disallowed Tab WKWebView ownership API outside coordinator/Tab/routing: %s\n' "$match" >&2
    status=1
  fi
done <<< "$mutator_matches"

if [[ "$status" -ne 0 ]]; then
  echo "Tab WebView ownership boundary audit failed" >&2
  echo "Use BrowserWebViewRoutingService / WebViewCoordinator for live WebView lookup and assignment." >&2
  echo "Tab public WebView getters were removed in T2; use routing/session or resolved* helpers." >&2
  exit "$status"
fi

# N6: forbid Tab mirror storage fields (_webView / _existingWebView as stored properties).
# Accessors may remain as session-delegating computed properties on Tab.
storage_matches="$(
  grep -rEn --include='*.swift' \
    -e 'private\(set\)\s+var\s+webView:\s*WKWebView\?' \
    -e 'private\(set\)\s+var\s+existingWebView:\s*WKWebView\?' \
    -e 'var\s+_webView:\s*WKWebView\?\s*\{' \
    -e 'var\s+_existingWebView:\s*WKWebView\?\s*\{' \
    -e 'var\s+webView:\s*WKWebView\?\s*\{' \
    -e 'var\s+assignedWebView:\s*WKWebView\?\s*\{' \
    -e 'var\s+existingWebView:\s*WKWebView\?\s*\{' \
    -e 'var\s+parkedWebView:\s*WKWebView\?\s*\{' \
    -e 'var\s+currentWebView:\s*WKWebView\?\s*\{' \
    "Sumi/Models/Tab/" || [[ $? -eq 1 ]]
)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  relative_path="${match%%:*}"
  # Façade getters on Tab / OwnershipOwner are forbidden after T2.
  # Context structs may still declare closure properties named currentWebView / parkedWebView.
  if [[ "$relative_path" == "Sumi/Models/Tab/Tab+WebViewRuntime.swift" ]] \
    || [[ "$relative_path" == "Sumi/Models/Tab/Tab.swift" ]] \
    || [[ "$relative_path" == "Sumi/Models/Tab/TabWebViewOwnershipOwner.swift" ]]; then
    printf 'disallowed Tab WebView accessor/façade in %s: %s\n' "$relative_path" "$match" >&2
    status=1
    continue
  fi
done <<< "$storage_matches"

# Forbid syncFromTabIfNeeded (replaced by promoteLocalSessionIfNeeded).
sync_matches="$(
  grep -rEn --include='*.swift' \
    -e 'syncFromTabIfNeeded' \
    "${scan_roots[@]}" SumiTests || [[ $? -eq 1 ]]
)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  printf 'disallowed syncFromTabIfNeeded (use promoteLocalSessionIfNeeded / session notes): %s\n' "$match" >&2
  status=1
done <<< "$sync_matches"

# Phase 4: dead ensureWebView API must not reappear in production.
production_ensure_matches="$(
  grep -rEn --include='*.swift' \
    -e '\.ensureWebView\(' \
    -e 'func ensureWebView\(' \
    "${scan_roots[@]}" || [[ $? -eq 1 ]]
)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  printf 'disallowed Tab.ensureWebView in production (use ensureUntrackedNormalWebView): %s\n' "$match" >&2
  status=1
done <<< "$production_ensure_matches"

# Phase 4: setupWebView is only the thin Tab wrapper; create SoT is ensureUntrackedNormalWebView.
setup_call_matches="$(
  grep -rEn --include='*.swift' \
    -e '\.setupWebView\(' \
    "${scan_roots[@]}" || [[ $? -eq 1 ]]
)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  relative_path="${match%%:*}"
  # Thin wrapper definition may reference the historical name only as the function itself.
  if [[ "$relative_path" == "Sumi/Models/Tab/Tab+WebViewRuntime.swift" ]]; then
    continue
  fi
  printf 'disallowed Tab.setupWebView call site (use ensureUntrackedNormalWebView): %s\n' "$match" >&2
  status=1
done <<< "$setup_call_matches"

# Phase 5: clear ownership only from Tab internals + WebViewCoordinator + routing.
clear_matches="$(
  grep -rEn --include='*.swift' \
    -e '\.clearCurrentWebViewOwnership\(' \
    -e '\.clearAllWebViewOwnership\(' \
    "${scan_roots[@]}" || [[ $? -eq 1 ]]
)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  relative_path="${match%%:*}"
  allowed=0
  for prefix in "${allow_prefixes[@]}"; do
    if [[ "$relative_path" == "$prefix"* ]]; then
      allowed=1
      break
    fi
  done
  if [[ "$allowed" -eq 0 ]]; then
    printf 'disallowed Tab clear* ownership outside coordinator/Tab/routing: %s\n' "$match" >&2
    status=1
  fi
done <<< "$clear_matches"

# Phase 6: replaceUntrackedWebView only from Tab + WebViewCoordinator + routing.
replace_matches="$(
  grep -rEn --include='*.swift' \
    -e '\.replaceUntrackedWebView\(' \
    "${scan_roots[@]}" || [[ $? -eq 1 ]]
)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  relative_path="${match%%:*}"
  allowed=0
  for prefix in "${allow_prefixes[@]}"; do
    if [[ "$relative_path" == "$prefix"* ]]; then
      allowed=1
      break
    fi
  done
  if [[ "$allowed" -eq 0 ]]; then
    printf 'disallowed replaceUntrackedWebView outside coordinator/Tab/routing: %s\n' "$match" >&2
    status=1
  fi
done <<< "$replace_matches"

# Phase 7: makeNormalTabWebView only from Tab + WebViewCoordinator.
make_matches="$(
  grep -rEn --include='*.swift' \
    -e '\.makeNormalTabWebView\(' \
    "${scan_roots[@]}" || [[ $? -eq 1 ]]
)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  relative_path="${match%%:*}"
  allowed=0
  for prefix in "${allow_prefixes[@]}"; do
    if [[ "$relative_path" == "$prefix"* ]]; then
      allowed=1
      break
    fi
  done
  if [[ "$allowed" -eq 0 ]]; then
    printf 'disallowed makeNormalTabWebView outside Tab/WebViewCoordinator: %s\n' "$match" >&2
    status=1
  fi
done <<< "$make_matches"

if [[ "$status" -ne 0 ]]; then
  echo "Tab WebView ownership boundary audit failed" >&2
  echo "Pre-window create must use ensureUntrackedNormalWebView; clear/release/install/replace ownership via WebViewCoordinator; primary window via registry/session." >&2
  echo "Tab public WebView getters were removed; use routing/session or Tab.resolved* helpers internally." >&2
  exit "$status"
fi

echo "Tab WebView ownership boundary audit passed"
