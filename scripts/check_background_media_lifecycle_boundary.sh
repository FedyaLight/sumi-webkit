#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

service="Sumi/Services/SumiBackgroundMediaOptimizationService.swift"
lifecycle="Sumi/Managers/BrowserManager/BrowserRuntimeLifecycle.swift"
browser_manager="Sumi/Managers/BrowserManager/BrowserManager.swift"
termination="Sumi/Managers/BrowserManager/BrowserTerminationRuntimeLease.swift"

for file in "$service" "$lifecycle" "$browser_manager" "$termination"; do
  guard_require_file "$file"
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

init_body="$(extract_scope "$service" 'init(notificationCenter:')"
if [[ -z "$init_body" ]]; then
  guard_record_failure "background-media lifecycle boundary: service initializer is missing"
  exit 1
fi
init_resource_count="$(
  guard_count_matches 'addObserver|Task[[:space:]]*\{|scheduleReconcile|pendingReasons|appliedCommandsByWebView' \
    - <<< "$init_body"
)"
if (( init_resource_count > 0 )); then
  guard_record_failure "background-media lifecycle boundary: init must remain resource-free"
  exit 1
fi

attach_body="$(extract_scope "$service" 'func attach(runtime:')"
for required in \
  'detach\(\)' \
  'self\.runtime = runtime' \
  'notificationCenter\.addObserver' \
  'attachmentGeneration'; do
  required_count="$(guard_count_matches "$required" - <<< "$attach_body")"
  if (( required_count == 0 )); then
    guard_record_failure "background-media lifecycle boundary: attach lost required activation step: $required"
    exit 1
  fi
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
  required_count="$(guard_count_matches "$required" - <<< "$detach_body")"
  if (( required_count == 0 )); then
    guard_record_failure "background-media lifecycle boundary: detach lost required retirement step: $required"
    exit 1
  fi
done

schedule_body="$(extract_scope "$service" 'func scheduleReconcile(reason: String)')"
schedule_guard_count="$(
  guard_count_matches 'guard runtime != nil else { return }' -F - <<< "$schedule_body"
)"
if (( schedule_guard_count == 0 )); then
  guard_record_failure "background-media lifecycle boundary: scheduleReconcile must be a no-op while detached"
  exit 1
fi

invalidate_body="$(extract_scope "$service" 'func invalidateAppliedCommand(for webView:')"
invalidate_guard_count="$(
  guard_count_matches 'guard runtime != nil else { return }' -F - <<< "$invalidate_body"
)"
if (( invalidate_guard_count == 0 )); then
  guard_record_failure "background-media lifecycle boundary: command invalidation must be a no-op while detached"
  exit 1
fi

shutdown_body="$(extract_scope "$lifecycle" 'func shutdown() {')"
shutdown_cancel_line="$(guard_capture_matches 'runtimeGraphSubscription?.cancel()' -F - <<< "$shutdown_body" | cut -d: -f1)"
shutdown_detach_line="$(guard_capture_matches 'backgroundMediaOptimization.detach()' -F - <<< "$shutdown_body" | cut -d: -f1)"
shutdown_tab_runtime_line="$(guard_capture_matches 'tabRuntimeLifecycle.shutdown()' -F - <<< "$shutdown_body" | cut -d: -f1)"
if [[ -z "$shutdown_cancel_line" || -z "$shutdown_detach_line" || -z "$shutdown_tab_runtime_line" ]]; then
  guard_record_failure "background-media lifecycle boundary: runtime shutdown must cancel inputs, detach background media, and shut down the tab runtime"
  exit 1
fi
if (( shutdown_cancel_line >= shutdown_detach_line )); then
  guard_record_failure "background-media lifecycle boundary: runtime shutdown must cancel structural input before detaching background media"
  exit 1
fi
if (( shutdown_detach_line >= shutdown_tab_runtime_line )); then
  guard_record_failure "background-media lifecycle boundary: runtime shutdown must detach background media before tab runtime teardown"
  exit 1
fi

manager_deinit="$(extract_scope "$browser_manager" 'isolated deinit')"
manager_shutdown_line="$(guard_capture_matches 'runtimeLifecycle.shutdown()' -F - <<< "$manager_deinit" | cut -d: -f1)"
manager_cleanup_line="$(guard_capture_matches 'shutdownCleanupService.cleanupAfterBrowserRuntimeDeallocation()' -F - <<< "$manager_deinit" | cut -d: -f1)"
if [[ -z "$manager_shutdown_line" || -z "$manager_cleanup_line" ]]; then
  guard_record_failure "background-media lifecycle boundary: BrowserManager deinit lost runtime shutdown or final cleanup"
  exit 1
fi
if (( manager_shutdown_line >= manager_cleanup_line )); then
  guard_record_failure "background-media lifecycle boundary: runtime shutdown must finish before final browser cleanup"
  exit 1
fi
manager_detach_reach="$(
  guard_capture_matches 'tabManager\.detachBrowserRuntime\(\)' \
    "$browser_manager"
)"
if [[ -n "$manager_detach_reach" ]]; then
  guard_record_failure "background-media lifecycle boundary: BrowserManager must not bypass BrowserRuntimeLifecycle for tab-runtime teardown"
  exit 1
fi

finalize_body="$(extract_scope "$termination" 'func finalizeTermination()')"
termination_detach_line="$(guard_capture_matches 'backgroundMediaOptimization.detach()' -F - <<< "$finalize_body" | cut -d: -f1)"
termination_flush_line="$(guard_capture_matches 'windowPersistence.flush()' -F - <<< "$finalize_body" | cut -d: -f1)"
if [[ -z "$termination_detach_line" || -z "$termination_flush_line" ]]; then
  guard_record_failure "background-media lifecycle boundary: termination finalization lost detach or persistence boundary"
  exit 1
fi
if (( termination_detach_line >= termination_flush_line )); then
  guard_record_failure "background-media lifecycle boundary: termination must detach background media before persistence and WebKit cleanup"
  exit 1
fi

browser_manager_count="$(guard_count_matches 'BrowserManager' "$service")"
if (( browser_manager_count > 0 )); then
  guard_record_failure "background-media lifecycle boundary: service must not recover BrowserManager through a hidden lookup"
  exit 1
fi

timer_count="$(guard_count_matches 'Timer|Task\.sleep|DispatchSourceTimer' "$service")"
if (( timer_count > 0 )); then
  guard_record_failure "background-media lifecycle boundary: service must not add timers or polling"
  exit 1
fi

echo "background-media lifecycle boundary passed"
