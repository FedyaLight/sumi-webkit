#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT}/.build/adblock-native-compiler-compare"
SAFARI_CONVERTER_LIB_DIR="${SAFARI_CONVERTER_LIB_DIR:-${WORK_DIR}/SafariConverterLib}"
RUST_MANIFEST="${ROOT}/Vendor/Brave/AdblockRustAdapter/Cargo.toml"
RUST_HELPER="${ROOT}/Vendor/Brave/AdblockRustAdapter/target/debug/sumi-adblock-rust-adapter"

PROFILE="current"
LIST_IDS=("easylist")
LIST_URLS=("https://easylist.to/easylist/easylist.txt")

usage() {
  cat <<'USAGE'
Usage:
  scripts/compare_native_adblock_compilers.sh [--profile current|light|balanced|high|ora-like] [filter-list-url-or-file ...]

Compares Sumi's current adblock-rust native compiler helper against
AdGuard SafariConverterLib on the same selected list inputs. With no arguments,
it uses Sumi's current default profile (`easylist`).

Named profiles:
  current, light  easylist
  balanced        adguard-base + adguard-mobile-ads
  high            balanced + adguard-annoyances
  ora-like        balanced + tracking + URL tracking + annoyances

Set SAFARI_CONVERTER_LIB_DIR to an existing SafariConverterLib checkout to avoid
the script-managed clone under .build/.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--profile" ]]; then
  PROFILE="${2:?missing profile name}"
  shift 2
  case "${PROFILE}" in
    current|light)
      LIST_IDS=("easylist")
      LIST_URLS=("https://easylist.to/easylist/easylist.txt")
      ;;
    balanced)
      LIST_IDS=("adguard-base" "adguard-mobile-ads")
      LIST_URLS=(
        "https://filters.adtidy.org/extension/chromium/filters/2.txt"
        "https://filters.adtidy.org/extension/chromium/filters/11.txt"
      )
      ;;
    high)
      LIST_IDS=("adguard-base" "adguard-mobile-ads" "adguard-annoyances")
      LIST_URLS=(
        "https://filters.adtidy.org/extension/chromium/filters/2.txt"
        "https://filters.adtidy.org/extension/chromium/filters/11.txt"
        "https://filters.adtidy.org/extension/chromium/filters/14.txt"
      )
      ;;
    ora-like)
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
      ;;
    *)
      echo "Unknown profile: ${PROFILE}" >&2
      exit 2
      ;;
  esac
fi

if [[ "$#" -gt 0 ]]; then
  PROFILE="custom"
  LIST_URLS=("$@")
  LIST_IDS=()
  for source in "${LIST_URLS[@]}"; do
    LIST_IDS+=("custom-$(printf '%s' "${source}" | shasum -a 256 | awk '{print substr($1,1,8)}')")
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

/usr/bin/python3 - "$METADATA" "$PROFILE" "${LIST_IDS[@]}" -- "${LIST_LOCAL_PATHS[@]}" <<'PY'
import json
import pathlib
import sys

out_path, profile, *rest = sys.argv[1:]
split = rest.index("--")
ids = rest[:split]
paths = rest[split + 1 :]
lists = []
for identifier, raw_path in zip(ids, paths):
    data = pathlib.Path(raw_path).read_bytes()
    text = data.decode("utf-8", errors="replace")
    approximate_rule_count = sum(
        1 for line in text.splitlines()
        if line.strip() and not line.lstrip().startswith(("!", "["))
    )
    lists.append(
        {
            "id": identifier,
            "inputByteSize": len(data),
            "approximateInputRuleCount": approximate_rule_count,
        }
    )
payload = {
    "profile": profile,
    "inputListIDs": ids,
    "inputLists": lists,
    "inputByteSize": sum(item["inputByteSize"] for item in lists),
    "approximateInputRuleCount": sum(item["approximateInputRuleCount"] for item in lists),
}
pathlib.Path(out_path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
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
cat >"${SWIFT_PACKAGE}/Sources/SafariConverterCompare/main.swift" <<'SWIFT'
import ContentBlockerConverter
import Foundation
import WebKit

struct Report: Encodable {
    let compiler: String
    let integrationStatus: String
    let conversionSucceeded: Bool
    let version: String
    let inputRuleCount: Int
    let outputRuleCount: Int
    let nativeCSSRuleCount: Int
    let unsupportedOrAdvancedRuleCount: Int
    let diagnostics: [String]
    let webKitCompileSucceeded: Bool
    let jsonSizeBytes: Int
    let conversionTimeMilliseconds: Double
    let ruleCapHit: Bool
    let discardedRuleCount: Int
}

struct ValidationOutput: Encodable {
    let webKitCompileSucceeded: Bool
}

@main
enum Main {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.dropFirst().first == "--validate-json" {
            let json = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? "[]"
            let output = ValidationOutput(webKitCompileSucceeded: await compileWithWebKit(json))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(output))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        var input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        input.makeContiguousUTF8()
        let rules = input.components(separatedBy: .newlines)
        let started = Date()
        let result = ContentBlockerConverter().convertArray(
            rules: rules,
            safariVersion: .autodetect(),
            advancedBlocking: false
        )
        let elapsed = Date().timeIntervalSince(started) * 1000
        let webKitSucceeded = await compileWithWebKit(result.safariRulesJSON)
        let nativeCSSCount = result.safariRulesJSON.components(separatedBy: "\"css-display-none\"").count - 1
        let report = Report(
            compiler: "SafariConverterLib",
            integrationStatus: "external-harness-only",
            conversionSucceeded: true,
            version: ContentBlockerConverterVersion.library,
            inputRuleCount: result.sourceRulesCount,
            outputRuleCount: result.safariRulesCount,
            nativeCSSRuleCount: nativeCSSCount,
            unsupportedOrAdvancedRuleCount: result.errorsCount + result.advancedRulesCount + result.discardedSafariRules,
            diagnostics: [
                "sourceSafariCompatibleRules=\(result.sourceSafariCompatibleRulesCount)",
                "errors=\(result.errorsCount)",
                "advanced=\(result.advancedRulesCount)",
                "discarded=\(result.discardedSafariRules)"
            ],
            webKitCompileSucceeded: webKitSucceeded,
            jsonSizeBytes: result.safariRulesJSON.utf8.count,
            conversionTimeMilliseconds: elapsed,
            ruleCapHit: result.discardedSafariRules > 0,
            discardedRuleCount: result.discardedSafariRules
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    @MainActor
    private static func compileWithWebKit(_ json: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let identifier = "sumi.adblock.compare.safari.\(UUID().uuidString)"
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) { _, error in
                if error == nil {
                    WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { _ in
                        continuation.resume(returning: true)
                    }
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
SWIFT

RUST_RAW="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-output.json"
RUST_REPORT="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-report.json"
RUST_NETWORK_JSON="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-network-webkit.json"
RUST_NATIVE_CSS_JSON="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-native-css-webkit.json"
RUST_STDERR="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-stderr.txt"
RUST_NETWORK_WEBKIT_REPORT="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-network-webkit-report.json"
RUST_NATIVE_CSS_WEBKIT_REPORT="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-native-css-webkit-report.json"
RUST_SHARD_DIR="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-shards"
RUST_SHARD_REPORT="${WORK_DIR}/${PROFILE_SLUG}-adblock-rust-shard-dry-run-report.json"
SAFARI_REPORT="${WORK_DIR}/${PROFILE_SLUG}-safari-converter-report.json"
rm -f "${RUST_SHARD_REPORT}"

START_NS="$(date +%s%N)"
set +e
"${RUST_HELPER}" <"${COMBINED}" >"${RUST_RAW}" 2>"${RUST_STDERR}"
RUST_STATUS="$?"
set -e
END_NS="$(date +%s%N)"
RUST_MS="$(( (END_NS - START_NS) / 1000000 ))"

if [[ "${RUST_STATUS}" -eq 0 ]]; then
  /usr/bin/python3 - "$RUST_RAW" "$RUST_REPORT" "$RUST_NETWORK_JSON" "$RUST_NATIVE_CSS_JSON" "$RUST_MS" <<'PY'
import json
import sys

raw_path, report_path, network_path, native_css_path, elapsed_ms = (
    sys.argv[1],
    sys.argv[2],
    sys.argv[3],
    sys.argv[4],
    float(sys.argv[5]),
)
with open(raw_path, "r", encoding="utf-8") as handle:
    raw = json.load(handle)

network = raw.get("network", [])
css = raw.get("native_cosmetic_css", [])
unsupported = raw.get("unsupported_or_ignored", [])
encoded_network = json.dumps(network, ensure_ascii=False, separators=(",", ":"))
encoded_css = json.dumps(css, ensure_ascii=False, separators=(",", ":"))
report = {
    "compiler": "adblock-rust",
    "integrationStatus": "in-app-production-default",
    "conversionSucceeded": True,
    "version": "adblock-rust-adapter/0.1.0 adblock-rust/0.12.5",
    "inputRuleCount": len(raw.get("used_rules", [])) + len(unsupported),
    "outputRuleCount": len(network),
    "nativeCSSRuleCount": len(css),
    "unsupportedOrAdvancedRuleCount": len(unsupported),
    "diagnostics": [
        f"enhancedResourceCandidates={len(raw.get('enhanced_resource_candidates', []))}",
        f"unsupportedOrIgnored={len(unsupported)}",
    ],
    "webKitCompileSucceeded": False,
    "networkGroupWebKitCompileSucceeded": False,
    "nativeCSSGroupWebKitCompileSucceeded": False,
    "jsonSizeBytes": len(encoded_network.encode("utf-8")) + len(encoded_css.encode("utf-8")),
    "conversionTimeMilliseconds": elapsed_ms,
    "ruleCapHit": False,
    "discardedRuleCount": 0,
}
with open(network_path, "w", encoding="utf-8") as handle:
    json.dump(network, handle, ensure_ascii=False, separators=(",", ":"))
with open(native_css_path, "w", encoding="utf-8") as handle:
    json.dump(css, handle, ensure_ascii=False, separators=(",", ":"))
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

  set +e
  (cd "${SWIFT_PACKAGE}" && swift run -c release SafariConverterCompare --validate-json <"${RUST_NETWORK_JSON}" >"${RUST_NETWORK_WEBKIT_REPORT}")
  RUST_NETWORK_WEBKIT_STATUS="$?"
  (cd "${SWIFT_PACKAGE}" && swift run -c release SafariConverterCompare --validate-json <"${RUST_NATIVE_CSS_JSON}" >"${RUST_NATIVE_CSS_WEBKIT_REPORT}")
  RUST_NATIVE_CSS_WEBKIT_STATUS="$?"
  set -e
  if [[ "${RUST_NETWORK_WEBKIT_STATUS}" -ne 0 ]]; then
    printf '{"webKitCompileSucceeded":false,"processExitStatus":%s}\n' "${RUST_NETWORK_WEBKIT_STATUS}" >"${RUST_NETWORK_WEBKIT_REPORT}"
  fi
  if [[ "${RUST_NATIVE_CSS_WEBKIT_STATUS}" -ne 0 ]]; then
    printf '{"webKitCompileSucceeded":false,"processExitStatus":%s}\n' "${RUST_NATIVE_CSS_WEBKIT_STATUS}" >"${RUST_NATIVE_CSS_WEBKIT_REPORT}"
  fi
  /usr/bin/python3 - "$RUST_REPORT" "$RUST_NETWORK_WEBKIT_REPORT" "$RUST_NATIVE_CSS_WEBKIT_REPORT" <<'PY'
import json
import sys

report_path, network_webkit_path, native_css_webkit_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(report_path, "r", encoding="utf-8") as handle:
    report = json.load(handle)
with open(network_webkit_path, "r", encoding="utf-8") as handle:
    network_webkit = json.load(handle)
with open(native_css_webkit_path, "r", encoding="utf-8") as handle:
    native_css_webkit = json.load(handle)
report["networkGroupWebKitCompileSucceeded"] = bool(network_webkit["webKitCompileSucceeded"])
report["nativeCSSGroupWebKitCompileSucceeded"] = bool(native_css_webkit["webKitCompileSucceeded"])
report["webKitCompileSucceeded"] = bool(
    report["networkGroupWebKitCompileSucceeded"]
    and report["nativeCSSGroupWebKitCompileSucceeded"]
)
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

  rm -rf "${RUST_SHARD_DIR}"
  mkdir -p "${RUST_SHARD_DIR}"
  /usr/bin/python3 - "$RUST_RAW" "$RUST_SHARD_DIR" "$RUST_SHARD_REPORT" <<'PY'
import json
import pathlib
import sys

raw_path, shard_dir, report_path = map(pathlib.Path, sys.argv[1:])
raw = json.loads(raw_path.read_text())
max_rules = 25_000
max_bytes = 3_000_000

def encode(rules):
    return json.dumps(rules, ensure_ascii=False, separators=(",", ":"))

def chunk(rules):
    if not rules:
        return [[]]
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

def write_group(name, rules):
    output = []
    for index, shard_rules in enumerate(chunk(rules), start=1):
        encoded = encode(shard_rules)
        path = shard_dir / f"{name}-{index:04d}.json"
        path.write_text(encoded)
        output.append(
            {
                "id": f"{name}-{index:04d}",
                "path": str(path),
                "ruleCount": len(shard_rules),
                "jsonSizeBytes": len(encoded.encode("utf-8")),
                "webKitCompileSucceeded": None,
            }
        )
    return output

report = {
    "strategy": {
        "maxRulesPerShard": max_rules,
        "maxJSONBytesPerShard": max_bytes,
    },
    "networkShards": write_group("network", raw.get("network", [])),
    "nativeCSSShards": write_group("nativeCSS", raw.get("native_cosmetic_css", [])),
}
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY

  while IFS= read -r shard_path; do
    shard_report_path="${shard_path%.json}-webkit-report.json"
    set +e
    (cd "${SWIFT_PACKAGE}" && swift run -c release SafariConverterCompare --validate-json <"${shard_path}" >"${shard_report_path}")
    shard_status="$?"
    set -e
    if [[ "${shard_status}" -ne 0 ]]; then
      printf '{"webKitCompileSucceeded":false,"processExitStatus":%s}\n' "${shard_status}" >"${shard_report_path}"
    fi
  done < <(find "${RUST_SHARD_DIR}" -name '*.json' ! -name '*-webkit-report.json' | sort)

  /usr/bin/python3 - "$RUST_SHARD_REPORT" "$RUST_REPORT" <<'PY'
import json
import pathlib
import sys

shard_report_path = pathlib.Path(sys.argv[1])
rust_report_path = pathlib.Path(sys.argv[2])
report = json.loads(shard_report_path.read_text())
rust_report = json.loads(rust_report_path.read_text())

for group_name in ("networkShards", "nativeCSSShards"):
    for shard in report[group_name]:
        webkit_report = json.loads(pathlib.Path(shard["path"].replace(".json", "-webkit-report.json")).read_text())
        shard["webKitCompileSucceeded"] = bool(webkit_report["webKitCompileSucceeded"])

all_shards = report["networkShards"] + report["nativeCSSShards"]
report.update(
    {
        "networkShardCount": len(report["networkShards"]),
        "nativeCSSShardCount": len(report["nativeCSSShards"]),
        "largestShardJSONBytes": max((item["jsonSizeBytes"] for item in all_shards), default=0),
        "allShardWebKitCompileSucceeded": all(item["webKitCompileSucceeded"] for item in all_shards),
        "previousOneShotNetworkWebKitCompileSucceeded": rust_report["networkGroupWebKitCompileSucceeded"],
        "previousOneShotNativeCSSWebKitCompileSucceeded": rust_report["nativeCSSGroupWebKitCompileSucceeded"],
    }
)
shard_report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
else
  /usr/bin/python3 - "$COMBINED" "$RUST_STDERR" "$RUST_REPORT" "$RUST_STATUS" "$RUST_MS" <<'PY'
import json
import sys

combined_path, stderr_path, report_path, status, elapsed_ms = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), float(sys.argv[5])
with open(combined_path, "r", encoding="utf-8") as handle:
    input_rule_count = sum(1 for line in handle if line.strip() and not line.startswith("!"))
with open(stderr_path, "r", encoding="utf-8") as handle:
    stderr_lines = [line.strip() for line in handle if line.strip()]
report = {
    "compiler": "adblock-rust",
    "integrationStatus": "in-app-production-default",
    "conversionSucceeded": False,
    "version": "adblock-rust-adapter/0.1.0 adblock-rust/0.12.5",
    "inputRuleCount": input_rule_count,
    "outputRuleCount": 0,
    "nativeCSSRuleCount": 0,
    "unsupportedOrAdvancedRuleCount": 0,
    "diagnostics": [
        f"processExitStatus={status}",
        *stderr_lines[:4],
    ],
    "webKitCompileSucceeded": False,
    "networkGroupWebKitCompileSucceeded": False,
    "nativeCSSGroupWebKitCompileSucceeded": False,
    "jsonSizeBytes": 0,
    "conversionTimeMilliseconds": elapsed_ms,
    "ruleCapHit": False,
    "discardedRuleCount": 0,
}
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
fi

(cd "${SWIFT_PACKAGE}" && swift run -c release SafariConverterCompare <"${COMBINED}" >"${SAFARI_REPORT}")

/usr/bin/python3 - "$METADATA" "$RUST_REPORT" "$SAFARI_REPORT" <<'PY'
import json
import pathlib
import sys

metadata_path, *report_paths = sys.argv[1:]
metadata = json.loads(pathlib.Path(metadata_path).read_text())
for report_path in report_paths:
    path = pathlib.Path(report_path)
    report = json.loads(path.read_text())
    report.update(metadata)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY

printf 'Wrote comparison reports:\n'
printf '  %s\n' "${RUST_REPORT}"
if [[ -f "${RUST_SHARD_REPORT}" ]]; then
  printf '  %s\n' "${RUST_SHARD_REPORT}"
fi
printf '  %s\n' "${SAFARI_REPORT}"
