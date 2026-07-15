#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  guard_record_failure "$message: $matches"
}

singleton_hits="$(
  guard_capture_matches \
    '\bSumiFaviconProductionSystem\b|\bproductionFavicon(System|Service|Capabilities)\b' \
    -g '*.swift' App Sumi SumiTests
)"
fail_matches "favicon production singleton or alias reintroduced" "$singleton_hits"

static_authority_hits="$(
  guard_capture_matches \
    'static (let|var) (current|shared).*SumiFavicon|SumiFavicon.*static (let|var) (current|shared)' \
    -g '*.swift' Sumi/Favicons
)"
fail_matches "favicon runtime recovered shared/current authority" "$static_authority_hits"

default_live_hits="$(
  guard_capture_matches \
    'fetcher: any SumiFaviconNetworkFetching\s*=|imageReader: any BrowserFaviconImageReading\s*=|liveDiscovery: any BrowserFaviconLiveDiscoveryIngesting\s*=' \
    -g '*.swift' Sumi App
)"
fail_matches "favicon capability or network dependency hidden behind a default" "$default_live_hits"

late_lookup_hits="$(
  guard_capture_matches \
    '\bTabDependencyDataServices\b|attachDataServicesProvider|dataServices:.*TabDependency|dataServices: \{ \[weak browserManager\]' \
    -g '*.swift' \
    Sumi/Models/Tab \
    Sumi/Managers/BrowserManager/TabBrowserRuntimeFactory.swift \
    Sumi/Managers/BrowserManager/TabBrowserHostServicesRuntimeFactory.swift
)"
fail_matches "tab favicon authority recovered BrowserManager late lookup" "$late_lookup_hits"

browser_default_hits="$(
  guard_capture_matches \
    'dataServices: BrowserManagerDataServices\s*=' \
    -g '*.swift' Sumi/Managers/BrowserManager
)"
fail_matches "production BrowserManager construction hides data services" "$browser_default_hits"

production_construction_hits=''
production_construction_candidates="$(
  guard_capture_matches \
    'SumiFaviconSystem\(|SumiFaviconNetworkClient\(\)|BrowserManagerDataServices\.production\(' \
    -g '*.swift' App Sumi
)"
while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  [[ "$match" == App/SumiApp.swift:* ]] && continue
  production_construction_hits+="$match"$'\n'
done <<< "$production_construction_candidates"
fail_matches "live favicon construction escaped SumiApp" "$production_construction_hits"

guard_exact \
  'SumiApp favicon-system construction authority' \
  "$(guard_count_matches 'SumiFaviconSystem\(' App/SumiApp.swift)" \
  1
guard_exact \
  'SumiApp production data-services authority' \
  "$(guard_count_matches 'BrowserManagerDataServices\.production\(' App/SumiApp.swift)" \
  1

guard_finish 'favicon production ownership guard'
