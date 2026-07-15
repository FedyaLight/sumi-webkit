#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

registry='Sumi/Managers/WindowRegistry/WindowRegistry.swift'
shell='Sumi/Services/BrowserWindowShellService.swift'
bindings='App/BrowserWindowRegistryBindings.swift'
browser_manager='Sumi/Managers/BrowserManager/BrowserManager.swift'
session_bundle='Sumi/Managers/BrowserManager/BrowserWindowSessionBundle.swift'
publication='Sumi/Managers/BrowserManager/WindowExtensionPublicationTransaction.swift'
publication_live='Sumi/Managers/BrowserManager/WindowExtensionPublicationTransaction+Live.swift'
runtime_factory='Sumi/Managers/BrowserManager/TabBrowserRuntimeFactory.swift'
extension_composition='Sumi/Managers/BrowserManager/BrowserExtensionBridgeComposition.swift'
require_pattern() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if [[ ! -f "$file" ]]; then
    guard_record_failure "$message (missing source: $file)"
    return
  fi
  local match_count
  match_count="$(guard_count_matches "$pattern" "$file")" || return
  if (( match_count == 0 )); then
    guard_record_failure "$message"
  fi
}

require_pattern "$registry" 'private var provisionalWindows:' \
  'WindowRegistry lost isolated provisional storage'
require_pattern "$registry" 'func beginRegistration\(' \
  'WindowRegistry lost provisional registration entry point'
require_pattern "$registry" 'func commitRegistration\(' \
  'WindowRegistry lost registration commit entry point'
require_pattern "$registry" 'func rollbackProvisionalRegistration\(' \
  'WindowRegistry lost exact provisional rollback entry point'
require_pattern "$registry" 'struct EventSink' \
  'WindowRegistry lost its typed lifecycle event sink'
require_pattern "$registry" 'func installEventSink\(' \
  'WindowRegistry lost one-time event sink installation'
require_pattern "$registry" 'struct EventSinkInstallationReceipt:' \
  'WindowRegistry lost typed installation evidence'

mutable_callback_count="$(
  guard_count_matches \
    'var (prepareWindowRegistration|publishWindowRegistration|onWindowClose|onActiveWindowChange|onWindowVisibilityChange|onAllWindowsClosed):' \
    "$registry"
)"
if (( mutable_callback_count > 0 )); then
  guard_record_failure 'independently overwritable WindowRegistry callback slots resurfaced'
fi

production_sink_installers="$(
  guard_capture_matches '\.installEventSink\(' -g '*.swift' App Sumi
)"
production_sink_installer_count="$(
  guard_count_matches '\.installEventSink\(' -g '*.swift' App Sumi
)"
if [[ "$production_sink_installer_count" != "1" ]] \
    || [[ "$production_sink_installers" != "$bindings:"* ]]; then
  guard_record_failure \
    "production must install the WindowRegistry event sink exactly once in $bindings: $production_sink_installers"
fi

committed_rollback_count="$(
  guard_count_matches 'rollbackRegistration\(' -g '*.swift' Sumi App
)"
if (( committed_rollback_count > 0 )); then
  guard_record_failure 'committed-capable window registration rollback resurfaced'
fi

begin_body="$(
  sed -n '/^    func beginRegistration(/,/^    }$/p' "$registry"
)"
begin_visibility_count="$(
  guard_count_matches \
    'windowAwaiters|publishWindowRegistration' \
    - <<< "$begin_body"
)"
if (( begin_visibility_count > 0 )); then
  guard_record_failure 'provisional window registration became externally observable'
fi

rollback_body="$(
  sed -n '/^    func rollbackProvisionalRegistration(/,/^    }$/p' "$registry"
)"
rollback_lifecycle_count="$(
  guard_count_matches \
    '_windows\.removeValue|onWindowClose|onAllWindowsClosed' \
    - <<< "$rollback_body"
)"
if (( rollback_lifecycle_count > 0 )); then
  guard_record_failure 'provisional rollback can mutate committed window lifecycle'
fi

commit_body="$(
  sed -n '/^    func commitRegistration(/,/^    }$/p' "$registry"
)"
publication_line="$(
  guard_capture_matches \
    'eventSink\?\.publishWindowRegistration\(' \
    - <<< "$commit_body" \
    | cut -d: -f1 \
    | head -1
)"
awaiter_line="$(
  guard_capture_matches \
    'continuation\.resume\(returning: window\)' \
    - <<< "$commit_body" \
    | cut -d: -f1 \
    | head -1
)"
if [[ -z "$publication_line" || -z "$awaiter_line" ]] \
    || (( publication_line >= awaiter_line )); then
  guard_record_failure 'committed extension publication must precede window awaiter resumption'
fi

shell_transaction="$(
  sed -n '/^    func createNewWindow(/,/^    @discardableResult$/p' "$shell"
)"
begin_line="$(
  guard_capture_matches 'beginRegistration\(windowState\)' - <<< "$shell_transaction" \
    | cut -d: -f1 \
    | head -1
)"
validate_line="$(
  guard_capture_matches \
    'validateRestoredStateBeforePublication\(windowState\)' \
    - <<< "$shell_transaction" \
    | cut -d: -f1 \
    | head -1
)"
commit_line="$(
  guard_capture_matches \
    'context\.windowRegistry\.commitRegistration\(' \
    - <<< "$shell_transaction" \
    | cut -d: -f1 \
    | head -1
)"
if [[ -z "$begin_line" || -z "$validate_line" || -z "$commit_line" ]] \
    || (( begin_line >= validate_line || validate_line >= commit_line )); then
  guard_record_failure 'browser shell must prepare, validate, then commit window registration'
fi

require_pattern "$bindings" 'prepareRegistration\(windowState\)' \
  'window registry restoration must run during provisional preparation'
require_pattern "$bindings" 'commitRegistration\(windowState\)' \
  'extension window lifecycle must publish only after registry commit'
require_pattern "$bindings" 'WindowRegistry\.EventSink\(' \
  'browser workflows must be installed through one immutable event sink'
require_pattern "$browser_manager" 'lazy var windowExtensionPublication' \
  'BrowserManager lost its explicit cross-window extension publication transaction'
require_pattern "$session_bundle" \
  'extensionPublication: browserManager\.windowExtensionPublication' \
  'window restoration must use the process-wide publication transaction'
require_pattern "$runtime_factory" \
  'extensionPublication: browserManager\.windowExtensionPublication' \
  'WebKit and link window opening must use the process-wide publication transaction'
require_pattern "$extension_composition" \
  'extensionPublication: browserManager\.windowExtensionPublication' \
  'extension-requested windows must use the process-wide publication transaction'
require_pattern "$publication" 'protocol BrowserWindowExtensionPublishing:' \
  'window publication lost its exact publishing capability'
require_pattern "$publication" 'protocol BrowserWindowExtensionFocusNotifying:' \
  'window focus notification lost its exact capability'

combined_publication_capability_count="$(
  guard_count_matches \
    'BrowserWindowExtensionLifecycleNotifying' \
    "$publication"
)"
hidden_session_publication_count="$(
  guard_count_matches \
    '^    let extensionPublication:' \
    "$session_bundle"
)"
if (( combined_publication_capability_count > 0 \
    || hidden_session_publication_count > 0 )); then
  guard_record_failure \
    'extension publication/focus capabilities were recombined or hidden in the session bundle'
fi

publication_constructors="$(
  guard_capture_matches \
    'WindowExtensionPublicationTransaction\(' \
    -g '*.swift' App Sumi
)"
publication_constructor_count="$(
  guard_count_matches \
    'WindowExtensionPublicationTransaction\(' \
    -g '*.swift' App Sumi
)"
if [[ "$publication_constructor_count" != "1" ]] \
    || [[ "$publication_constructors" != "$publication_live:"* ]]; then
  guard_record_failure \
    "production must construct the process-wide window publication transaction exactly once in $publication_live: $publication_constructors"
fi

guard_finish 'window registration transaction boundary'
