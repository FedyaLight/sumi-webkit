#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

transaction='Sumi/Managers/BrowserManager/BrowserExtensionRequestedWindowTransaction.swift'
creation='Sumi/Managers/ExtensionManager/ExtensionRequestedWindowCreation.swift'
router='Sumi/Managers/ExtensionManager/ExtensionWindowRequestRouter.swift'
status=0

require_literal() {
  local file="$1"
  local literal="$2"
  local message="$3"
  local count
  count="$(guard_count_matches "$literal" "$file" -F)"
  if (( count == 0 )); then
    printf 'error: %s\n' "$message" >&2
    status=1
  fi
}

for retired in \
  'ExtensionRequestedWindowOpeningOwner' \
  'awaitNextExtensionWindow' \
  'createExtensionWindow()'; do
  hits="$(guard_capture_matches "$retired" App Sumi -g '*.swift')"
  if [[ -n "$hits" ]]; then
    printf 'error: retired async empty-window path returned: %s\n%s\n' \
      "$retired" "$hits" >&2
    status=1
  fi
done

polling_hits="$(
  guard_capture_matches \
    'Task\.sleep|awaitNextRegisteredWindow|while[[:space:]]+true' \
    "$transaction" "$router"
)"
if [[ -n "$polling_hits" ]]; then
  printf 'error: requested-window transaction started polling for ownership\n%s\n' \
    "$polling_hits" >&2
  status=1
fi

require_literal "$creation" 'protocol PreparedExtensionRequestedWindow' \
  'requested-window preparation capability is missing'
require_literal "$creation" 'func present(activate: Bool) -> Bool' \
  'requested-window presentation is no longer explicitly deferred'
require_literal "$creation" 'func accept() -> Bool' \
  'requested-window post-focus acceptance boundary is missing'
require_literal "$creation" 'func cancel()' \
  'requested-window rollback capability is missing'

for literal in \
  'presentAfterRegistration: false' \
  ') == .extensionPrepared' \
  '== .extensionPublished' \
  'hasExactTrackedWebView(' \
  'revokeCommittedPublicationIfNeeded' \
  'rollbackRegisteredWindow' \
  'preparedByToken.removeValue(forKey: token)'; do
  require_literal "$transaction" "$literal" \
    "atomic requested-window invariant missing: $literal"
done

for literal in \
  'request.tabURLs.map(Optional.some)' \
  'loads.allSatisfy({ $0.hasUnresolvedExtensionOwnership == false })' \
  'creator.prepareExtensionRequestedWindow(' \
  'let adapter = publishedWindow(window, profileID)' \
  'guard preparedWindow.present(activate: request.shouldBeFocused),' \
  'publishedWindow(window, profileID) === adapter' \
  'preparedWindow.accept()' \
  'preparedWindow.cancel()' \
  'profileRuntime.controller(for: profileID) === controller' \
  'profileRuntime.owns(loadContext, in: profileID)' \
  'controller.extensionContext(for: loadURL) === loadContext'; do
  require_literal "$router" "$literal" \
    "requested-window routing invariant missing: $literal"
done

raw_adapter_hits="$(
  guard_capture_matches \
    'adapterCatalog\.windowAdapter|adapterStore\.windowAdapter' \
    "$router" "$transaction"
)"
if [[ -n "$raw_adapter_hits" ]]; then
  printf 'error: requested-window path materialized a raw window adapter\n%s\n' \
    "$raw_adapter_hits" >&2
  status=1
fi

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo 'extension requested-window transaction boundary passed'
