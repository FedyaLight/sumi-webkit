#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

runtime_paths=(App Sumi Settings SidebarChrome UI FloatingBar)
content_blocking_paths=(Sumi/ContentBlocking)

check_absent() {
  local label="$1"
  local pattern="$2"
  shift 2
  local matches

  matches="$(guard_capture_matches "$pattern" -g '*.swift' "$@")" || return
  if [[ -n "$matches" ]]; then
    guard_record_failure "$label: $matches"
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

tds_matches="$(
  guard_capture_matches \
    'trackerblocking/v6/current|macos-tds\.json' \
    -g '*.swift' "${runtime_paths[@]}"
)"
tds_violations=""
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  if [[ "$match" == *"sourceURL"* ]]; then
    continue
  fi
  tds_violations+="$match"$'\n'
done <<< "$tds_matches"
if [[ -n "$tds_violations" ]]; then
  guard_record_failure "DDG/TDS runtime list URL use: $tds_violations"
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

guard_finish 'prepared-bundle runtime boundary audit'
