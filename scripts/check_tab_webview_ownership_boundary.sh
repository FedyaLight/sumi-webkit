#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# External production code must not treat Tab as the live WKWebView source of truth.
# Live lookup/assignment goes through WebViewCoordinator / BrowserWebViewRoutingService.
# Untracked create goes through ensureUntrackedNormalWebView / coordinator ensureUntrackedOwnedWebView.
#
# Phase 6B progress (session-first writers):
# - TabWebViewSessionStore is authoritative for parked / untracked / primary-assignment notes
#   when a browser runtime is attached (Tab mutators call note* FIRST, then mirror Tab fields).
# - Teardown, rebuild, ownsLive, creation adopt, cleanup validation, and reload URL prefer session.
# - Tab.assignedWebView / existingWebView / parkedWebView remain a dual-write compatibility mirror
#   for Tab-internal readers and pre-runtime tabs; do not remove fields until those readers migrate.
# - Goal: forbid Tab WebView accessors outside Tab + WebViewCoordinator (this script),
#   then remove Tab fields once session is sole SoT for parked/untracked.
#
# Phase 9 sole-writer model (evolving under 6B):
# - Windowed webView + primaryWindowId = dual-write cache (registry is SoT; session notes primary)
# - Untracked webView = session note first, Tab mirror second
# - Parked existingWebView = session note first, Tab mirror second
scan_roots=(App Sumi Navigation FloatingBar Settings UI)
allow_prefixes=(
  "Sumi/Models/Tab/"
  "Sumi/Managers/WebViewCoordinator/"
)

matches="$(
  grep -rEn --include='*.swift' \
    -e '\.currentWebView\b' \
    -e '\.existingWebView\b' \
    -e '\.assignedWebView\b' \
    -e '\.parkedWebView\b' \
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

status=0
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
    printf 'disallowed Tab WKWebView ownership API outside coordinator/Tab internals: %s\n' "$match" >&2
    status=1
  fi
done <<< "$matches"

if [[ "$status" -ne 0 ]]; then
  echo "Tab WebView ownership boundary audit failed" >&2
  echo "Use BrowserWebViewRoutingService / WebViewCoordinator for live WebView lookup and assignment." >&2
  exit "$status"
fi

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

# Phase 5: clear ownership only from Tab internals + WebViewCoordinator.
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
    printf 'disallowed Tab clear* ownership outside coordinator/Tab internals: %s\n' "$match" >&2
    status=1
  fi
done <<< "$clear_matches"

# Phase 6: replaceUntrackedWebView only from Tab + WebViewCoordinator.
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
    printf 'disallowed replaceUntrackedWebView outside coordinator/Tab internals: %s\n' "$match" >&2
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

# Phase 8: external code must not read Tab.primaryWindowId; use registry/routing.
primary_window_matches="$(
  grep -rEn --include='*.swift' \
    -e '\.primaryWindowId\b' \
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
    printf 'disallowed Tab.primaryWindowId outside Tab/WebViewCoordinator (use primaryTrackedWindowId): %s\n' "$match" >&2
    status=1
  fi
done <<< "$primary_window_matches"

if [[ "$status" -ne 0 ]]; then
  echo "Tab WebView ownership boundary audit failed" >&2
  echo "Pre-window create must use ensureUntrackedNormalWebView; clear/release/install/replace ownership via WebViewCoordinator; primary window via registry." >&2
  exit "$status"
fi

echo "Tab WebView ownership boundary audit passed"
