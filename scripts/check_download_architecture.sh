#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

download_root="Sumi/Managers/DownloadManager"
guard_require_directory "$download_root"

count_nonempty_lines() {
  awk 'NF { count += 1 } END { print count + 0 }' <<< "$1"
}

printf '%s\n' 'Download architecture boundary audit'
printf '%s\n' '------------------------------------'

orchestration_sources="$(
  guard_capture_files \
    'final class (DownloadManager|DownloadListCoordinator|DownloadTransaction)\b' \
    "$download_root" -g '*.swift' \
    | sort
)"
guard_exact \
  'semantic download orchestration roles' \
  "$(count_nonempty_lines "$orchestration_sources")" \
  3

while IFS= read -r source; do
  [[ -n "$source" ]] || continue
  forbidden_hits="$(
    guard_capture_matches \
      'import WebKit|\b(WKDownload|WKWebView|WKDownloadDelegate|FileManager|NSWorkspace|NSSavePanel|DownloadFileUtilities)\b' \
      "$source"
  )"
  if [[ -n "$forbidden_hits" ]]; then
    printf '%s\n' "$forbidden_hits" >&2
    guard_record_failure \
      "download orchestration directly owns WebKit, filesystem, or workspace behavior: $source"
  fi
done <<< "$orchestration_sources"

required_ports=(
  DownloadTransport
  DownloadDestinationAllocating
  DownloadFileFinalizing
  DownloadWorkspaceOpening
  DownloadOrphanCleaning
  DownloadProgressPublishing
)
for port in "${required_ports[@]}"; do
  guard_exact \
    "$port declarations" \
    "$(guard_count_swift_matches "protocol ${port}\\b" "$download_root")" \
    1
done

webKit_sources="$(
  guard_capture_files \
    'import WebKit|\b(WKDownload|WKDownloadDelegate)\b' \
    "$download_root" -g '*.swift' \
    | sort
)"
while IFS= read -r source; do
  [[ -n "$source" ]] || continue
  adapter_role_count="$(
    guard_count_matches \
      'DownloadWebKitTransportAdapting|DownloadTransport, WKDownloadDelegate|DownloadRetryTransportStarting' \
      "$source"
  )"
  if (( adapter_role_count == 0 )); then
    guard_record_failure \
      "WebKit download code exists outside a transport adapter role: $source"
  fi
done <<< "$webKit_sources"

webKit_transport_source="$(
  guard_capture_files \
    'final class SumiWebKitDownloadTransport[[:space:]]*:[\s\S]{0,240}\bDownloadTransport\b[\s\S]{0,240}\bWKDownloadDelegate\b' \
    -U \
    "$download_root" -g '*.swift'
)"
webKit_transport_count="$(count_nonempty_lines "$webKit_transport_source")"
guard_exact 'live WebKit transport roles' "$webKit_transport_count" 1
if (( webKit_transport_count == 1 )); then
  cancel_count="$(
    guard_count_matches \
      'func cancel\(\)[[:space:]]*\{[[:space:]]*switch phase[[:space:]]*\{[[:space:]]*case \.idle, \.running:[\s\S]*download\.cancel' \
      -U "$webKit_transport_source"
  )"
  guard_exact 'idle/running WebKit transport cancellation' "$cancel_count" 1
fi

destination_allocator_source="$(
  guard_capture_files \
    'final class SumiDownloadDestinationAllocator\b' \
    "$download_root" -g '*.swift'
)"
destination_allocator_count="$(count_nonempty_lines "$destination_allocator_source")"
guard_exact 'download destination allocators' "$destination_allocator_count" 1
if (( destination_allocator_count == 1 )); then
  utility_task_count="$(
    guard_count_matches 'Task\.detached\(priority: \.utility\)' \
      "$destination_allocator_source"
  )"
  if (( utility_task_count == 0 )); then
    guard_record_failure 'destination filesystem allocation must run in a utility task'
  fi

  renewal_count="$(
    guard_count_matches \
      'func renewTemporaryDestination\([\s\S]*\)[[:space:]]*async' \
      -U "$destination_allocator_source"
  )"
  if (( renewal_count == 0 )); then
    guard_record_failure 'retry destination renewal must use the off-main allocation path'
  fi

  if awk '
    function occurrences(text, character, copy) {
      copy = text
      return gsub(character, "", copy)
    }
    /lock\.withLock[[:space:]]*\{/ {
      inside_lock = 1
      depth = occurrences($0, "\\{") - occurrences($0, "\\}")
    }
    inside_lock && /fileManager|ensureDirectoryExists|uniqueAvailable/ {
      unsafe = 1
    }
    inside_lock && !/lock\.withLock[[:space:]]*\{/ {
      depth += occurrences($0, "\\{") - occurrences($0, "\\}")
    }
    inside_lock && depth <= 0 {
      inside_lock = 0
      depth = 0
    }
    END { exit unsafe ? 0 : 1 }
  ' "$destination_allocator_source"; then
    guard_record_failure 'destination reservation ledger lock encloses filesystem work'
  fi
fi

progress_sources="$(
  guard_capture_files 'DownloadProgressPublishing' \
    "$download_root" -g '*.swift' \
    | sort
)"
while IFS= read -r source; do
  [[ -n "$source" ]] || continue
  polling_hits="$(
    guard_capture_matches \
      '\bTimer\b|scheduledTimer|asyncAfter|Task\.sleep|while[[:space:]]*\(' \
      "$source"
  )"
  if [[ -n "$polling_hits" ]]; then
    printf '%s\n' "$polling_hits" >&2
    guard_record_failure "download progress publication must be event-driven: $source"
  fi
done <<< "$progress_sources"

hidden_dependency_hits="$(
  guard_capture_matches \
    'struct[[:space:]]+Dependencies\b|DownloadManager[[:space:]]*\([[:space:]]*\)' \
    "$download_root" -g '*.swift'
)"
if [[ -n "$hidden_dependency_hits" ]]; then
  printf '%s\n' "$hidden_dependency_hits" >&2
  guard_record_failure \
    'download composition regrew a dependency bag or hidden live manager default'
fi

manager_source="$(
  guard_capture_files 'final class DownloadManager\b' \
    "$download_root" -g '*.swift'
)"
manager_source_count="$(count_nonempty_lines "$manager_source")"
guard_exact 'DownloadManager declarations' "$manager_source_count" 1
if (( manager_source_count == 1 )); then
  manager_constructor_edges="$(
    guard_count_matches \
      'private let (coordinator|workspace|orphanCleaner):' \
      "$manager_source"
  )"
  manager_attached_edges="$(
    guard_count_matches 'private var retryTransport:' "$manager_source"
  )"
  guard_exact 'DownloadManager constructed edges' "$manager_constructor_edges" 3
  guard_exact 'DownloadManager attached lifecycle edges' "$manager_attached_edges" 1

  retry_attachment_region="$(
    sed -n '/func attachRetryTransport(/,/^[[:space:]]*}/p' "$manager_source"
  )"
  retry_guard_count="$(
    guard_count_matches \
      'guard retryTransport == nil else \{ return false \}' \
      - <<< "$retry_attachment_region"
  )"
  retry_assignment_count="$(
    guard_count_matches 'retryTransport = transport' - \
      <<< "$retry_attachment_region"
  )"
  retry_wiring_count="$(
    guard_count_matches \
      'attachRetryTransport' \
      Sumi/Managers/BrowserManager/BrowserManagerRuntimeWiring.swift
  )"
  if (( retry_guard_count == 0 || retry_assignment_count == 0 || retry_wiring_count == 0 )); then
    guard_record_failure 'download retry transport must be a one-shot runtime attachment'
  fi

  guard_exact \
    'DownloadManager coordinator publications' \
    "$(guard_count_matches 'publishCoordinatorState\(\)' "$manager_source")" \
    2
fi

coordinator_source="$(
  guard_capture_files 'final class DownloadListCoordinator\b' \
    "$download_root" -g '*.swift'
)"
coordinator_source_count="$(count_nonempty_lines "$coordinator_source")"
guard_exact 'DownloadListCoordinator declarations' "$coordinator_source_count" 1
if (( coordinator_source_count == 1 && manager_source_count == 1 )); then
  event_attachment_region="$(
    sed -n '/func attachEventSink(/,/^[[:space:]]*}/p' "$coordinator_source"
  )"
  mutable_event_sink_count="$(
    guard_count_matches 'var on(Change|Finish):' "$coordinator_source"
  )"
  immutable_sink_guard_count="$(
    guard_count_matches \
      'guard !didAttachEventSink else \{ return false \}' \
      - <<< "$event_attachment_region"
  )"
  manager_sink_count="$(
    guard_count_matches 'coordinator\.attachEventSink\(self\)' "$manager_source"
  )"
  if (( mutable_event_sink_count != 0 || immutable_sink_guard_count == 0 || manager_sink_count == 0 )); then
    guard_record_failure \
      'coordinator events must use one immutable manager sink attachment'
  fi
fi

presenter_source="$download_root/DownloadFilePresenter.swift"
guard_require_file "$presenter_source"
presenter_attach_count="$(
  guard_count_matches \
    'func attachFileSourceIfPresent\(\)[[:space:]]*\{[[:space:]]*guard fileSource == nil' \
    -U "$presenter_source"
)"
if (( presenter_attach_count == 0 )); then
  guard_record_failure 'download file presenter may attach at most one file source'
fi

guard_require_directory App
startup_maintenance_count="$(
  guard_count_swift_matches 'performStartupMaintenance\(\)' App
)"
if (( startup_maintenance_count == 0 )); then
  guard_record_failure 'orphan cleanup has no explicit app lifecycle entry point'
fi

if (( manager_source_count == 1 )); then
  init_region="$(
    sed -n '/^[[:space:]]*init(/,/^[[:space:]]*}/p' "$manager_source"
  )"
  hidden_cleanup_count="$(
    guard_count_matches \
      'performStartupMaintenance|removeOrphanedDownloads' \
      - <<< "$init_region"
  )"
  if (( hidden_cleanup_count != 0 )); then
    guard_record_failure 'DownloadManager init performs hidden orphan cleanup'
  fi

  maintenance_region="$(
    sed -n '/func performStartupMaintenance()/,/^[[:space:]]*}/p' \
      "$manager_source"
  )"
  attached_settings_count="$(
    guard_count_matches 'let settings,' - <<< "$maintenance_region"
  )"
  cleaner_count="$(
    guard_count_matches 'let orphanCleaner' - <<< "$maintenance_region"
  )"
  fallback_preference_count="$(
    guard_count_matches \
      '\?\?[[:space:]]*SumiDownloadDestinationPreference' \
      - <<< "$maintenance_region"
  )"
  if (( attached_settings_count == 0 || cleaner_count == 0 || fallback_preference_count != 0 )); then
    guard_record_failure \
      'startup cleanup must wait for attached settings and use its exact preference'
  fi
fi

guard_finish 'download architecture boundary audit'
