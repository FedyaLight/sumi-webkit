#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

registry='Sumi/Managers/WindowRegistry/WindowRegistry.swift'
shell='Sumi/Services/BrowserWindowShellService.swift'
bindings='App/BrowserWindowRegistryBindings.swift'
browser_manager='Sumi/Managers/BrowserManager/BrowserManager.swift'
session_bundle='Sumi/Managers/BrowserManager/BrowserWindowSessionBundle.swift'
publication='Sumi/Managers/BrowserManager/WindowExtensionPublicationTransaction.swift'
publication_live='Sumi/Managers/BrowserManager/WindowExtensionPublicationTransaction+Live.swift'
runtime_factory='Sumi/Managers/BrowserManager/TabBrowserRuntimeFactory.swift'
extension_composition='Sumi/Managers/BrowserManager/BrowserExtensionBridgeComposition.swift'
status=0

require_pattern() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if [[ ! -f "$file" ]] || ! rg -q "$pattern" "$file"; then
    printf 'error: %s\n' "$message" >&2
    status=1
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
require_pattern "$registry" 'var publishWindowRegistration:' \
  'WindowRegistry lost post-validation publication boundary'

if rg -q 'rollbackRegistration\(' Sumi App -g '*.swift'; then
  printf 'error: committed-capable window registration rollback resurfaced\n' >&2
  status=1
fi

begin_body="$(
  sed -n '/^    func beginRegistration(/,/^    }$/p' "$registry"
)"
if rg -q 'windowAwaiters|publishWindowRegistration' <<< "$begin_body"; then
  printf 'error: provisional window registration became externally observable\n' >&2
  status=1
fi

rollback_body="$(
  sed -n '/^    func rollbackProvisionalRegistration(/,/^    }$/p' "$registry"
)"
if rg -q '_windows\.removeValue|onWindowClose|onAllWindowsClosed' \
    <<< "$rollback_body"; then
  printf 'error: provisional rollback can mutate committed window lifecycle\n' >&2
  status=1
fi

commit_body="$(
  sed -n '/^    func commitRegistration(/,/^    }$/p' "$registry"
)"
publication_line="$(rg -n 'publishWindowRegistration\?\(' <<< "$commit_body" | cut -d: -f1 | head -1)"
awaiter_line="$(rg -n 'continuation\.resume\(returning: window\)' <<< "$commit_body" | cut -d: -f1 | head -1)"
if [[ -z "$publication_line" || -z "$awaiter_line" ]] \
    || (( publication_line >= awaiter_line )); then
  printf 'error: committed extension publication must precede window awaiter resumption\n' >&2
  status=1
fi

shell_transaction="$(
  sed -n '/^    func createNewWindow(/,/^    @discardableResult$/p' "$shell"
)"
begin_line="$(rg -n 'beginRegistration\(windowState\)' <<< "$shell_transaction" | cut -d: -f1 | head -1)"
validate_line="$(rg -n 'validateRestoredStateBeforePublication\(windowState\)' <<< "$shell_transaction" | cut -d: -f1 | head -1)"
commit_line="$(rg -n 'context\.windowRegistry\.commitRegistration\(' <<< "$shell_transaction" | cut -d: -f1 | head -1)"
if [[ -z "$begin_line" || -z "$validate_line" || -z "$commit_line" ]] \
    || (( begin_line >= validate_line || validate_line >= commit_line )); then
  printf 'error: browser shell must prepare, validate, then commit window registration\n' >&2
  status=1
fi

require_pattern "$bindings" 'prepareRegistration\(windowState\)' \
  'window registry restoration must run during provisional preparation'
require_pattern "$bindings" 'commitRegistration\(windowState\)' \
  'extension window lifecycle must publish only after registry commit'
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

if rg -q 'BrowserWindowExtensionLifecycleNotifying' "$publication" \
    || rg -q '^    let extensionPublication:' "$session_bundle"; then
  printf 'error: extension publication/focus capabilities were recombined or hidden in the session bundle\n' >&2
  status=1
fi

publication_constructors="$(
  rg -n 'WindowExtensionPublicationTransaction\(' App Sumi -g '*.swift' || true
)"
if [[ "$(wc -l <<< "$publication_constructors" | tr -d ' ')" != "1" ]] \
    || [[ "$publication_constructors" != "$publication_live:"* ]]; then
  printf 'error: production must construct the process-wide window publication transaction exactly once\n%s\n' \
    "$publication_constructors" >&2
  status=1
fi

for test_name in \
  testAwaiterCannotObserveRolledBackProvisionalWindow \
  testProvisionalRollbackRejectsCommittedWindow \
  testProvisionalRollbackRequiresExactObjectIdentity \
  testReopenRejectsRegisteredStateWithWrongArchiveIdentity \
  testPreparedWindowDoesNotPublishExtensionLifecycleBeforeRegistryCommit; do
  if ! rg -q "func[[:space:]]+${test_name}\\b" SumiTests -g '*.swift'; then
    printf 'error: window registration regression missing: %s\n' "$test_name" >&2
    status=1
  fi
done

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo 'window registration transaction boundary passed'
