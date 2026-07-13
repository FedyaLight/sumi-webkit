#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

download_root="Sumi/Managers/DownloadManager"
status=0

orchestration_sources="$(
  rg -l 'final class (DownloadManager|DownloadListCoordinator|DownloadTransaction)\b' \
    "$download_root" -g '*.swift' | sort
)"
orchestration_count="$(awk 'NF { count += 1 } END { print count + 0 }' <<< "$orchestration_sources")"

if [[ "$orchestration_count" -ne 3 ]]; then
  printf 'error: expected three semantic download orchestration roles, found %d\n' \
    "$orchestration_count" >&2
  status=1
fi

while IFS= read -r source; do
  [[ -n "$source" ]] || continue
  if rg -n \
    'import WebKit|\b(WKDownload|WKWebView|WKDownloadDelegate|FileManager|NSWorkspace|NSSavePanel|DownloadFileUtilities)\b' \
    "$source"; then
    printf 'error: download orchestration directly owns WebKit, filesystem, or workspace behavior: %s\n' \
      "$source" >&2
    status=1
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
  count="$(rg -c "protocol ${port}\\b" "$download_root" -g '*.swift' | awk -F: '{ total += $NF } END { print total + 0 }')"
  if [[ "$count" -ne 1 ]]; then
    printf 'error: expected exactly one %s port, found %s\n' "$port" "$count" >&2
    status=1
  fi
done

while IFS= read -r source; do
  [[ -n "$source" ]] || continue
  if ! rg -q \
    'DownloadWebKitTransportAdapting|DownloadTransport, WKDownloadDelegate|DownloadRetryTransportStarting' \
    "$source"; then
    printf 'error: WebKit download code exists outside a transport adapter role: %s\n' \
      "$source" >&2
    status=1
  fi
done < <(rg -l 'import WebKit|\b(WKDownload|WKDownloadDelegate)\b' "$download_root" -g '*.swift' || true)

webKit_transport_source="$(
  rg -l -U \
    'final class SumiWebKitDownloadTransport[[:space:]]*:[\s\S]{0,240}\bDownloadTransport\b[\s\S]{0,240}\bWKDownloadDelegate\b' \
    "$download_root" -g '*.swift' || true
)"
webKit_transport_count="$(
  awk 'NF { count += 1 } END { print count + 0 }' \
    <<< "$webKit_transport_source"
)"
if [[ "$webKit_transport_count" -ne 1 ]]; then
  printf 'error: expected one format-independent live WebKit transport match, found %s\n' \
    "$webKit_transport_count" >&2
  status=1
elif ! rg -q -U \
  'func cancel\(\)[[:space:]]*\{[[:space:]]*switch phase[[:space:]]*\{[[:space:]]*case \.idle, \.running:[\s\S]*download\.cancel' \
  "$webKit_transport_source"; then
    printf 'error: the live WebKit adapter must cancel idle and running transports exactly once\n' >&2
    status=1
fi

destination_allocator_source="$(
  rg -l 'final class SumiDownloadDestinationAllocator\b' \
    "$download_root" -g '*.swift'
)"
if ! rg -q 'Task\.detached\(priority: \.utility\)' \
    "$destination_allocator_source"; then
  printf 'error: destination filesystem allocation must run in a utility task\n' >&2
  status=1
fi
if ! rg -q -U \
  'func renewTemporaryDestination\([\s\S]*\)[[:space:]]*async' \
  "$destination_allocator_source"; then
  printf 'error: retry destination renewal must use the off-main allocation path\n' >&2
  status=1
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
  printf 'error: destination reservation ledger lock encloses filesystem work\n' >&2
  status=1
fi

progress_sources="$(
  rg -l 'DownloadProgressPublishing' "$download_root" -g '*.swift' | sort
)"
while IFS= read -r source; do
  [[ -n "$source" ]] || continue
  if rg -n '\bTimer\b|scheduledTimer|asyncAfter|Task\.sleep|while[[:space:]]*\(' "$source"; then
    printf 'error: download progress publication must be event-driven: %s\n' "$source" >&2
    status=1
  fi
done <<< "$progress_sources"

if rg -n 'struct[[:space:]]+Dependencies\b|DownloadManager[[:space:]]*\([[:space:]]*\)' \
  "$download_root" -g '*.swift'; then
  printf 'error: download composition regrew a dependency bag or hidden live manager default\n' >&2
  status=1
fi

manager_source="$(rg -l 'final class DownloadManager\b' "$download_root" -g '*.swift')"
manager_constructor_edges="$(
  rg -c 'private let (coordinator|workspace|orphanCleaner):' "$manager_source" || true
)"
manager_constructor_edges="${manager_constructor_edges:-0}"
manager_attached_edges="$(
  rg -c 'private var retryTransport:' "$manager_source" || true
)"
manager_attached_edges="${manager_attached_edges:-0}"
if [[ "$manager_constructor_edges" -ne 3 || "$manager_attached_edges" -ne 1 ]]; then
  printf 'error: DownloadManager must have three constructed edges and one explicit attached lifecycle edge, found %s + %s\n' \
    "$manager_constructor_edges" "$manager_attached_edges" >&2
  status=1
fi

retry_attachment_region="$(
  sed -n '/func attachRetryTransport(/,/^[[:space:]]*}/p' "$manager_source"
)"
if ! rg -q 'guard retryTransport == nil else \{ return false \}' \
    <<< "$retry_attachment_region" \
    || ! rg -q 'retryTransport = transport' <<< "$retry_attachment_region" \
    || ! rg -q 'attachRetryTransport' \
      Sumi/Managers/BrowserManager/BrowserManagerRuntimeWiring.swift; then
  printf 'error: download retry transport must be a one-shot runtime attachment\n' >&2
  status=1
fi

manager_publication_count="$(rg -c 'publishCoordinatorState\(\)' "$manager_source")"
if [[ "$manager_publication_count" -ne 2 ]]; then
  printf 'error: manager state must publish only through the coordinator change callback\n' >&2
  status=1
fi

coordinator_source="$(
  rg -l 'final class DownloadListCoordinator\b' "$download_root" -g '*.swift'
)"
event_attachment_region="$(
  sed -n '/func attachEventSink(/,/^[[:space:]]*}/p' "$coordinator_source"
)"
if rg -q 'var on(Change|Finish):' "$coordinator_source" \
    || ! rg -q 'guard !didAttachEventSink else \{ return false \}' \
      <<< "$event_attachment_region" \
    || ! rg -q 'coordinator\.attachEventSink\(self\)' "$manager_source"; then
  printf 'error: coordinator events must use one immutable manager sink attachment\n' >&2
  status=1
fi

presenter_source="$download_root/DownloadFilePresenter.swift"
if ! rg -q -U \
  'func attachFileSourceIfPresent\(\)[[:space:]]*\{[[:space:]]*guard fileSource == nil' \
  "$presenter_source"; then
  printf 'error: download file presenter may attach at most one file source\n' >&2
  status=1
fi

if ! rg -q 'performStartupMaintenance\(\)' App -g '*.swift'; then
  printf 'error: orphan cleanup has no explicit app lifecycle entry point\n' >&2
  status=1
fi
manager_source="$(rg -l 'final class DownloadManager\b' "$download_root" -g '*.swift')"
init_region="$(sed -n '/^[[:space:]]*init(/,/^[[:space:]]*}/p' "$manager_source")"
if rg -q 'performStartupMaintenance|removeOrphanedDownloads' <<< "$init_region"; then
  printf 'error: DownloadManager init performs hidden orphan cleanup\n' >&2
  status=1
fi

maintenance_region="$(
  sed -n '/func performStartupMaintenance()/,/^[[:space:]]*}/p' "$manager_source"
)"
if ! rg -q 'let settings,' <<< "$maintenance_region" \
    || ! rg -q 'let orphanCleaner' <<< "$maintenance_region" \
    || rg -q '\?\?[[:space:]]*SumiDownloadDestinationPreference' <<< "$maintenance_region"; then
  printf 'error: startup cleanup must wait for attached settings and use its exact preference\n' >&2
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

echo "download architecture boundary audit passed"
