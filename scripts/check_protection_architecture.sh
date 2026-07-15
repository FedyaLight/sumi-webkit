#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

domain_values="Packages/SumiDomain/Sources/SumiDomain/ContentBlocking/SumiProtectionValues.swift"
coordinator="Sumi/ContentBlocking/SumiProtectionCoordinator.swift"

line_budgets=(
  "$domain_values|100"
  "Sumi/ContentBlocking/SumiProtectionLevel+App.swift|80"
  "Sumi/ContentBlocking/SumiProtectionRulePlan.swift|120"
  "Sumi/ContentBlocking/SumiProtectionNormalTabDecision.swift|50"
  "Sumi/ContentBlocking/SumiProtectionApplicationResult.swift|60"
  "Sumi/ContentBlocking/SumiProtectionSettings.swift|100"
  "$coordinator|420"
)
for budget in "${line_budgets[@]}"; do
  file="${budget%%|*}"
  maximum="${budget#*|}"
  guard_require_file "$file"
  actual="$(guard_count_lines "$file")"
  if (( actual > maximum )); then
    echo "error: $file grew beyond its protection role ($actual > $maximum LOC)" >&2
    exit 1
  fi
done

coordinator_model_hits="$(
  guard_capture_matches '^(enum|struct|final class) SumiProtection(RulePlan|NormalTabDecision|ApplyOutcome|Settings)\b' "$coordinator"
)"
if [[ -n "$coordinator_model_hits" ]]; then
  echo "error: protection model/settings responsibility returned to the coordinator" >&2
  exit 1
fi

for value_type in \
  SumiProtectionLevel \
  SumiProtectionGroupKind \
  SumiProtectionAttachmentState \
  SumiProtectionReloadRequirement; do
  declaration_count="$(
    guard_count_matches "^public (enum|struct) ${value_type}\\b" \
      Packages/SumiDomain/Sources --glob '*.swift'
  )"
  if [[ "$declaration_count" != "1" ]]; then
    echo "error: ${value_type} must have one SumiDomain declaration, found $declaration_count" >&2
    exit 1
  fi

  app_declaration_count="$(
    guard_count_matches "^(public |internal |private |fileprivate )?(enum|struct|class|final class) ${value_type}\\b" \
      App Sumi --glob '*.swift'
  )"
  if (( app_declaration_count > 0 )); then
    echo "error: ${value_type} was redeclared in the application target" >&2
    exit 1
  fi
done

domain_dependency_count="$(
  guard_count_matches '^import (AppKit|Combine|OSLog|SwiftData|WebKit)|Adblock|WK[A-Z]|UserDefaults' \
    "$domain_values"
)"
if (( domain_dependency_count > 0 )); then
  echo "error: pure protection values gained app, persistence, diagnostics, or WebKit dependencies" >&2
  exit 1
fi

required_contracts=(
  "$domain_values|public var requestedGroups: \\[SumiProtectionGroupKind\\]"
  "Sumi/ContentBlocking/SumiProtectionLevel+App.swift|var displayTitle: String"
  "Sumi/ContentBlocking/SumiProtectionLevel+App.swift|var preferredBundleProfileId: String?"
  "Sumi/ContentBlocking/SumiProtectionLevel+App.swift|var adblockRuleGroupKinds: Set<AdblockCompiledRuleGroupKind>"
)
for contract in "${required_contracts[@]}"; do
  file="${contract%%|*}"
  pattern="${contract#*|}"
  contract_count="$(guard_count_matches "$pattern" "$file")"
  if (( contract_count == 0 )); then
    guard_record_failure "required protection contract is missing from $file: $pattern"
    exit 1
  fi
done

echo "Protection architecture guard passed"
