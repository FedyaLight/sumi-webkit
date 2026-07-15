#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

legacy='Sumi/Managers/ExtensionManager/ExtensionUtils.swift'
roles=(
  'Sumi/Managers/ExtensionManager/ExtensionURLIdentity.swift'
  'Sumi/Managers/ExtensionManager/ExtensionDisplayNameResolver.swift'
  'Sumi/Managers/ExtensionManager/ExtensionPathSafety.swift'
  'Sumi/Managers/ExtensionManager/ExtensionManifestValidation.swift'
  'Sumi/Managers/ExtensionManager/ExtensionHostPermissionMatcher.swift'
  'Sumi/Managers/ExtensionManager/ExtensionManifestLocalization.swift'
  'Sumi/Managers/ExtensionManager/ExtensionPackageFingerprint.swift'
  'Sumi/Managers/ExtensionManager/ExtensionManifestIconResolver.swift'
  'Sumi/Managers/ExtensionManager/ExtensionManifestSemantics.swift'
  'Sumi/Managers/ExtensionManager/ExtensionOptionsPageResolution.swift'
)

if [[ -e "$legacy" ]]; then
  echo 'error: ExtensionUtils god namespace returned' >&2
  exit 1
fi
for role in "${roles[@]}"; do
  [[ -f "$role" ]] || {
    printf 'error: missing extension utility role: %s\n' "$role" >&2
    exit 1
  }
done

legacy_symbol_hits="$(
  guard_capture_matches '\bExtensionUtils\b' \
    Sumi SumiTests --glob '*.swift'
)"
if [[ -n "$legacy_symbol_hits" ]]; then
  printf '%s\n' "$legacy_symbol_hits" >&2
  echo 'error: compatibility facade or legacy ExtensionUtils consumer returned' >&2
  exit 1
fi

url_identity="${roles[0]}"
display_name="${roles[1]}"
path_safety="${roles[2]}"
validation="${roles[3]}"
host_matcher="${roles[4]}"
localization="${roles[5]}"
fingerprint="${roles[6]}"
icons="${roles[7]}"
semantics="${roles[8]}"
options="${roles[9]}"

required_role_boundaries=(
  "$url_identity|SumiExtensionOwnedURL\\.isExtensionOwnedURL"
  "$display_name|ExtensionURLIdentity\\.extensionID"
  "$path_safety|resolvingSymlinksInPath"
  "$validation|validateContents"
  "$host_matcher|WKWebExtension\\.MatchPattern"
  "$localization|messages\\.json"
  "$fingerprint|SHA256\\.hash"
  "$icons|iconCandidates"
  "$semantics|activationSummary"
  "$options|existingValidatedPath"
)
for role_boundary in "${required_role_boundaries[@]}"; do
  role_file="${role_boundary%%|*}"
  role_pattern="${role_boundary#*|}"
  role_boundary_count="$(
    guard_count_matches "$role_pattern" "$role_file"
  )"
  if (( role_boundary_count == 0 )); then
    printf 'error: extension utility role lost required boundary: %s\n' \
      "$role_pattern" >&2
    exit 1
  fi
done

url_policy_hits="$(
  guard_capture_matches \
    'import (WebKit|CryptoKit|OSLog)|InstalledExtension' "$url_identity"
)"
if [[ -n "$url_policy_hits" ]]; then
  printf '%s\n' "$url_policy_hits" >&2
  echo 'error: extension URL identity absorbed runtime, logging, or catalog policy' >&2
  exit 1
fi
manifest_dependency_hits="$(
  guard_capture_matches 'import (WebKit|CryptoKit|OSLog)' \
    "$display_name" "$icons" "$semantics"
)"
if [[ -n "$manifest_dependency_hits" ]]; then
  printf '%s\n' "$manifest_dependency_hits" >&2
  echo 'error: pure extension identity/manifest roles gained runtime or logging dependencies' >&2
  exit 1
fi
path_policy_hits="$(
  guard_capture_matches \
    'WKWebExtension|InstalledExtension|SHA256|messages\.json' "$path_safety"
)"
if [[ -n "$path_policy_hits" ]]; then
  printf '%s\n' "$path_policy_hits" >&2
  echo 'error: path-safety role absorbed unrelated extension semantics' >&2
  exit 1
fi
fingerprint_policy_hits="$(
  guard_capture_matches \
    'resolvingSymlinksInPath|WKWebExtension|InstalledExtension' "$fingerprint"
)"
if [[ -n "$fingerprint_policy_hits" ]]; then
  printf '%s\n' "$fingerprint_policy_hits" >&2
  echo 'error: fingerprint role absorbed path/runtime/catalog policy' >&2
  exit 1
fi

echo 'extension utility role boundary passed'
