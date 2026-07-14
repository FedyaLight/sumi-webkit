#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

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

if rg -n '\bExtensionUtils\b' Sumi SumiTests --glob '*.swift'; then
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

rg -q 'SumiExtensionOwnedURL\.isExtensionOwnedURL' "$url_identity"
rg -q 'ExtensionURLIdentity\.extensionID' "$display_name"
rg -q 'resolvingSymlinksInPath' "$path_safety"
rg -q 'validateContents' "$validation"
rg -q 'WKWebExtension\.MatchPattern' "$host_matcher"
rg -q 'messages\.json' "$localization"
rg -q 'SHA256\.hash' "$fingerprint"
rg -q 'iconCandidates' "$icons"
rg -q 'activationSummary' "$semantics"
rg -q 'existingValidatedPath' "$options"

if rg -n 'import (WebKit|CryptoKit|OSLog)|InstalledExtension' "$url_identity"; then
  echo 'error: extension URL identity absorbed runtime, logging, or catalog policy' >&2
  exit 1
fi
if rg -n 'import (WebKit|CryptoKit|OSLog)' "$display_name" "$icons" "$semantics"; then
  echo 'error: pure extension identity/manifest roles gained runtime or logging dependencies' >&2
  exit 1
fi
if rg -n 'WKWebExtension|InstalledExtension|SHA256|messages\.json' "$path_safety"; then
  echo 'error: path-safety role absorbed unrelated extension semantics' >&2
  exit 1
fi
if rg -n 'resolvingSymlinksInPath|WKWebExtension|InstalledExtension' "$fingerprint"; then
  echo 'error: fingerprint role absorbed path/runtime/catalog policy' >&2
  exit 1
fi

echo 'extension utility role boundary passed'
