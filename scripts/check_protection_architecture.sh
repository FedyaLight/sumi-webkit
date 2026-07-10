#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

domain_values="Packages/SumiDomain/Sources/SumiDomain/ContentBlocking/SumiProtectionValues.swift"
coordinator="Sumi/ContentBlocking/SumiProtectionCoordinator.swift"

check_max_lines() {
  local file="$1"
  local maximum="$2"
  if [[ ! -f "$file" ]]; then
    echo "error: missing protection architecture component: $file" >&2
    exit 1
  fi

  local actual
  actual="$(wc -l < "$file" | tr -d ' ')"
  if (( actual > maximum )); then
    echo "error: $file grew beyond its protection role ($actual > $maximum LOC)" >&2
    exit 1
  fi
}

check_max_lines "$domain_values" 100
check_max_lines Sumi/ContentBlocking/SumiProtectionLevel+App.swift 80
check_max_lines Sumi/ContentBlocking/SumiProtectionRulePlan.swift 120
check_max_lines Sumi/ContentBlocking/SumiProtectionNormalTabDecision.swift 50
check_max_lines Sumi/ContentBlocking/SumiProtectionApplicationResult.swift 60
check_max_lines Sumi/ContentBlocking/SumiProtectionSettings.swift 100
# Phase A retains orchestration here. Later phases may lower or retire this cap.
check_max_lines "$coordinator" 420

if rg -n '^(enum|struct|final class) SumiProtection(RulePlan|NormalTabDecision|ApplyOutcome|Settings)\b' "$coordinator" >/dev/null; then
  echo "error: protection model/settings responsibility returned to the coordinator" >&2
  exit 1
fi

for value_type in \
  SumiProtectionLevel \
  SumiProtectionGroupKind \
  SumiProtectionAttachmentState \
  SumiProtectionReloadRequirement; do
  declaration_count="$(rg -n "^public (enum|struct) ${value_type}\\b" Packages/SumiDomain/Sources --glob '*.swift' | wc -l | tr -d ' ')"
  if [[ "$declaration_count" != "1" ]]; then
    echo "error: ${value_type} must have one SumiDomain declaration, found $declaration_count" >&2
    exit 1
  fi

  if rg -n "^(public |internal |private |fileprivate )?(enum|struct|class|final class) ${value_type}\\b" App Sumi --glob '*.swift' >/dev/null; then
    echo "error: ${value_type} was redeclared in the application target" >&2
    exit 1
  fi
done

if rg -n '^import (AppKit|Combine|OSLog|SwiftData|WebKit)|Adblock|WK[A-Z]|UserDefaults' "$domain_values" >/dev/null; then
  echo "error: pure protection values gained app, persistence, diagnostics, or WebKit dependencies" >&2
  exit 1
fi

rg -q 'public var requestedGroups: \[SumiProtectionGroupKind\]' "$domain_values"
rg -q 'var displayTitle: String' Sumi/ContentBlocking/SumiProtectionLevel+App.swift
rg -q 'var preferredBundleProfileId: String?' Sumi/ContentBlocking/SumiProtectionLevel+App.swift
rg -q 'var adblockRuleGroupKinds: Set<AdblockCompiledRuleGroupKind>' Sumi/ContentBlocking/SumiProtectionLevel+App.swift

echo "Protection architecture guard passed"
