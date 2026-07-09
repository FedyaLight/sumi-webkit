#!/usr/bin/env bash
# Domain isolation boundary — Phase 7 enforcement without full SPM target split.
#
# Pure domain files must stay Foundation-only (no SwiftUI / AppKit / WebKit).
# Expand DOMAIN_FILES as Models/Common types are peeled off UI/runtime.
# Eventual SPM shape: SumiDomain → SumiWebRuntime → SumiAppUI.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

DOMAIN_FILES=(
  "Sumi/Models/Profile/SumiProfileIcon.swift"
  "Sumi/Common/SumiURLCore/SumiSiteNormalizer.swift"
  "Sumi/Utils/SumiURLNormalization.swift"
  "Sumi/ContentBlocking/SumiProtectionSiteNormalizer.swift"
  "Sumi/Permissions/SumiPermissionFailClosedMapper.swift"
  "Sumi/Permissions/SumiPermissionSecurityContextBuilder.swift"
)

forbidden_pattern='^import (SwiftUI|AppKit|WebKit)\b'
failures=0

printf '%s\n' 'Domain isolation boundary guardrail'
printf '%s\n' '----------------------------------'

for file in "${DOMAIN_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: domain file missing: %s\n' "$file" >&2
    failures=$((failures + 1))
    continue
  fi
  if rg -n "$forbidden_pattern" "$file" >/dev/null 2>&1; then
    printf 'error: domain file imports UI/runtime framework: %s\n' "$file" >&2
    rg -n "$forbidden_pattern" "$file" >&2 || true
    failures=$((failures + 1))
  else
    printf 'ok  %s\n' "$file"
  fi
done

# Models must not grow new SwiftUI Views (ProfileIconView already moved out).
if rg -n 'struct\s+\w+:\s*View\b' -g '*.swift' Sumi/Models >/dev/null 2>&1; then
  printf 'error: SwiftUI View types must not live under Sumi/Models:\n' >&2
  rg -n 'struct\s+\w+:\s*View\b' -g '*.swift' Sumi/Models >&2 || true
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  exit 1
fi

printf '\ndomain isolation boundary audit passed\n'
