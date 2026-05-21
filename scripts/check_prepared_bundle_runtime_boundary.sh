#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

runtime_paths=(App Sumi Settings Navigation UI FloatingBar)
content_blocking_paths=(Sumi/ContentBlocking)
status=0

check_absent() {
  local label="$1"
  local pattern="$2"
  shift 2
  local matches

  matches="$(rg -n --glob '*.swift' -e "$pattern" "$@" || true)"
  if [[ -n "$matches" ]]; then
    printf 'disallowed %s:\n%s\n' "$label" "$matches" >&2
    status=1
  fi
}

check_absent \
  "TrackerRadarKit runtime import/use" \
  'TrackerRadarKit|ContentBlockerRulesBuilder' \
  "${runtime_paths[@]}"

check_absent \
  "browser-side tracking/adblock runtime generation" \
  'SumiTrackingProtection|SumiTrackingRuleListProvider|SumiTrackingRuleListPipeline|updateTrackerDataManually|runtimeGenerated|raw-list|raw list|tracking data set|tracker data|EasyList|EasyPrivacy|adblock-rust|adblock_rust|AdblockRustCompiler|sumi-adblock-rust-adapter' \
  "${runtime_paths[@]}"

tds_matches="$(rg -n --glob '*.swift' -e 'trackerblocking/v6/current|macos-tds\.json' "${runtime_paths[@]}" || true)"
tds_violations=""
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  if [[ "$match" == *"sourceURL"* ]]; then
    continue
  fi
  tds_violations+="$match"$'\n'
done <<< "$tds_matches"
if [[ -n "$tds_violations" ]]; then
  printf 'disallowed DDG/TDS runtime list URL use:\n%s' "$tds_violations" >&2
  status=1
fi

check_absent \
  "old adblock diagnostics/debug install API" \
  'SumiAdBlockingModuleStatus|SumiAdblockCurrentTabDiagnostics|SumiAdblockAttachmentDiagnostics|embeddedAdblockBundleSnapshot|installEmbeddedAdblockBundle|SumiEmbeddedAdblockBundleCatalog|requestEmbeddedBundleInstall|contentRuleListDefinitions\(for allowedKinds' \
  "${runtime_paths[@]}"

check_absent \
  "content-blocking userscript/runtime injection" \
  'WKUserScript|addUserScript|addScriptMessageHandler|WKWebExtension' \
  "${content_blocking_paths[@]}"

check_absent \
  "automatic background list update scheduling" \
  'Timer|scheduledTimer|automatic update|background update|stale tracker|stale ad' \
  "${content_blocking_paths[@]}"

if [[ "$status" -ne 0 ]]; then
  echo "prepared-bundle runtime boundary audit failed" >&2
  exit "$status"
fi

echo "prepared-bundle runtime boundary audit passed"
