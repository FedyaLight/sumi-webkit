#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

service="Sumi/Services/SumiBackgroundMediaOptimizationService.swift"
lifecycle="Sumi/Managers/BrowserManager/BrowserRuntimeLifecycle.swift"
browser_manager="Sumi/Managers/BrowserManager/BrowserManager.swift"
termination="Sumi/Managers/BrowserManager/BrowserTerminationRuntimeLease.swift"

for file in "$service" "$lifecycle" "$browser_manager" "$termination"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: background-media lifecycle source missing: %s\n' "$file" >&2
    exit 1
  fi
done

extract_scope() {
  local file="$1"
  local marker="$2"
  awk -v marker="$marker" '
    index($0, marker) > 0 && started == 0 { started = 1 }
    started == 1 {
      print
      opens = gsub(/\{/, "{")
      closes = gsub(/\}/, "}")
      depth += opens - closes
      if (opens > 0) { saw_open = 1 }
      if (saw_open == 1 && depth == 0) { exit }
    }
  ' "$file"
}

fail() {
  printf 'error: background-media lifecycle boundary: %s\n' "$1" >&2
  exit 1
}

init_body="$(extract_scope "$service" 'init(notificationCenter:')"
[[ -n "$init_body" ]] || fail "service initializer is missing"
if rg -q 'addObserver|Task[[:space:]]*\{|scheduleReconcile|pendingReasons|appliedCommandsByWebView' <<<"$init_body"; then
  fail "init must remain resource-free"
fi

attach_body="$(extract_scope "$service" 'func attach(runtime:')"
for required in \
  'detach\(\)' \
  'self\.runtime = runtime' \
  'notificationCenter\.addObserver' \
  'attachmentGeneration'; do
  rg -q "$required" <<<"$attach_body" \
    || fail "attach lost required activation step: $required"
done

detach_body="$(extract_scope "$service" 'func detach()')"
for required in \
  'runtime = nil' \
  'notificationCenter\.removeObserver' \
  'scheduledReconcileTask\?\.cancel\(\)' \
  'scheduledReconcileTask = nil' \
  'pendingReasons\.removeAll\(\)' \
  'didTruncatePendingReasons = false' \
  'appliedCommandsByWebView\.removeAll\(\)' \
  'attachmentGeneration'; do
  rg -q "$required" <<<"$detach_body" \
    || fail "detach lost required retirement step: $required"
done

schedule_body="$(extract_scope "$service" 'func scheduleReconcile(reason: String)')"
rg -Fq 'guard runtime != nil else { return }' <<<"$schedule_body" \
  || fail "scheduleReconcile must be a no-op while detached"

invalidate_body="$(extract_scope "$service" 'func invalidateAppliedCommand(for webView:')"
rg -Fq 'guard runtime != nil else { return }' <<<"$invalidate_body" \
  || fail "command invalidation must be a no-op while detached"

shutdown_body="$(extract_scope "$lifecycle" 'func shutdown()')"
shutdown_cancel_line="$(rg -n -F 'runtimeGraphSubscription?.cancel()' <<<"$shutdown_body" | cut -d: -f1)"
shutdown_detach_line="$(rg -n -F 'backgroundMediaOptimization.detach()' <<<"$shutdown_body" | cut -d: -f1)"
[[ -n "$shutdown_cancel_line" && -n "$shutdown_detach_line" ]] \
  || fail "runtime shutdown must cancel inputs and detach background media"
(( shutdown_cancel_line < shutdown_detach_line )) \
  || fail "runtime shutdown must cancel structural input before detaching background media"

manager_deinit="$(extract_scope "$browser_manager" 'isolated deinit')"
manager_shutdown_line="$(rg -n -F 'runtimeLifecycle.shutdown()' <<<"$manager_deinit" | cut -d: -f1)"
manager_tab_detach_line="$(rg -n -F 'tabManager.detachBrowserRuntime()' <<<"$manager_deinit" | cut -d: -f1)"
[[ -n "$manager_shutdown_line" && -n "$manager_tab_detach_line" ]] \
  || fail "BrowserManager deinit lost runtime or tab detach"
(( manager_shutdown_line < manager_tab_detach_line )) \
  || fail "background media must detach before tab runtime teardown"

finalize_body="$(extract_scope "$termination" 'func finalizeTermination()')"
termination_detach_line="$(rg -n -F 'backgroundMediaOptimization.detach()' <<<"$finalize_body" | cut -d: -f1)"
termination_flush_line="$(rg -n -F 'windowPersistence.flush()' <<<"$finalize_body" | cut -d: -f1)"
[[ -n "$termination_detach_line" && -n "$termination_flush_line" ]] \
  || fail "termination finalization lost detach or persistence boundary"
(( termination_detach_line < termination_flush_line )) \
  || fail "termination must detach background media before persistence and WebKit cleanup"

if rg -q 'BrowserManager' "$service"; then
  fail "service must not recover BrowserManager through a hidden lookup"
fi

if rg -q 'Timer|Task\.sleep|DispatchSourceTimer' "$service"; then
  fail "service must not add timers or polling"
fi

echo "background-media lifecycle boundary passed"
