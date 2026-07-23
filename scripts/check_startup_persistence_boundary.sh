#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

runtime_paths=(App Sumi Settings SidebarChrome CommandPalette UI)
allowed_file="Sumi/Services/SumiStartupPersistence.swift"
permission_composition_file="Sumi/Managers/BrowserManager/BrowserManagerStartupPersistence.swift"

check_pattern() {
  local label="$1"
  local pattern="$2"
  local matches

  matches="$(guard_capture_matches "$pattern" -g '*.swift' "${runtime_paths[@]}")" || return
  [[ -z "$matches" ]] && return

  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    local relative_path="${match%%:*}"
    if [[ "$relative_path" != "$allowed_file" ]]; then
      guard_record_failure "$label outside $allowed_file: $match"
    fi
  done <<< "$matches"
}

check_pattern_allowed_only_in() {
  local label="$1"
  local pattern="$2"
  local allowed_path="$3"
  local matches

  matches="$(guard_capture_matches "$pattern" -g '*.swift' "${runtime_paths[@]}")" || return
  [[ -z "$matches" ]] && return

  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    local relative_path="${match%%:*}"
    if [[ "$relative_path" != "$allowed_path" ]]; then
      guard_record_failure "$label outside $allowed_path: $match"
    fi
  done <<< "$matches"
}

check_pattern "SwiftData model container construction" 'ModelContainer\s*\('
check_pattern "SwiftData model configuration construction" 'ModelConfiguration\s*\('
check_pattern "SwiftData schema construction" 'Schema\s*\('
check_pattern_allowed_only_in \
  "persistent permission-store construction" \
  'SwiftDataPermissionStore\s*\(' \
  "$permission_composition_file"
check_pattern_allowed_only_in \
  "autoplay permission-adapter construction" \
  'SumiAutoplayPolicyStoreAdapter\s*\(' \
  "$permission_composition_file"

legacy_permission_forwarders="$(
  guard_capture_matches \
    'SumiStartupPersistenceComposition\.(persistentPermissionStore|autoplayPolicyStore)' \
    -g '*.swift' "${runtime_paths[@]}"
)"
if [[ -n "$legacy_permission_forwarders" ]]; then
  guard_record_failure "legacy startup permission forwarding: $legacy_permission_forwarders"
fi

guard_finish 'startup persistence boundary audit'
