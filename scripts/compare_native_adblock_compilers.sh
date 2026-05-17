#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT}/.build/adblock-native-compiler-compare"
SAFARI_CONVERTER_LIB_DIR="${SAFARI_CONVERTER_LIB_DIR:-${WORK_DIR}/SafariConverterLib}"
RUST_MANIFEST="${ROOT}/Vendor/Brave/AdblockRustAdapter/Cargo.toml"
RUST_HELPER="${ROOT}/Vendor/Brave/AdblockRustAdapter/target/debug/sumi-adblock-rust-adapter"
SWIFT_HARNESS_SOURCE="${ROOT}/scripts/adblock_safari_converter_compare_main.swift"

PROFILE="current"
PAGE_URL="https://adblock.turtlecute.org/"
RUN_PAGE_TEST=1

LIST_IDS=()
LIST_URLS=()
LIST_GROUPS=()
LIST_CATEGORIES=()

usage() {
  cat <<'USAGE'
Usage:
  scripts/compare_native_adblock_compilers.sh [--profile NAME] [--page-url URL|--no-page] [filter-list-url-or-file ...]

Compares Sumi's current adblock-rust native compiler helper against an
experimental AdGuard SafariConverterLib native harness on the same selected
inputs. SafariConverterLib is used only from a script-managed local checkout.

Named profiles:
  current, currentDefault
      EasyList, matching Sumi's production default list selection.
  light
      EasyList, explicit low-overlap native sample.
  balanced, clean-balanced, adguard-ads-only
      AdGuard Base + AdGuard Mobile Ads.
  high
      AdGuard Base + Mobile Ads + Annoyances.
  adguard-ads-privacy
      AdGuard Base + Mobile Ads + Tracking Protection + URL Tracking.
  reference-adguard, adguard-max
      AdGuard Base + Mobile Ads + Tracking Protection + URL Tracking + Annoyances.

The SafariConverterLib harness groups lists by neutral categories:
  generalAds, privacy, annoyances, regional, custom
Each group is converted separately, split into network/nativeCSS shards, filtered
with Sumi's native CSS safety policy, and validated transactionally with WebKit.

Set SAFARI_CONVERTER_LIB_DIR to an existing SafariConverterLib checkout to avoid
the script-managed clone under .build/.
USAGE
}

set_profile_lists() {
  case "$1" in
    current|currentDefault|light)
      LIST_IDS=("easylist")
      LIST_URLS=("https://easylist.to/easylist/easylist.txt")
      LIST_GROUPS=("generalAds")
      LIST_CATEGORIES=("baseAds")
      ;;
    balanced|clean-balanced|adguard-ads-only)
      LIST_IDS=("adguard-base" "adguard-mobile-ads")
      LIST_URLS=(
        "https://filters.adtidy.org/extension/chromium/filters/2.txt"
        "https://filters.adtidy.org/extension/chromium/filters/11.txt"
      )
      LIST_GROUPS=("generalAds" "generalAds")
      LIST_CATEGORIES=("baseAds" "baseAds")
      ;;
    high)
      LIST_IDS=("adguard-base" "adguard-mobile-ads" "adguard-annoyances")
      LIST_URLS=(
        "https://filters.adtidy.org/extension/chromium/filters/2.txt"
        "https://filters.adtidy.org/extension/chromium/filters/11.txt"
        "https://filters.adtidy.org/extension/chromium/filters/14.txt"
      )
      LIST_GROUPS=("generalAds" "generalAds" "annoyances")
      LIST_CATEGORIES=("baseAds" "baseAds" "annoyances")
      ;;
    adguard-ads-privacy)
      LIST_IDS=(
        "adguard-base"
        "adguard-mobile-ads"
        "adguard-tracking-protection"
        "adguard-url-tracking"
      )
      LIST_URLS=(
        "https://filters.adtidy.org/extension/chromium/filters/2.txt"
        "https://filters.adtidy.org/extension/chromium/filters/11.txt"
        "https://filters.adtidy.org/extension/chromium/filters/3.txt"
        "https://filters.adtidy.org/windows/filters/17.txt"
      )
      LIST_GROUPS=("generalAds" "generalAds" "privacy" "privacy")
      LIST_CATEGORIES=("baseAds" "baseAds" "privacyOverlap" "privacyOverlap")
      ;;
    reference-adguard|adguard-max)
      LIST_IDS=(
        "adguard-base"
        "adguard-mobile-ads"
        "adguard-tracking-protection"
        "adguard-url-tracking"
        "adguard-annoyances"
      )
      LIST_URLS=(
        "https://filters.adtidy.org/extension/chromium/filters/2.txt"
        "https://filters.adtidy.org/extension/chromium/filters/11.txt"
        "https://filters.adtidy.org/extension/chromium/filters/3.txt"
        "https://filters.adtidy.org/windows/filters/17.txt"
        "https://filters.adtidy.org/extension/chromium/filters/14.txt"
      )
      LIST_GROUPS=("generalAds" "generalAds" "privacy" "privacy" "annoyances")
      LIST_CATEGORIES=("baseAds" "baseAds" "privacyOverlap" "privacyOverlap" "annoyances")
      ;;
    *)
      echo "Unknown profile: $1" >&2
      exit 2
      ;;
  esac
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --profile)
      PROFILE="${2:?missing profile name}"
      shift 2
      ;;
    --page-url)
      PAGE_URL="${2:?missing page URL}"
      RUN_PAGE_TEST=1
      shift 2
      ;;
    --no-page)
      RUN_PAGE_TEST=0
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

set_profile_lists "${PROFILE}"

if [[ "$#" -gt 0 ]]; then
  PROFILE="custom"
  LIST_URLS=("$@")
  LIST_IDS=()
  LIST_GROUPS=()
  LIST_CATEGORIES=()
  for source in "${LIST_URLS[@]}"; do
    LIST_IDS+=("custom-$(printf '%s' "${source}" | shasum -a 256 | awk '{print substr($1,1,8)}')")
    LIST_GROUPS+=("custom")
    LIST_CATEGORIES+=("custom")
  done
fi

mkdir -p "${WORK_DIR}/lists" "${WORK_DIR}/SafariConverterCompare"
PROFILE_SLUG="$(printf '%s' "${PROFILE}" | tr -c '[:alnum:]._-' '-')"

if [[ ! -d "${SAFARI_CONVERTER_LIB_DIR}/.git" ]]; then
  rm -rf "${SAFARI_CONVERTER_LIB_DIR}"
  git clone --depth 1 --branch v4.2.2 https://github.com/AdguardTeam/SafariConverterLib.git "${SAFARI_CONVERTER_LIB_DIR}"
fi

cargo build --manifest-path "${RUST_MANIFEST}" >/dev/null

COMBINED="${WORK_DIR}/${PROFILE_SLUG}-combined.txt"
METADATA="${WORK_DIR}/${PROFILE_SLUG}-comparison-metadata.json"
GROUP_METADATA="${WORK_DIR}/${PROFILE_SLUG}-group-metadata.json"
: >"${COMBINED}"
LIST_LOCAL_PATHS=()
for index in "${!LIST_URLS[@]}"; do
  source="${LIST_URLS[$index]}"
  name="$(printf '%s' "${source}" | shasum -a 256 | awk '{print substr($1,1,16)}')"
  destination="${WORK_DIR}/lists/${name}.txt"
  if [[ "${source}" =~ ^https?:// ]]; then
    curl -fsSL "${source}" -o "${destination}"
  else
    cp "${source}" "${destination}"
  fi
  printf '\n! source: %s\n' "${source}" >>"${COMBINED}"
  cat "${destination}" >>"${COMBINED}"
  printf '\n' >>"${COMBINED}"
  LIST_LOCAL_PATHS+=("${destination}")
done

/usr/bin/python3 - "$METADATA" "$GROUP_METADATA" "$PROFILE" \
  "${LIST_IDS[@]}" -- "${LIST_GROUPS[@]}" -- "${LIST_CATEGORIES[@]}" -- "${LIST_LOCAL_PATHS[@]}" <<'PY'
import json
import pathlib
import sys

metadata_path, group_metadata_path, profile, *rest = sys.argv[1:]
first = rest.index("--")
second = rest.index("--", first + 1)
third = rest.index("--", second + 1)
ids = rest[:first]
groups = rest[first + 1:second]
categories = rest[second + 1:third]
paths = rest[third + 1:]
lists = []
grouped = {}
for identifier, group, category, raw_path in zip(ids, groups, categories, paths):
    path = pathlib.Path(raw_path)
    data = path.read_bytes()
    text = data.decode("utf-8", errors="replace")
    approximate_rule_count = sum(
        1 for line in text.splitlines()
        if line.strip() and not line.lstrip().startswith(("!", "["))
    )
    item = {
        "id": identifier,
        "group": group,
        "category": category,
        "path": str(path),
        "inputByteSize": len(data),
        "approximateInputRuleCount": approximate_rule_count,
    }
    lists.append(item)
    grouped.setdefault(group, {"sourceListIDs": [], "sourceCategories": [], "paths": []})
    grouped[group]["sourceListIDs"].append(identifier)
    grouped[group]["sourceCategories"].append(category)
    grouped[group]["paths"].append(str(path))
payload = {
    "profile": profile,
    "inputListIDs": ids,
    "inputLists": lists,
    "inputByteSize": sum(item["inputByteSize"] for item in lists),
    "approximateInputRuleCount": sum(item["approximateInputRuleCount"] for item in lists),
    "trackingProtectionState": "off",
    "cosmeticMode": "nativeCSS",
    "enhancedRuntimeState": "off",
}
pathlib.Path(metadata_path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
pathlib.Path(group_metadata_path).write_text(json.dumps(grouped, indent=2, sort_keys=True) + "\n")
PY

SWIFT_PACKAGE="${WORK_DIR}/SafariConverterCompare"
cat >"${SWIFT_PACKAGE}/Package.swift" <<SWIFT
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SafariConverterCompare",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "${SAFARI_CONVERTER_LIB_DIR}")
    ],
    targets: [
        .executableTarget(
            name: "SafariConverterCompare",
            dependencies: [
                .product(name: "ContentBlockerConverter", package: "SafariConverterLib")
            ]
        )
    ]
)
SWIFT

mkdir -p "${SWIFT_PACKAGE}/Sources/SafariConverterCompare"
cp "${SWIFT_HARNESS_SOURCE}" "${SWIFT_PACKAGE}/Sources/SafariConverterCompare/main.swift"
(cd "${SWIFT_PACKAGE}" && swift build -c release >/dev/null)
(cd "${SWIFT_PACKAGE}" && swift run -c release SafariConverterCompare --safety-self-test >"${WORK_DIR}/${PROFILE_SLUG}-safari-harness-self-test.json")

parse_time_json() {
  /usr/bin/python3 - "$1" <<'PY'
import json
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(errors="replace") if pathlib.Path(sys.argv[1]).exists() else ""
def number_for(label):
    pattern = re.compile(r"^\s*(\d+)\s+" + re.escape(label) + r"\s*$", re.MULTILINE)
    match = pattern.search(text)
    return int(match.group(1)) if match else None
payload = {
    "timeRealSeconds": None,
    "maximumResidentSetSizeBytes": number_for("maximum resident set size"),
    "peakMemoryFootprintBytes": number_for("peak memory footprint"),
}
real_match = re.search(r"^real\s+([0-9.]+)$", text, re.MULTILINE)
if real_match:
    payload["timeRealSeconds"] = float(real_match.group(1))
print(json.dumps(payload, sort_keys=True))
PY
}

RUST_RAW="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-output.json"
RUST_REPORT="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-report.json"
RUST_NETWORK_JSON="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-network-webkit.json"
RUST_NATIVE_CSS_UNSAFE_JSON="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-native-css-webkit-unsafe.json"
RUST_NATIVE_CSS_JSON="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-native-css-webkit.json"
RUST_NATIVE_CSS_SAFETY_REPORT="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-native-css-safety-report.json"
RUST_STDERR="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-stderr.txt"
RUST_TIME="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-time.txt"
RUST_SHARD_DIR="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-shards"
RUST_SHARD_REPORT="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-shard-report.json"
RUST_WEBKIT_PLAN="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-webkit-plan.json"
RUST_WEBKIT_REPORT="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-webkit-page-report.json"

SAFARI_GROUP_DIR="${WORK_DIR}/${PROFILE_SLUG}-safari-converter-groups"
SAFARI_SHARD_DIR="${WORK_DIR}/${PROFILE_SLUG}-safari-converter-shards"
SAFARI_GROUPED_REPORT="${WORK_DIR}/${PROFILE_SLUG}-safari-converter-grouped-report.json"
SAFARI_WEBKIT_PLAN="${WORK_DIR}/${PROFILE_SLUG}-safari-converter-webkit-plan.json"
SAFARI_WEBKIT_REPORT="${WORK_DIR}/${PROFILE_SLUG}-safari-converter-webkit-page-report.json"

rm -rf "${RUST_SHARD_DIR}" "${SAFARI_GROUP_DIR}" "${SAFARI_SHARD_DIR}"
mkdir -p "${RUST_SHARD_DIR}" "${SAFARI_GROUP_DIR}" "${SAFARI_SHARD_DIR}"

START_NS="$(date +%s%N)"
set +e
/usr/bin/time -lp -o "${RUST_TIME}" "${RUST_HELPER}" <"${COMBINED}" >"${RUST_RAW}" 2>"${RUST_STDERR}"
RUST_STATUS="$?"
set -e
END_NS="$(date +%s%N)"
RUST_MS="$(( (END_NS - START_NS) / 1000000 ))"

if [[ "${RUST_STATUS}" -eq 0 ]]; then
  /usr/bin/python3 - "$RUST_RAW" "$RUST_NETWORK_JSON" "$RUST_NATIVE_CSS_UNSAFE_JSON" <<'PY'
import json
import sys

raw_path, network_path, css_path = sys.argv[1:4]
with open(raw_path, "r", encoding="utf-8") as handle:
    raw = json.load(handle)
with open(network_path, "w", encoding="utf-8") as handle:
    json.dump(raw.get("network", []), handle, ensure_ascii=False, separators=(",", ":"))
with open(css_path, "w", encoding="utf-8") as handle:
    json.dump(raw.get("native_cosmetic_css", []), handle, ensure_ascii=False, separators=(",", ":"))
PY
  (cd "${SWIFT_PACKAGE}" && swift run -c release SafariConverterCompare \
    --sanitize-json \
    --report-path "${RUST_NATIVE_CSS_SAFETY_REPORT}" \
    <"${RUST_NATIVE_CSS_UNSAFE_JSON}" >"${RUST_NATIVE_CSS_JSON}")

  /usr/bin/python3 - "$RUST_RAW" "$RUST_NETWORK_JSON" "$RUST_NATIVE_CSS_JSON" "$RUST_NATIVE_CSS_SAFETY_REPORT" \
    "$RUST_SHARD_DIR" "$RUST_SHARD_REPORT" "$RUST_REPORT" "$RUST_MS" "$(parse_time_json "${RUST_TIME}")" <<'PY'
import hashlib
import json
import pathlib
import sys

(
    raw_path,
    network_path,
    css_path,
    safety_path,
    shard_dir,
    shard_report_path,
    rust_report_path,
    elapsed_ms,
    time_json,
) = sys.argv[1:10]
raw = json.loads(pathlib.Path(raw_path).read_text())
network = json.loads(pathlib.Path(network_path).read_text())
css = json.loads(pathlib.Path(css_path).read_text())
safety = json.loads(pathlib.Path(safety_path).read_text())
time_metrics = json.loads(time_json)
unsupported = raw.get("unsupported_or_ignored", [])
max_rules = 25_000
max_bytes = 3_000_000
shard_dir_path = pathlib.Path(shard_dir)

def encode(rules):
    return json.dumps(rules, ensure_ascii=False, separators=(",", ":"))

def chunk(rules):
    chunks = []
    current = []
    current_bytes = 2
    for rule in rules:
        encoded_rule = json.dumps(rule, ensure_ascii=False, separators=(",", ":"))
        separator = 0 if not current else 1
        if current and (len(current) >= max_rules or current_bytes + separator + len(encoded_rule.encode("utf-8")) > max_bytes):
            chunks.append(current)
            current = []
            current_bytes = 2
            separator = 0
        current.append(rule)
        current_bytes += separator + len(encoded_rule.encode("utf-8"))
    if current:
        chunks.append(current)
    return chunks

def write_group(kind, rules):
    output = []
    for index, shard_rules in enumerate(chunk(rules), start=1):
        encoded = encode(shard_rules)
        digest = hashlib.sha256(encoded.encode("utf-8")).hexdigest()[:12]
        identifier = f"sumi.adblock.adblockRust.combined.{kind}.{index:04d}.{digest}"
        path = shard_dir_path / f"{kind}-{index:04d}.json"
        path.write_text(encoded)
        output.append(
            {
                "id": identifier,
                "groupID": "combined",
                "kind": kind,
                "path": str(path),
                "ruleCount": len(shard_rules),
                "jsonSizeBytes": len(encoded.encode("utf-8")),
                "webKitCompileSucceeded": None,
            }
        )
    return output

network_shards = write_group("network", network)
native_css_shards = write_group("nativeCSS", css)
all_shards = network_shards + native_css_shards
shard_report = {
    "strategy": {
        "maxRulesPerShard": max_rules,
        "maxJSONBytesPerShard": max_bytes,
    },
    "networkShards": network_shards,
    "nativeCSSShards": native_css_shards,
    "networkShardCount": len(network_shards),
    "nativeCSSShardCount": len(native_css_shards),
    "largestShardJSONBytes": max((item["jsonSizeBytes"] for item in all_shards), default=0),
    "allShardWebKitCompileSucceeded": None,
}
report = {
    "compiler": "adblock-rust",
    "integrationStatus": "in-app-production-default",
    "profile": None,
    "conversionSucceeded": True,
    "version": "adblock-rust-adapter/0.1.0 adblock-rust/0.12.5",
    "groupingModel": "current-sumi-combined-output",
    "inputRuleCount": len(raw.get("used_rules", [])) + len(unsupported),
    "outputRuleCount": len(network),
    "networkRuleCount": len(network),
    "nativeCSSRuleCount": len(css),
    "unsupportedOrAdvancedRuleCount": len(unsupported),
    "unsafeNativeCSSFilteredRuleCount": safety["unsafeNativeCSSFilteredRuleCount"],
    "droppedUnsafeNativeCSSRuleCount": safety["droppedUnsafeNativeCSSRuleCount"],
    "diagnostics": [
        f"enhancedResourceCandidates={len(raw.get('enhanced_resource_candidates', []))}",
        f"unsupportedOrIgnored={len(unsupported)}",
        f"nativeCSSSafetyFiltered={safety['unsafeNativeCSSFilteredRuleCount']}",
    ],
    "webKitCompileSucceeded": None,
    "jsonSizeBytes": sum(item["jsonSizeBytes"] for item in all_shards),
    "conversionTimeMilliseconds": float(elapsed_ms),
    "ruleCapHit": False,
    "discardedRuleCount": 0,
    "networkShardCount": len(network_shards),
    "nativeCSSShardCount": len(native_css_shards),
    "largestShardJSONBytes": max((item["jsonSizeBytes"] for item in all_shards), default=0),
    "timeMetrics": time_metrics,
    "shards": all_shards,
}
pathlib.Path(shard_report_path).write_text(json.dumps(shard_report, indent=2, sort_keys=True) + "\n")
pathlib.Path(rust_report_path).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
else
  /usr/bin/python3 - "$COMBINED" "$RUST_STDERR" "$RUST_REPORT" "$RUST_STATUS" "$RUST_MS" "$(parse_time_json "${RUST_TIME}")" <<'PY'
import json
import sys

combined_path, stderr_path, report_path, status, elapsed_ms, time_json = sys.argv[1:7]
with open(combined_path, "r", encoding="utf-8") as handle:
    input_rule_count = sum(1 for line in handle if line.strip() and not line.startswith("!"))
with open(stderr_path, "r", encoding="utf-8") as handle:
    stderr_lines = [line.strip() for line in handle if line.strip()]
report = {
    "compiler": "adblock-rust",
    "integrationStatus": "in-app-production-default",
    "conversionSucceeded": False,
    "version": "adblock-rust-adapter/0.1.0 adblock-rust/0.12.5",
    "groupingModel": "current-sumi-combined-output",
    "inputRuleCount": input_rule_count,
    "outputRuleCount": 0,
    "networkRuleCount": 0,
    "nativeCSSRuleCount": 0,
    "unsupportedOrAdvancedRuleCount": 0,
    "unsafeNativeCSSFilteredRuleCount": 0,
    "droppedUnsafeNativeCSSRuleCount": 0,
    "diagnostics": [f"processExitStatus={status}", *stderr_lines[:4]],
    "webKitCompileSucceeded": False,
    "jsonSizeBytes": 0,
    "conversionTimeMilliseconds": float(elapsed_ms),
    "ruleCapHit": False,
    "discardedRuleCount": 0,
    "timeMetrics": json.loads(time_json),
    "shards": [],
}
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
fi

/usr/bin/python3 - "$GROUP_METADATA" "$SAFARI_GROUP_DIR" "$PROFILE_SLUG" <<'PY'
import json
import pathlib
import sys

metadata_path, group_dir, profile_slug = sys.argv[1:4]
metadata = json.loads(pathlib.Path(metadata_path).read_text())
group_dir_path = pathlib.Path(group_dir)
for group_id, item in metadata.items():
    path = group_dir_path / f"{profile_slug}-{group_id}.txt"
    with path.open("w", encoding="utf-8") as output:
        for source_path in item["paths"]:
            output.write(f"\n! grouped source: {source_path}\n")
            output.write(pathlib.Path(source_path).read_text(encoding="utf-8", errors="replace"))
            output.write("\n")
    item["combinedPath"] = str(path)
pathlib.Path(metadata_path).write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
PY

SAFARI_GROUP_IDS=()
while IFS= read -r group_id; do
  SAFARI_GROUP_IDS+=("${group_id}")
done < <(/usr/bin/python3 - "$GROUP_METADATA" <<'PY'
import json
import pathlib
import sys
metadata = json.loads(pathlib.Path(sys.argv[1]).read_text())
for key in sorted(metadata):
    print(key)
PY
)

SAFARI_GROUP_REPORTS=()
for group_id in "${SAFARI_GROUP_IDS[@]}"; do
  group_input="$(/usr/bin/python3 - "$GROUP_METADATA" "$group_id" <<'PY'
import json
import pathlib
import sys
metadata = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(metadata[sys.argv[2]]["combinedPath"])
PY
)"
  group_ids="$(/usr/bin/python3 - "$GROUP_METADATA" "$group_id" <<'PY'
import json
import pathlib
import sys
metadata = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(",".join(metadata[sys.argv[2]]["sourceListIDs"]))
PY
)"
  group_categories="$(/usr/bin/python3 - "$GROUP_METADATA" "$group_id" <<'PY'
import json
import pathlib
import sys
metadata = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(",".join(sorted(set(metadata[sys.argv[2]]["sourceCategories"]))))
PY
)"
  report_path="${SAFARI_GROUP_DIR}/${PROFILE_SLUG}-${group_id}-report.json"
  time_path="${SAFARI_GROUP_DIR}/${PROFILE_SLUG}-${group_id}-time.txt"
  set +e
  /usr/bin/time -lp -o "${time_path}" \
    "${SWIFT_PACKAGE}/.build/release/SafariConverterCompare" \
    --convert-safari-group \
    --profile "${PROFILE}" \
    --group-id "${group_id}" \
    --source-list-ids "${group_ids}" \
    --source-categories "${group_categories}" \
    --generation-id "${PROFILE_SLUG}" \
    --shard-dir "${SAFARI_SHARD_DIR}" \
    <"${group_input}" >"${report_path}"
  status="$?"
  set -e
  if [[ "${status}" -ne 0 ]]; then
    echo "SafariConverterLib group conversion failed for ${group_id}" >&2
    exit "${status}"
  fi
  /usr/bin/python3 - "$report_path" "$(parse_time_json "${time_path}")" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["timeMetrics"] = json.loads(sys.argv[2])
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
  SAFARI_GROUP_REPORTS+=("${report_path}")
done

/usr/bin/python3 - "$SAFARI_GROUPED_REPORT" "${SAFARI_GROUP_REPORTS[@]}" <<'PY'
import json
import pathlib
import sys

output_path, *report_paths = sys.argv[1:]
groups = [json.loads(pathlib.Path(path).read_text()) for path in report_paths]
shards = [shard for group in groups for shard in group["shards"]]
network_shards = [shard for shard in shards if shard["kind"] == "network"]
native_css_shards = [shard for shard in shards if shard["kind"] == "nativeCSS"]
payload = {
    "compiler": "SafariConverterLib",
    "integrationStatus": "external-harness-only",
    "profile": groups[0]["profile"] if groups else None,
    "groupingModel": "experimentalAdGuardNative/grouped-by-category",
    "conversionSucceeded": all(group["conversionSucceeded"] for group in groups),
    "version": groups[0]["version"] if groups else None,
    "groups": groups,
    "groupCount": len(groups),
    "inputRuleCount": sum(group["inputRuleCount"] for group in groups),
    "outputRuleCount": sum(group["outputRuleCount"] for group in groups),
    "networkRuleCount": sum(group["networkRuleCount"] for group in groups),
    "nativeCSSRuleCount": sum(group["nativeCSSRuleCount"] for group in groups),
    "unsupportedOrAdvancedRuleCount": sum(group["unsupportedOrAdvancedRuleCount"] for group in groups),
    "unsafeNativeCSSFilteredRuleCount": sum(group["unsafeNativeCSSFilteredRuleCount"] for group in groups),
    "droppedUnsafeNativeCSSRuleCount": sum(group["droppedUnsafeNativeCSSRuleCount"] for group in groups),
    "jsonSizeBytes": sum(group["jsonSizeBytes"] for group in groups),
    "conversionTimeMilliseconds": sum(group["conversionTimeMilliseconds"] for group in groups),
    "ruleCapHit": any(group["ruleCapHit"] for group in groups),
    "discardedRuleCount": sum(group["discardedRuleCount"] for group in groups),
    "networkShardCount": len(network_shards),
    "nativeCSSShardCount": len(native_css_shards),
    "largestShardJSONBytes": max((shard["jsonSizeBytes"] for shard in shards), default=0),
    "webKitCompileSucceeded": None,
    "shards": shards,
}
pathlib.Path(output_path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

make_plan() {
  local compiler="$1"
  local report_path="$2"
  local plan_path="$3"
  /usr/bin/python3 - "$compiler" "$PROFILE" "$report_path" "$plan_path" <<'PY'
import json
import pathlib
import sys

compiler, profile, report_path, plan_path = sys.argv[1:5]
report = json.loads(pathlib.Path(report_path).read_text())
plan = {
    "compiler": compiler,
    "profile": profile,
    "trackingProtectionState": "off",
    "cosmeticMode": "nativeCSS",
    "enhancedRuntimeState": "off",
    "attachKinds": ["network", "nativeCSS"],
    "shards": [
        {
            "id": shard["id"],
            "groupID": shard.get("groupID"),
            "kind": shard["kind"],
            "path": shard["path"],
        }
        for shard in report.get("shards", [])
    ],
}
pathlib.Path(plan_path).write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
PY
}

if [[ "${RUST_STATUS}" -eq 0 ]]; then
  make_plan "adblock-rust" "$RUST_REPORT" "$RUST_WEBKIT_PLAN"
  if [[ "${RUN_PAGE_TEST}" -eq 1 ]]; then
    "${SWIFT_PACKAGE}/.build/release/SafariConverterCompare" \
      --webkit-plan \
      --plan-path "${RUST_WEBKIT_PLAN}" \
      --page-url "${PAGE_URL}" >"${RUST_WEBKIT_REPORT}"
  else
    "${SWIFT_PACKAGE}/.build/release/SafariConverterCompare" \
      --webkit-plan \
      --plan-path "${RUST_WEBKIT_PLAN}" >"${RUST_WEBKIT_REPORT}"
  fi
fi

make_plan "SafariConverterLib" "$SAFARI_GROUPED_REPORT" "$SAFARI_WEBKIT_PLAN"
if [[ "${RUN_PAGE_TEST}" -eq 1 ]]; then
  "${SWIFT_PACKAGE}/.build/release/SafariConverterCompare" \
    --webkit-plan \
    --plan-path "${SAFARI_WEBKIT_PLAN}" \
    --page-url "${PAGE_URL}" >"${SAFARI_WEBKIT_REPORT}"
else
  "${SWIFT_PACKAGE}/.build/release/SafariConverterCompare" \
    --webkit-plan \
    --plan-path "${SAFARI_WEBKIT_PLAN}" >"${SAFARI_WEBKIT_REPORT}"
fi

/usr/bin/python3 - "$METADATA" "$RUST_REPORT" "$RUST_SHARD_REPORT" "$RUST_WEBKIT_REPORT" "$SAFARI_GROUPED_REPORT" "$SAFARI_WEBKIT_REPORT" <<'PY'
import json
import pathlib
import sys

metadata_path, rust_report_path, rust_shard_report_path, rust_webkit_path, safari_report_path, safari_webkit_path = sys.argv[1:7]
metadata = json.loads(pathlib.Path(metadata_path).read_text())

def load_optional(path):
    p = pathlib.Path(path)
    return json.loads(p.read_text()) if p.exists() else None

def write(path, payload):
    pathlib.Path(path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")

rust = load_optional(rust_report_path)
rust_shards = load_optional(rust_shard_report_path)
rust_webkit = load_optional(rust_webkit_path)
safari = load_optional(safari_report_path)
safari_webkit = load_optional(safari_webkit_path)

if rust:
    rust.update(metadata)
    if rust_webkit:
        rust["webKitPageRun"] = rust_webkit
        rust["webKitCompileSucceeded"] = bool(rust_webkit["webKitCompileSucceeded"])
        rust["scorePercent"] = rust_webkit.get("scorePercent")
        rust["scoreText"] = rust_webkit.get("scoreText")
        rust["blankPageResult"] = rust_webkit.get("blankPageResult")
        if rust_shards:
            rust_shards["allShardWebKitCompileSucceeded"] = bool(rust_webkit["webKitCompileSucceeded"])
    write(rust_report_path, rust)
if rust_shards:
    write(rust_shard_report_path, rust_shards)

if safari:
    safari.update(metadata)
    if safari_webkit:
        safari["webKitPageRun"] = safari_webkit
        safari["webKitCompileSucceeded"] = bool(safari_webkit["webKitCompileSucceeded"])
        safari["scorePercent"] = safari_webkit.get("scorePercent")
        safari["scoreText"] = safari_webkit.get("scoreText")
        safari["blankPageResult"] = safari_webkit.get("blankPageResult")
    write(safari_report_path, safari)
PY

printf 'Wrote comparison reports:\n'
printf '  %s\n' "${RUST_REPORT}"
if [[ -f "${RUST_SHARD_REPORT}" ]]; then
  printf '  %s\n' "${RUST_SHARD_REPORT}"
fi
if [[ -f "${RUST_WEBKIT_REPORT}" ]]; then
  printf '  %s\n' "${RUST_WEBKIT_REPORT}"
fi
printf '  %s\n' "${SAFARI_GROUPED_REPORT}"
printf '  %s\n' "${SAFARI_WEBKIT_REPORT}"
