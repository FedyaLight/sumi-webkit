#!/usr/bin/env bash
# Deferred protected commands must not acknowledge an effect that disappeared
# with the runtime graph, and WebView identity resolution must stay concrete.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

dispatch='Sumi/Managers/WebViewRuntime/WebViewProtectedCommandDispatchOwner.swift'
execution='Sumi/Managers/WebViewRuntime/WebViewDeferredProtectedCommandExecutionOwner.swift'
graph='Sumi/Managers/WebViewRuntime/WebViewRuntimeGraph.swift'
resolver='Sumi/Managers/WebViewRuntime/WebViewRuntimeWebViewResolver.swift'
command='Packages/SumiWebRuntime/Sources/SumiWebRuntime/Commands/DeferredWebViewCommand.swift'
queue='Packages/SumiWebRuntime/Sources/SumiWebRuntime/Commands/WebViewProtectedCommandOwner.swift'

for file in "$dispatch" "$execution" "$graph" "$resolver" "$command" "$queue"; do
  [[ -f "$file" ]] || {
    printf 'error: protected-command boundary file missing: %s\n' "$file" >&2
    exit 1
  }
done

if ! rg -q 'enum DeferredProtectedCommandExecutionOutcome' "$command"; then
  printf 'error: deferred command execution lost typed outcome\n' >&2
  exit 1
fi
if rg -U -n 'executeCommand:[^\n]*\(DeferredWebViewCommand\)[[:space:]]*->[[:space:]]*Bool' \
  "$execution" "$queue"; then
  printf 'error: deferred command execution regressed to ambiguous Bool\n' >&2
  exit 1
fi

if rg -n '\bhasTabManager\b' "$dispatch" "$execution" "$graph"; then
  printf 'error: deferred-command validation regained fake TabManager liveness\n' >&2
  exit 1
fi

if rg -n 'let resolveWebView:[[:space:]]*@MainActor' "$dispatch"; then
  printf 'error: dispatch dependencies regained an ad-hoc WebView resolver\n' >&2
  exit 1
fi

required_patterns=(
  'let webViews: WebViewRuntimeWebViewResolver'
  'let isRuntimeAvailable: @MainActor () -> Bool'
  'let removeWebViewFromContainers: @MainActor (WKWebView) -> Bool'
  'let cleanupTrackedWebView: @MainActor (WKWebView, TrackedWebViewOwner) -> Bool'
  'let cleanupWindow: @MainActor (UUID) -> Bool'
  'let cleanupAllWebViews: @MainActor () -> Bool'
  'let evictHiddenWebViews: @MainActor (UUID, Set<UUID>) -> Bool'
  'let performFallbackWebViewCleanup: @MainActor (WKWebView, UUID) -> Bool'
)
for pattern in "${required_patterns[@]}"; do
  rg -Fq "$pattern" "$dispatch" || {
    printf 'error: protected command effect lost fail-closed contract: %s\n' \
      "$pattern" >&2
    exit 1
  }
done

guarded_live_effects="$(
  rg -U -c ':[[:space:]]*\{ \[weak graph\][^}]{0,120}guard let graph else \{ return false \}' \
    "$graph" || true
)"
if (( ${guarded_live_effects:-0} < 6 )); then
  printf 'error: protected command live effects are not fail-closed (%s < 6)\n' \
    "${guarded_live_effects:-0}" >&2
  exit 1
fi

echo 'protected command dispatch boundary passed'
