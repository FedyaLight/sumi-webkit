#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

transaction='Sumi/Managers/BrowserManager/BrowserExtensionRequestedWindowTransaction.swift'
creation='Sumi/Managers/ExtensionManager/ExtensionRequestedWindowCreation.swift'
router='Sumi/Managers/ExtensionManager/ExtensionWindowRequestRouter.swift'
status=0

require_literal() {
  local file="$1"
  local literal="$2"
  local message="$3"
  if [[ ! -f "$file" ]] || ! rg -Fq "$literal" "$file"; then
    printf 'error: %s\n' "$message" >&2
    status=1
  fi
}

for retired in \
  'ExtensionRequestedWindowOpeningOwner' \
  'awaitNextExtensionWindow' \
  'createExtensionWindow()'; do
  hits="$(rg -n "$retired" App Sumi -g '*.swift' || true)"
  if [[ -n "$hits" ]]; then
    printf 'error: retired async empty-window path returned: %s\n%s\n' \
      "$retired" "$hits" >&2
    status=1
  fi
done

polling_hits="$(
  rg -n 'Task\.sleep|awaitNextRegisteredWindow|while[[:space:]]+true' \
    "$transaction" "$router" || true
)"
if [[ -n "$polling_hits" ]]; then
  printf 'error: requested-window transaction started polling for ownership\n%s\n' \
    "$polling_hits" >&2
  status=1
fi

require_literal "$creation" 'protocol PreparedExtensionRequestedWindow' \
  'requested-window preparation capability is missing'
require_literal "$creation" 'func present() -> Bool' \
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
  'guard tabURLs.count <= 1 else' \
  'creator.prepareExtensionRequestedWindow(' \
  'let adapter = publishedWindow(window, profileID)' \
  'guard preparedWindow.present(),' \
  'publishedWindow(window, profileID) === adapter' \
  'preparedWindow.accept()' \
  'preparedWindow.cancel()' \
  'profileRuntime.controllersByProfile[profileID] === controller' \
  'controller.extensionContext(for: loadURL) === loadContext'; do
  require_literal "$router" "$literal" \
    "requested-window routing invariant missing: $literal"
done

raw_adapter_hits="$(
  rg -n 'adapterResolutionOwner\.windowAdapter|adapterStore\.windowAdapter' \
    "$router" "$transaction" || true
)"
if [[ -n "$raw_adapter_hits" ]]; then
  printf 'error: requested-window path materialized a raw window adapter\n%s\n' \
    "$raw_adapter_hits" >&2
  status=1
fi

for test_name in \
  testExtensionRequestedWindowPublishesExactTabBeforeFocusAndCompletion \
  testExtensionRequestedWindowCancelsBeforePresentationWhenPublishedAdapterIsMissing \
  testExtensionRequestedWindowRejectsMultipleInitialURLsWithoutMutation; do
  if ! rg -q "func[[:space:]]+${test_name}\\b" SumiTests -g '*.swift'; then
    printf 'error: requested-window regression missing: %s\n' "$test_name" >&2
    status=1
  fi
done

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo 'extension requested-window transaction boundary passed'
