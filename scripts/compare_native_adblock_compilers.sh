#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT}/.build/adblock-native-compiler-compare"
SAFARI_CONVERTER_LIB_DIR="${SAFARI_CONVERTER_LIB_DIR:-${WORK_DIR}/SafariConverterLib}"
RUST_MANIFEST="${ROOT}/Vendor/Brave/AdblockRustAdapter/Cargo.toml"
RUST_HELPER="${ROOT}/Vendor/Brave/AdblockRustAdapter/target/debug/sumi-adblock-rust-adapter"

LIST_URLS=(
  "https://easylist.to/easylist/easylist.txt"
  "https://filters.adtidy.org/extension/chromium/filters/2.txt"
  "https://filters.adtidy.org/extension/chromium/filters/11.txt"
  "https://filters.adtidy.org/extension/chromium/filters/3.txt"
  "https://filters.adtidy.org/windows/filters/17.txt"
  "https://filters.adtidy.org/extension/chromium/filters/14.txt"
)

usage() {
  cat <<'USAGE'
Usage:
  scripts/compare_native_adblock_compilers.sh [filter-list-url-or-file ...]

Compares Sumi's current adblock-rust native compiler helper against
AdGuard SafariConverterLib on the same selected list inputs. With no arguments,
it uses Sumi current default plus the Ora-like AdGuard comparison lists.

Set SAFARI_CONVERTER_LIB_DIR to an existing SafariConverterLib checkout to avoid
the script-managed clone under .build/.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "$#" -gt 0 ]]; then
  LIST_URLS=("$@")
fi

mkdir -p "${WORK_DIR}/lists" "${WORK_DIR}/SafariConverterCompare"

if [[ ! -d "${SAFARI_CONVERTER_LIB_DIR}/.git" ]]; then
  rm -rf "${SAFARI_CONVERTER_LIB_DIR}"
  git clone --depth 1 --branch v4.2.2 https://github.com/AdguardTeam/SafariConverterLib.git "${SAFARI_CONVERTER_LIB_DIR}"
fi

cargo build --manifest-path "${RUST_MANIFEST}" >/dev/null

COMBINED="${WORK_DIR}/combined.txt"
: >"${COMBINED}"
for source in "${LIST_URLS[@]}"; do
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
done

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
            conversionTimeMilliseconds: elapsed
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

RUST_RAW="${WORK_DIR}/adblock-rust-output.json"
RUST_REPORT="${WORK_DIR}/adblock-rust-report.json"
RUST_COMBINED_JSON="${WORK_DIR}/adblock-rust-combined-webkit.json"
RUST_STDERR="${WORK_DIR}/adblock-rust-stderr.txt"
RUST_WEBKIT_REPORT="${WORK_DIR}/adblock-rust-webkit-report.json"
SAFARI_REPORT="${WORK_DIR}/safari-converter-report.json"

START_NS="$(date +%s%N)"
set +e
"${RUST_HELPER}" <"${COMBINED}" >"${RUST_RAW}" 2>"${RUST_STDERR}"
RUST_STATUS="$?"
set -e
END_NS="$(date +%s%N)"
RUST_MS="$(( (END_NS - START_NS) / 1000000 ))"

if [[ "${RUST_STATUS}" -eq 0 ]]; then
  /usr/bin/python3 - "$RUST_RAW" "$RUST_REPORT" "$RUST_COMBINED_JSON" "$RUST_MS" <<'PY'
import json
import sys

raw_path, report_path, combined_path, elapsed_ms = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
with open(raw_path, "r", encoding="utf-8") as handle:
    raw = json.load(handle)

network = raw.get("network", [])
css = raw.get("native_cosmetic_css", [])
unsupported = raw.get("unsupported_or_ignored", [])
encoded_network = json.dumps(network, ensure_ascii=False, separators=(",", ":"))
encoded_css = json.dumps(css, ensure_ascii=False, separators=(",", ":"))
report = {
    "compiler": "adblock-rust",
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
    "jsonSizeBytes": len(encoded_network.encode("utf-8")) + len(encoded_css.encode("utf-8")),
    "conversionTimeMilliseconds": elapsed_ms,
}
with open(combined_path, "w", encoding="utf-8") as handle:
    json.dump(network + css, handle, ensure_ascii=False, separators=(",", ":"))
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

  (cd "${SWIFT_PACKAGE}" && swift run -c release SafariConverterCompare --validate-json <"${RUST_COMBINED_JSON}" >"${RUST_WEBKIT_REPORT}")
  /usr/bin/python3 - "$RUST_REPORT" "$RUST_WEBKIT_REPORT" <<'PY'
import json
import sys

report_path, webkit_path = sys.argv[1], sys.argv[2]
with open(report_path, "r", encoding="utf-8") as handle:
    report = json.load(handle)
with open(webkit_path, "r", encoding="utf-8") as handle:
    webkit = json.load(handle)
report["webKitCompileSucceeded"] = bool(webkit["webKitCompileSucceeded"])
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2, sort_keys=True)
    handle.write("\n")
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
    "jsonSizeBytes": 0,
    "conversionTimeMilliseconds": elapsed_ms,
}
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
fi

(cd "${SWIFT_PACKAGE}" && swift run -c release SafariConverterCompare <"${COMBINED}" >"${SAFARI_REPORT}")

printf 'Wrote comparison reports:\n'
printf '  %s\n' "${RUST_REPORT}"
printf '  %s\n' "${SAFARI_REPORT}"
