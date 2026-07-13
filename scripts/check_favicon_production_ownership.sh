#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

singleton_hits="$(
  rg -n '\bSumiFaviconProductionSystem\b|\bproductionFavicon(System|Service|Capabilities)\b' \
    App Sumi SumiTests -g '*.swift' || true
)"
fail_matches "favicon production singleton or alias reintroduced" "$singleton_hits"

static_authority_hits="$(
  rg -n 'static (let|var) (current|shared).*SumiFavicon|SumiFavicon.*static (let|var) (current|shared)' \
    Sumi/Favicons -g '*.swift' || true
)"
fail_matches "favicon runtime recovered shared/current authority" "$static_authority_hits"

default_live_hits="$(
  rg -n 'fetcher: any SumiFaviconNetworkFetching\s*=|imageReader: any BrowserFaviconImageReading\s*=|liveDiscovery: any BrowserFaviconLiveDiscoveryIngesting\s*=' \
    Sumi App -g '*.swift' || true
)"
fail_matches "favicon capability or network dependency hidden behind a default" "$default_live_hits"

late_lookup_hits="$(
  rg -n '\bTabDependencyDataServices\b|attachDataServicesProvider|dataServices:.*TabDependency|dataServices: \{ \[weak browserManager\]' \
    Sumi/Models/Tab \
    Sumi/Managers/BrowserManager/TabBrowserRuntimeFactory.swift \
    Sumi/Managers/BrowserManager/TabBrowserHostServicesRuntimeFactory.swift \
    -g '*.swift' || true
)"
fail_matches "tab favicon authority recovered BrowserManager late lookup" "$late_lookup_hits"

browser_default_hits="$(
  rg -n 'dataServices: BrowserManagerDataServices\s*=' \
    Sumi/Managers/BrowserManager -g '*.swift' || true
)"
fail_matches "production BrowserManager construction hides data services" "$browser_default_hits"

production_construction_hits="$(
  rg -n 'SumiFaviconSystem\(|SumiFaviconNetworkClient\(\)|BrowserManagerDataServices\.production\(' \
    App Sumi -g '*.swift' \
    | rg -v '^App/SumiApp\.swift:' || true
)"
fail_matches "live favicon construction escaped SumiApp" "$production_construction_hits"

if [[ "$(rg -c 'SumiFaviconSystem\(' App/SumiApp.swift)" != "1" ]]; then
  printf 'error: SumiApp must construct exactly one favicon system\n' >&2
  status=1
fi

if [[ "$(rg -c 'BrowserManagerDataServices\.production\(' App/SumiApp.swift)" != "1" ]]; then
  printf 'error: SumiApp must install exactly one production favicon authority\n' >&2
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

echo "favicon production ownership guard passed"
