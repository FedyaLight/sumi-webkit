#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

root='Sumi/Managers/ExtensionManager'
bridge="$root/ExtensionControllerDelegateBridge.swift"
admission="$root/ExtensionControllerCallbackAdmission.swift"
installer="$root/ExtensionControllerBrowserRouteInstaller.swift"
factory="$root/ExtensionAttachedControllerRuntimeFactory.swift"
assembler="$root/ExtensionControllerRuntimeAssembler.swift"
attached_callbacks="$root/ExtensionAttachedControllerCallbacks.swift"

for file in "$bridge" "$admission" "$installer" "$factory" "$assembler" \
  "$attached_callbacks"; do
  guard_require_file "$file"
done

guard_expect_no_matches \
  'controller runtime regained a manager root or generic closure bag' \
  '\bExtensionManager\b|\bBrowserManager\b|struct (Dependencies|Actions)\b' \
  "$admission" "$installer" "$factory" "$assembler" "$attached_callbacks"
guard_expect_no_matches \
  'controller callback admission uses fallback identity' \
  'currentProfile|resolveProfile|extensionID\(for:|profileId\(for:|\?\? UUID\(' \
  "$admission"
guard_expect_no_matches \
  'controller delegate exposes mutable route replacement' \
  'func (set|replace|clear)BrowserRoutes' \
  "$bridge"
guard_expect_no_matches \
  'controller runtime exposes attached graph storage' \
  '\bExtensionAttachedBrowserRuntime\b' \
  "$bridge" "$admission" "$installer" "$factory" "$assembler"

capture_count="$(guard_count_matches 'coreRoutes\.callbackAdmission\.capture\(' "$bridge")"
guard_exact 'core callback evidence captures' "$capture_count" 8
fail_closed_count="$(guard_count_matches 'completionHandler\((\[\], nil|CancellationError\(\)|[[:space:]]*nil,[[:space:]]*CancellationError\(\))' "$bridge" -U)"
if (( fail_closed_count < 6 )); then
  guard_record_failure 'controller callbacks lost deterministic fail-closed settlement'
fi

for proof in \
  'exactContextIdentity(for: context)' \
  'controllerBindingRevision' \
  'contextBindingRevision' \
  'extensionLoadRevision'; do
  count="$(guard_count_matches "$proof" "$admission" -F)"
  if (( count == 0 )); then
    guard_record_failure "callback evidence lost authority dimension: $proof"
  fi
done

install_count="$(guard_count_matches 'func installBrowserRoutes\(' "$bridge")"
guard_exact 'one-shot browser route installation API' "$install_count" 1
install_guard_count="$(guard_count_matches 'guard browserRoutes == nil else' "$bridge")"
guard_exact 'one-shot browser route admission' "$install_guard_count" 1

factory_fields="$(guard_count_matches '^[[:space:]]*private let ' "$factory")"
guard_max 'attached controller factory collaborators' "$factory_fields" 5
factory_assemble_count="$(guard_count_matches 'func assemble\(' "$factory")"
guard_exact 'attached controller factory operations' "$factory_assemble_count" 1

guard_finish 'extension controller runtime boundary'
