#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

retired='SumiProtectionBundleRemote|SumiRemoteAdblockBundle|SumiPreparedAdblockBundleResolver|SumiProtectionBundleUpdateStatusStore|case (remoteReleaseBundle|developmentBundle|embeddedBundle)|embeddedBundleURLProvider'
if rg -n "$retired" Sumi Packages/SumiDomain/Sources --glob '*.swift'; then
  echo "error: retired prepared/remote Adblock runtime returned" >&2
  exit 1
fi

if rg -n 'case protection' Packages/SumiDomain/Sources/SumiDomain/ContentBlocking --glob '*.swift'; then
  echo "error: retired Protection level returned" >&2
  exit 1
fi

if rg -n 'Timer|scheduledTimer|automatic update|background update' Sumi/ContentBlocking --glob '*.swift'; then
  echo "error: Adblock must not update or convert in the background" >&2
  exit 1
fi

for contract in \
  'Sumi/ContentBlocking/SumiSelectedFilterBundleBuilder.swift:buildFilterEngine' \
  'Sumi/ContentBlocking/SumiSelectedFilterBundleBuilder.swift:SumiRemoveParamRuleBuilder' \
  'Sumi/ContentBlocking/AdblockGenerationArchive.swift:ContentBlockingItemExchange.swap' \
  'Sumi/ContentBlocking/SumiAdBlockingModule.swift:private var runtimeLevel = SumiProtectionLevel.off'; do
  file="${contract%%:*}"
  pattern="${contract#*:}"
  rg -q -F "$pattern" "$file" || {
    echo "error: missing local Adblock contract in $file: $pattern" >&2
    exit 1
  }
done

echo "Adblock update architecture guard passed"
