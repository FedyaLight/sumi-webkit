#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
SAFETY_POLICY_VERSION = "sumi-native-css-safety/0.4"
ADAPTER_VERSION = "adblock-rust-adapter/0.1.0 adblock-rust/0.12.5"
DEFAULT_MAX_RULES_PER_SHARD = 25_000
DEFAULT_MAX_BYTES_PER_SHARD = 3_000_000


LISTS: dict[str, dict[str, Any]] = {
    "easylist": {
        "displayName": "EasyList",
        "category": "baseAds",
        "url": "https://easylist.to/easylist/easylist.txt",
    },
    "adguard-base": {
        "displayName": "AdGuard Base",
        "category": "baseAds",
        "url": "https://filters.adtidy.org/extension/chromium/filters/2.txt",
    },
    "adguard-mobile-ads": {
        "displayName": "AdGuard Mobile Ads",
        "category": "baseAds",
        "url": "https://filters.adtidy.org/extension/chromium/filters/11.txt",
    },
    "adguard-tracking-protection": {
        "displayName": "AdGuard Tracking Protection",
        "category": "privacyOverlap",
        "url": "https://filters.adtidy.org/extension/chromium/filters/3.txt",
    },
    "adguard-url-tracking": {
        "displayName": "AdGuard URL Tracking",
        "category": "privacyOverlap",
        "url": "https://filters.adtidy.org/windows/filters/17.txt",
    },
    "adguard-annoyances": {
        "displayName": "AdGuard Annoyances",
        "category": "annoyances",
        "url": "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_14_Annoyances/filter.txt",
    },
}


PROFILES: dict[str, dict[str, Any]] = {
    "currentDefault": {
        "displayName": "Current default",
        "listIds": ["easylist"],
        "classification": "Current",
    },
    "adguardAdsOnly": {
        "displayName": "AdGuard ads only",
        "listIds": ["adguard-base", "adguard-mobile-ads"],
        "classification": "Custom/Maximum",
    },
    "adguardAdsPrivacy": {
        "displayName": "AdGuard ads and privacy",
        "listIds": [
            "adguard-base",
            "adguard-mobile-ads",
            "adguard-tracking-protection",
            "adguard-url-tracking",
        ],
        "classification": "Custom/Maximum",
    },
    "maximumCustomReference": {
        "displayName": "Maximum custom reference",
        "listIds": [
            "adguard-base",
            "adguard-mobile-ads",
            "adguard-tracking-protection",
            "adguard-url-tracking",
            "adguard-annoyances",
        ],
        "classification": "Custom/Maximum",
        "aliases": ["maximumCustom/reference", "maximumCustom"],
    },
}


@dataclass
class RawDedupeResult:
    rules: list[str]
    input_rule_count: int
    duplicate_removed: int
    skipped_count: int
    skipped_reasons: Counter[str]
    duplicate_attribution: dict[str, list[str]]
    raw_rule_count_by_list: dict[str, int]
    deduped_rule_count_by_list: dict[str, int]


@dataclass
class NativeDedupeResult:
    rules: list[dict[str, Any]]
    duplicate_removed: int
    skipped_count: int
    skipped_reasons: Counter[str]


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def sha256_hex(data: bytes) -> str:
    return sha256(data).hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def encoded_rule_list(rules: list[dict[str, Any]]) -> bytes:
    return json.dumps(
        rules,
        sort_keys=True,
        indent=2,
        ensure_ascii=False,
        separators=(",", ": "),
    ).encode("utf-8")


def resolve_profile(profile: str) -> str:
    if profile in PROFILES:
        return profile
    for profile_id, descriptor in PROFILES.items():
        if profile in descriptor.get("aliases", []):
            return profile_id
    raise SystemExit(f"Unknown bundle profile: {profile}")


def parse_list_file_overrides(values: list[str]) -> dict[str, Path]:
    overrides: dict[str, Path] = {}
    for value in values:
        if "=" not in value:
            raise SystemExit("--list-file expects LIST_ID=/path/to/list.txt")
        list_id, path = value.split("=", 1)
        overrides[list_id] = Path(path).expanduser().resolve()
    return overrides


def fetch_or_reuse_list(
    list_id: str,
    cache_dir: Path,
    refresh: bool,
    offline: bool,
    overrides: dict[str, Path],
) -> bytes:
    if list_id in overrides:
        return overrides[list_id].read_bytes()

    descriptor = LISTS[list_id]
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_path = cache_dir / f"{list_id}.txt"
    if cache_path.exists() and not refresh:
        return cache_path.read_bytes()
    if offline:
        raise SystemExit(f"Missing cached list for offline build: {list_id}")

    data = fetch_url_bytes(descriptor["url"])
    if len(data) < 16:
        raise SystemExit(f"Downloaded list is suspiciously small: {list_id}")
    preview = data[:4096].decode("utf-8", errors="ignore").strip().lower()
    if preview.startswith("<!doctype html") or preview.startswith("<html"):
        raise SystemExit(f"Downloaded list appears to be HTML: {list_id}")
    cache_path.write_bytes(data)
    return data


def fetch_url_bytes(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "SumiAdblockBundleBuilder/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return response.read()
    except urllib.error.URLError as error:
        curl = shutil.which("curl")
        if curl is None:
            raise SystemExit(f"Failed to fetch {url}: {error}") from error
        completed = subprocess.run(
            [
                curl,
                "--fail",
                "--location",
                "--silent",
                "--show-error",
                "--connect-timeout",
                "20",
                "--max-time",
                "90",
                "--user-agent",
                "SumiAdblockBundleBuilder/1.0",
                url,
            ],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if completed.returncode != 0:
            detail = completed.stderr.decode("utf-8", errors="replace").strip()
            raise SystemExit(f"Failed to fetch {url}: {detail or error}") from error
        return completed.stdout


def current_resident_memory_bytes() -> int | None:
    ps = shutil.which("ps")
    if ps is None:
        return None
    completed = subprocess.run(
        [ps, "-o", "rss=", "-p", str(os.getpid())],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if completed.returncode != 0:
        return None
    value = completed.stdout.strip()
    if not value:
        return None
    try:
        return int(value.splitlines()[-1].strip()) * 1024
    except ValueError:
        return None


def normalized_raw_lines(text: str) -> list[str]:
    lines: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("!") or line.startswith("["):
            continue
        lines.append(line)
    return lines


def raw_dedupe_skip_reason(line: str) -> str | None:
    lower = line.lower()
    if line.startswith("@@") or "#@#" in line:
        return "exception rule"
    if "$badfilter" in lower or ",badfilter" in lower:
        return "badfilter rule"
    if "$important" in lower or ",important" in lower:
        return "important rule"
    if "$redirect" in lower or ",redirect" in lower or "$rewrite" in lower or "$replace" in lower:
        return "redirect/resource rule"
    if "#%#" in line or "#?#" in line or "##+js(" in lower:
        return "scriptlet/procedural rule"
    if any(marker in lower for marker in [":has(", ":has-text(", ":matches-css(", ":xpath(", ":-abp-"]):
        return "scriptlet/procedural rule"
    if "$domain=" in lower or ",domain=" in lower:
        return "domain-conditional rule"
    return None


def dedupe_raw_lists(list_texts: dict[str, str]) -> RawDedupeResult:
    seen_safe: set[str] = set()
    seen_all: defaultdict[str, list[str]] = defaultdict(list)
    output: list[str] = []
    duplicate_attribution: defaultdict[str, list[str]] = defaultdict(list)
    skipped_reasons: Counter[str] = Counter()
    raw_rule_count_by_list: dict[str, int] = {}
    deduped_rule_count_by_list: Counter[str] = Counter()
    input_rule_count = 0
    duplicate_removed = 0
    skipped_count = 0

    for list_id in sorted(list_texts):
        lines = normalized_raw_lines(list_texts[list_id])
        raw_rule_count_by_list[list_id] = len(lines)
        for line in lines:
            input_rule_count += 1
            reason = raw_dedupe_skip_reason(line)
            if reason:
                if seen_all[line]:
                    skipped_count += 1
                    skipped_reasons[reason] += 1
                output.append(line)
                deduped_rule_count_by_list[list_id] += 1
                seen_all[line].append(list_id)
                continue

            if line in seen_safe:
                duplicate_removed += 1
                duplicate_attribution[line].append(list_id)
                seen_all[line].append(list_id)
                continue

            seen_safe.add(line)
            output.append(line)
            deduped_rule_count_by_list[list_id] += 1
            seen_all[line].append(list_id)

    for line, sources in seen_all.items():
        if len(sources) > 1 and line in duplicate_attribution:
            duplicate_attribution[line] = sorted(set(sources))

    return RawDedupeResult(
        rules=output,
        input_rule_count=input_rule_count,
        duplicate_removed=duplicate_removed,
        skipped_count=skipped_count,
        skipped_reasons=skipped_reasons,
        duplicate_attribution=dict(sorted(duplicate_attribution.items())),
        raw_rule_count_by_list=raw_rule_count_by_list,
        deduped_rule_count_by_list=dict(deduped_rule_count_by_list),
    )


def build_adapter(root: Path) -> Path:
    manifest = root / "Vendor/Brave/AdblockRustAdapter/Cargo.toml"
    subprocess.run(
        ["cargo", "build", "--locked", "--manifest-path", str(manifest)],
        check=True,
        cwd=root,
    )
    helper = root / "Vendor/Brave/AdblockRustAdapter/target/debug/sumi-adblock-rust-adapter"
    if not helper.exists():
        raise SystemExit(f"adblock-rust adapter did not build: {helper}")
    return helper


def run_adapter(helper: Path, rules: list[str]) -> dict[str, Any]:
    completed = subprocess.run(
        [str(helper)],
        input=("\n".join(rules) + "\n").encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise SystemExit(
            "adblock-rust adapter failed\n"
            + completed.stderr.decode("utf-8", errors="replace")
        )
    return json.loads(completed.stdout.decode("utf-8"))


def split_selector_list(selector: str) -> list[str]:
    parts: list[str] = []
    depth = 0
    quote: str | None = None
    start = 0
    index = 0
    while index < len(selector):
        char = selector[index]
        if quote:
            if char == quote:
                quote = None
            elif char == "\\":
                index += 1
        else:
            if char in {"\"", "'"}:
                quote = char
            elif char in {"[", "("}:
                depth += 1
            elif char in {"]",
                ")",
            }:
                depth = max(0, depth - 1)
            elif char == "," and depth == 0:
                part = selector[start:index].strip()
                if part:
                    parts.append(part)
                start = index + 1
        index += 1
    final = selector[start:].strip()
    if final:
        parts.append(final)
    return parts


def rightmost_selector_compound(selector: str) -> str:
    depth = 0
    quote: str | None = None
    last_boundary = 0
    index = 0
    while index < len(selector):
        char = selector[index]
        if quote:
            if char == quote:
                quote = None
            elif char == "\\":
                index += 1
        else:
            if char in {"\"", "'"}:
                quote = char
            elif char in {"[", "("}:
                depth += 1
            elif char in {"]", ")"}:
                depth = max(0, depth - 1)
            elif char in {">", "+", "~"} and depth == 0:
                last_boundary = index + 1
            elif char.isspace() and depth == 0:
                last_boundary = index + 1
        index += 1
    return selector[last_boundary:].strip()


def is_unsafe_root_selector_subject(subject: str, root: str) -> bool:
    if not subject.startswith(root):
        return False
    suffix = subject[len(root):]
    if not suffix:
        return True
    if suffix.startswith("::"):
        return False
    return suffix.startswith(".") or suffix.startswith("[") or suffix.startswith(":")


def targets_document_root_or_app_container(selector: str) -> bool:
    subject = rightmost_selector_compound(selector.strip())
    if not subject:
        return False
    lower_subject = subject.lower()
    if (
        is_unsafe_root_selector_subject(lower_subject, "html")
        or is_unsafe_root_selector_subject(lower_subject, "body")
        or is_unsafe_root_selector_subject(lower_subject, ":root")
    ):
        return True
    for app_root in ["#app", "#root", "#__next", "#__nuxt"]:
        if (
            subject == app_root
            or subject.startswith(app_root + ".")
            or subject.startswith(app_root + "[")
            or (subject.startswith(app_root + ":") and not subject.startswith(app_root + "::"))
        ):
            return True
    return False


def normalized_root_child_selector(selector: str) -> str:
    normalized = selector.strip().lower().replace("[class*=' ']", "[class*=\" \"]")
    normalized = re.sub(r"\s*>\s*", " > ", normalized)
    normalized = re.sub(r"\s+", " ", normalized)
    return normalized


def normalized_root_child_subject_selector(selector: str) -> str:
    index = selector.find(":has(")
    return selector if index < 0 else selector[:index]


def targets_root_child_page_shell_container(selector: str) -> bool:
    subject = normalized_root_child_subject_selector(normalized_root_child_selector(selector))
    return subject in {
        "body > div[id][class*=\" \"]",
        "body > div[id][class*=\" \"]:first-child",
        "html > body > div[id][class*=\" \"]",
        "html > body > div[id][class*=\" \"]:first-child",
    }


def unsafe_native_css_selector_reason(selector: str) -> str | None:
    if targets_document_root_or_app_container(selector):
        return "unsafe native CSS root-container selector"
    if targets_root_child_page_shell_container(selector):
        return "unsafe native CSS root-child page shell selector"
    return None


def sanitize_native_css_rules(rules: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    sanitized: list[dict[str, Any]] = []
    filtered: list[dict[str, str]] = []
    for rule in rules:
        action = rule.get("action")
        if not isinstance(action, dict) or action.get("type") != "css-display-none":
            sanitized.append(rule)
            continue
        selector = action.get("selector")
        if not isinstance(selector, str):
            sanitized.append(rule)
            continue
        retained: list[str] = []
        for component in split_selector_list(selector):
            reason = unsafe_native_css_selector_reason(component)
            if reason:
                filtered.append({"rule": component, "reason": reason})
            else:
                retained.append(component)
        if not retained:
            continue
        if len(retained) == len(split_selector_list(selector)):
            sanitized.append(rule)
        else:
            updated = json.loads(json.dumps(rule))
            updated["action"]["selector"] = ", ".join(retained)
            sanitized.append(updated)
    return sanitized, filtered


def native_dedupe_skip_reason(rule: dict[str, Any]) -> str | None:
    action = rule.get("action")
    if not isinstance(action, dict):
        return "invalid native rule"
    action_type = action.get("type")
    if action_type == "ignore-previous-rules":
        return "exception/order-sensitive native rule"
    if isinstance(action_type, str) and ("redirect" in action_type or "resource" in action_type):
        return "redirect/resource native rule"
    return None


def dedupe_native_rules(rules: list[dict[str, Any]]) -> NativeDedupeResult:
    seen: set[str] = set()
    seen_skipped: set[str] = set()
    output: list[dict[str, Any]] = []
    duplicate_removed = 0
    skipped_count = 0
    skipped_reasons: Counter[str] = Counter()
    for rule in rules:
        key = canonical_json(rule)
        reason = native_dedupe_skip_reason(rule)
        if reason:
            if key in seen_skipped:
                skipped_count += 1
                skipped_reasons[reason] += 1
            seen_skipped.add(key)
            output.append(rule)
            continue
        if key in seen:
            duplicate_removed += 1
            continue
        seen.add(key)
        output.append(rule)
    return NativeDedupeResult(output, duplicate_removed, skipped_count, skipped_reasons)


def chunk_rules(
    rules: list[dict[str, Any]],
    max_rules: int,
    max_bytes: int,
) -> list[list[dict[str, Any]]]:
    if not rules:
        return []
    chunks: list[list[dict[str, Any]]] = []
    current: list[dict[str, Any]] = []
    current_estimated_bytes = 2
    for rule in rules:
        rule_bytes = len(canonical_json(rule).encode("utf-8"))
        separator_bytes = 0 if not current else 1
        if current and (
            len(current) >= max_rules
            or current_estimated_bytes + separator_bytes + rule_bytes > max_bytes
        ):
            chunks.append(current)
            current = []
            current_estimated_bytes = 2
        current.append(rule)
        current_estimated_bytes += (0 if len(current) == 1 else 1) + rule_bytes
    if current:
        chunks.append(current)
    return chunks


def overlap_diagnostics(list_lines: dict[str, list[str]], selected_list_ids: list[str]) -> dict[str, Any]:
    safe_sets = {
        list_id: {line for line in lines if raw_dedupe_skip_reason(line) is None}
        for list_id, lines in list_lines.items()
    }
    pairs: list[dict[str, Any]] = []
    for index, left in enumerate(selected_list_ids):
        for right in selected_list_ids[index + 1:]:
            overlap = safe_sets.get(left, set()) & safe_sets.get(right, set())
            if overlap:
                pairs.append(
                    {
                        "left": left,
                        "right": right,
                        "overlapRuleCount": len(overlap),
                    }
                )
    categories = [LISTS[list_id]["category"] for list_id in selected_list_ids]
    warnings: list[str] = []
    if categories.count("baseAds") > 1:
        warnings.append("Multiple base advertising list families selected; classify as Custom/Maximum.")
    if "privacyOverlap" in categories and "baseAds" in categories:
        warnings.append("Privacy-overlap lists are selected with base lists; keep separate from Balanced.")
    if "annoyances" in categories:
        warnings.append("Annoyance list selected; classify as Custom/Maximum.")
    return {
        "pairs": pairs,
        "warnings": warnings,
    }


def write_shards(
    bundle_dir: Path,
    generation_id: str,
    kind: str,
    rules: list[dict[str, Any]],
    max_rules: int,
    max_bytes: int,
) -> list[dict[str, Any]]:
    group_dir = bundle_dir / kind
    group_dir.mkdir(parents=True, exist_ok=True)
    shards: list[dict[str, Any]] = []
    for index, chunk in enumerate(chunk_rules(rules, max_rules, max_bytes), start=1):
        relative_path = f"{kind}/{kind}-{index:04d}.json"
        data = encoded_rule_list(chunk)
        digest = sha256_hex(data)
        (bundle_dir / relative_path).write_bytes(data)
        shards.append(
            {
                "kind": kind,
                "group": kind,
                "relativePath": relative_path,
                "hash": digest,
                "byteSize": len(data),
                "ruleCount": len(chunk),
                "webKitIdentifier": f"sumi.adblock.{kind}.{generation_id}.{index:04d}.{digest[:12]}",
            }
        )
    return shards


def build_bundle(args: argparse.Namespace) -> None:
    root = repo_root()
    profiles = [resolve_profile(args.profile)]
    if args.all_profiles:
        profiles = list(PROFILES.keys())
    overrides = parse_list_file_overrides(args.list_file)
    helper = Path(args.adapter).expanduser().resolve() if args.adapter else build_adapter(root)
    output_root = Path(args.output).expanduser().resolve()

    for profile_id in profiles:
        bundle_dir = output_root / profile_id / "SumiAdblockBundle" if args.all_profiles else output_root / "SumiAdblockBundle"
        if bundle_dir.exists():
            shutil.rmtree(bundle_dir)
        bundle_dir.mkdir(parents=True)
        build_one_bundle(
            profile_id=profile_id,
            bundle_dir=bundle_dir,
            cache_dir=Path(args.cache_dir).expanduser().resolve(),
            helper=helper,
            refresh=args.refresh,
            offline=args.offline,
            overrides=overrides,
            max_rules=args.max_rules_per_shard,
            max_bytes=args.max_bytes_per_shard,
        )


def build_one_bundle(
    profile_id: str,
    bundle_dir: Path,
    cache_dir: Path,
    helper: Path,
    refresh: bool,
    offline: bool,
    overrides: dict[str, Path],
    max_rules: int,
    max_bytes: int,
) -> None:
    profile = PROFILES[profile_id]
    selected_list_ids = profile["listIds"]
    raw_data_by_list: dict[str, bytes] = {}
    list_texts: dict[str, str] = {}
    list_lines: dict[str, list[str]] = {}
    for list_id in selected_list_ids:
        data = fetch_or_reuse_list(list_id, cache_dir, refresh, offline, overrides)
        raw_data_by_list[list_id] = data
        text = data.decode("utf-8", errors="replace")
        list_texts[list_id] = text
        list_lines[list_id] = normalized_raw_lines(text)

    memory = {
        "beforeRawDedupeResidentBytes": current_resident_memory_bytes(),
    }
    raw_dedupe = dedupe_raw_lists(list_texts)
    memory["afterRawDedupeResidentBytes"] = current_resident_memory_bytes()
    adapter_output = run_adapter(helper, raw_dedupe.rules)
    network_input = adapter_output.get("network", [])
    css_input, filtered_css = sanitize_native_css_rules(adapter_output.get("native_cosmetic_css", []))
    memory["beforeNativeJSONDedupeResidentBytes"] = current_resident_memory_bytes()
    network_dedupe = dedupe_native_rules(network_input)
    css_dedupe = dedupe_native_rules(css_input)
    memory["afterNativeJSONDedupeResidentBytes"] = current_resident_memory_bytes()

    generated_at = datetime.now(timezone.utc)
    seed = canonical_json(
        {
            "profile": profile_id,
            "lists": {
                list_id: sha256_hex(raw_data_by_list[list_id])
                for list_id in selected_list_ids
            },
            "network": len(network_dedupe.rules),
            "nativeCSS": len(css_dedupe.rules),
            "rawDuplicates": raw_dedupe.duplicate_removed,
            "nativeDuplicates": network_dedupe.duplicate_removed + css_dedupe.duplicate_removed,
        }
    )
    generation_hash = sha256_hex(seed.encode("utf-8"))[:12]
    generation_id = generated_at.strftime("%Y%m%dT%H%M%SZ") + "-" + generation_hash
    bundle_id = f"sumi.adblock.bundle.{profile_id}.{generation_hash}"

    network_shards = write_shards(bundle_dir, generation_id, "network", network_dedupe.rules, max_rules, max_bytes)
    css_shards = write_shards(bundle_dir, generation_id, "nativeCSS", css_dedupe.rules, max_rules, max_bytes)
    shards = network_shards + css_shards
    overlap = overlap_diagnostics(list_lines, selected_list_ids)

    list_entries = []
    for list_id in selected_list_ids:
        descriptor = LISTS[list_id]
        list_entries.append(
            {
                "id": list_id,
                "displayName": descriptor["displayName"],
                "url": descriptor["url"],
                "hash": sha256_hex(raw_data_by_list[list_id]),
                "byteSize": len(raw_data_by_list[list_id]),
                "ruleCount": raw_dedupe.raw_rule_count_by_list[list_id],
                "dedupedRuleCount": raw_dedupe.deduped_rule_count_by_list.get(list_id, 0),
                "category": descriptor["category"],
            }
        )

    native_duplicates = network_dedupe.duplicate_removed + css_dedupe.duplicate_removed
    skipped_reasons = raw_dedupe.skipped_reasons + network_dedupe.skipped_reasons + css_dedupe.skipped_reasons
    skipped_count = raw_dedupe.skipped_count + network_dedupe.skipped_count + css_dedupe.skipped_count
    final_rule_count = len(network_dedupe.rules) + len(css_dedupe.rules)
    warnings = overlap["warnings"]

    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "bundleId": bundle_id,
        "generationId": generation_id,
        "profileId": profile_id,
        "profileDisplayName": profile["displayName"],
        "profileClassification": profile["classification"],
        "compiler": {
            "name": "adblock-rust",
            "version": f"{ADAPTER_VERSION} {SAFETY_POLICY_VERSION}",
            "adapterPath": str(helper),
        },
        "nativeCSSSafetyPolicyVersion": SAFETY_POLICY_VERSION,
        "generatedDate": generated_at.isoformat().replace("+00:00", "Z"),
        "lists": list_entries,
        "shards": shards,
        "diagnosticsSummary": {
            "inputRuleCount": raw_dedupe.input_rule_count,
            "finalRuleCount": final_rule_count,
            "finalShardCount": len(shards),
            "networkRuleCount": len(network_dedupe.rules),
            "nativeCSSRuleCount": len(css_dedupe.rules),
            "unsafeCSSFilteredCount": len(filtered_css),
            "warnings": warnings,
        },
        "unsafeCSSFilteredCount": len(filtered_css),
        "deduplication": {
            "inputRawRuleCount": raw_dedupe.input_rule_count,
            "rawDuplicateCountRemoved": raw_dedupe.duplicate_removed,
            "nativeJSONDuplicateCountRemoved": native_duplicates,
            "skippedDedupeCount": skipped_count,
            "skippedDedupeReasons": dict(sorted(skipped_reasons.items())),
            "finalRuleCount": final_rule_count,
            "finalShardCount": len(shards),
        },
    }
    diagnostics = {
        "manifest": {
            "bundleId": bundle_id,
            "profileId": profile_id,
            "generationId": generation_id,
        },
        "lists": list_entries,
        "rawDeduplication": {
            "inputRuleCount": raw_dedupe.input_rule_count,
            "duplicatesRemoved": raw_dedupe.duplicate_removed,
            "skippedDedupeCount": raw_dedupe.skipped_count,
            "skippedDedupeReasons": dict(sorted(raw_dedupe.skipped_reasons.items())),
            "duplicateAttribution": raw_dedupe.duplicate_attribution,
        },
        "nativeJSONDeduplication": {
            "networkDuplicatesRemoved": network_dedupe.duplicate_removed,
            "nativeCSSDuplicatesRemoved": css_dedupe.duplicate_removed,
            "networkSkippedDedupeCount": network_dedupe.skipped_count,
            "nativeCSSSkippedDedupeCount": css_dedupe.skipped_count,
            "skippedDedupeReasons": dict(sorted((network_dedupe.skipped_reasons + css_dedupe.skipped_reasons).items())),
        },
        "nativeCSSSafety": {
            "policyVersion": SAFETY_POLICY_VERSION,
            "filteredCount": len(filtered_css),
            "filteredSelectors": filtered_css[:1000],
        },
        "overlap": overlap,
        "memory": memory,
        "adapter": {
            "unsupportedOrIgnoredCount": len(adapter_output.get("unsupported_or_ignored", [])),
            "enhancedResourceCandidateCount": len(adapter_output.get("enhanced_resource_candidates", [])),
        },
    }

    write_json(bundle_dir / "manifest.json", manifest)
    write_json(bundle_dir / "diagnostics.json", diagnostics)
    verified = verify_bundle_dir(bundle_dir, allow_empty_shards=False, quiet=True)
    print(
        f"{profile_id}: rules={final_rule_count} shards={len(shards)} "
        f"bytes={verified['totalBytes']} rawDupes={raw_dedupe.duplicate_removed} "
        f"nativeDupes={native_duplicates} unsafeCSSFiltered={len(filtered_css)}"
    )


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(payload, sort_keys=True, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def verify_bundle_dir(
    bundle_dir: Path,
    allow_empty_shards: bool,
    quiet: bool = False,
) -> dict[str, Any]:
    manifest_path = bundle_dir / "manifest.json"
    diagnostics_path = bundle_dir / "diagnostics.json"
    if not manifest_path.exists():
        raise SystemExit(f"Missing manifest: {manifest_path}")
    if not diagnostics_path.exists():
        raise SystemExit(f"Missing diagnostics: {diagnostics_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        raise SystemExit(f"Unsupported schemaVersion: {manifest.get('schemaVersion')}")
    required = [
        "bundleId",
        "generationId",
        "profileId",
        "compiler",
        "nativeCSSSafetyPolicyVersion",
        "generatedDate",
        "lists",
        "shards",
        "diagnosticsSummary",
        "deduplication",
    ]
    missing = [key for key in required if key not in manifest]
    if missing:
        raise SystemExit(f"Manifest missing required keys: {', '.join(missing)}")
    if not manifest["shards"]:
        raise SystemExit("Bundle has no shards")

    total_rules = 0
    total_bytes = 0
    for shard in manifest["shards"]:
        relative = shard.get("relativePath")
        if not relative or Path(relative).is_absolute() or ".." in Path(relative).parts:
            raise SystemExit(f"Invalid shard relativePath: {relative}")
        shard_path = bundle_dir / relative
        if not shard_path.exists():
            raise SystemExit(f"Missing shard: {relative}")
        data = shard_path.read_bytes()
        if not data and not allow_empty_shards:
            raise SystemExit(f"Empty shard rejected: {relative}")
        if len(data) != shard.get("byteSize"):
            raise SystemExit(f"Shard size mismatch: {relative}")
        digest = sha256_hex(data)
        if digest != shard.get("hash"):
            raise SystemExit(f"Shard hash mismatch: {relative}")
        try:
            parsed = json.loads(data.decode("utf-8"))
        except json.JSONDecodeError as error:
            raise SystemExit(f"Shard JSON parse failed: {relative}: {error}") from error
        if not isinstance(parsed, list):
            raise SystemExit(f"Shard JSON is not an array: {relative}")
        if not parsed and not allow_empty_shards:
            raise SystemExit(f"Empty shard JSON rejected: {relative}")
        if len(parsed) != shard.get("ruleCount"):
            raise SystemExit(f"Shard rule count mismatch: {relative}")
        total_rules += len(parsed)
        total_bytes += len(data)

    dedupe = manifest["deduplication"]
    summary = manifest["diagnosticsSummary"]
    if total_rules != dedupe.get("finalRuleCount") or total_rules != summary.get("finalRuleCount"):
        raise SystemExit("Final rule count does not match shard contents")
    if len(manifest["shards"]) != dedupe.get("finalShardCount"):
        raise SystemExit("Final shard count does not match manifest shards")

    result = {
        "bundleId": manifest["bundleId"],
        "profileId": manifest["profileId"],
        "ruleCount": total_rules,
        "shardCount": len(manifest["shards"]),
        "totalBytes": total_bytes,
        "unsafeCSSFilteredCount": manifest.get("unsafeCSSFilteredCount", 0),
        "deduplication": dedupe,
    }
    if not quiet:
        print(
            f"verified {manifest['profileId']}: rules={total_rules} shards={len(manifest['shards'])} "
            f"bytes={total_bytes} unsafeCSSFiltered={result['unsafeCSSFilteredCount']} "
            f"rawDupes={dedupe.get('rawDuplicateCountRemoved')} "
            f"nativeDupes={dedupe.get('nativeJSONDuplicateCountRemoved')} "
            f"dedupeSkipped={dedupe.get('skippedDedupeCount')}"
        )
    return result


def verify_command(args: argparse.Namespace) -> None:
    verify_bundle_dir(
        Path(args.bundle).expanduser().resolve(),
        allow_empty_shards=args.allow_empty_shards,
    )


def self_test() -> None:
    raw = dedupe_raw_lists(
        {
            "a": "\n! comment\n||ads.example^\n||ads.example^\n@@||ads.example^\n@@||ads.example^\n",
            "b": "||ads.example^\n||tracker.example^$domain=example.com\n||tracker.example^$domain=example.com\n",
        }
    )
    assert raw.input_rule_count == 7
    assert raw.duplicate_removed == 2
    assert raw.skipped_count == 2
    assert raw.skipped_reasons["exception rule"] == 1
    assert raw.skipped_reasons["domain-conditional rule"] == 1

    rules = [
        {"action": {"type": "css-display-none", "selector": "body, .ad, #app"}, "trigger": {"url-filter": ".*"}},
        {"action": {"type": "css-display-none", "selector": "body > div[id][class*=\" \"]:has(div.adblock_subtitle)"}, "trigger": {"url-filter": ".*"}},
    ]
    sanitized, filtered = sanitize_native_css_rules(rules)
    assert len(sanitized) == 1
    assert sanitized[0]["action"]["selector"] == ".ad"
    assert len(filtered) == 3

    native = dedupe_native_rules(
        [
            {"action": {"type": "block"}, "trigger": {"url-filter": "ads"}},
            {"trigger": {"url-filter": "ads"}, "action": {"type": "block"}},
            {"action": {"type": "ignore-previous-rules"}, "trigger": {"url-filter": "ads"}},
            {"action": {"type": "ignore-previous-rules"}, "trigger": {"url-filter": "ads"}},
        ]
    )
    assert native.duplicate_removed == 1
    assert native.skipped_count == 1

    with tempfile.TemporaryDirectory() as tmp:
        bundle = Path(tmp) / "SumiAdblockBundle"
        (bundle / "network").mkdir(parents=True)
        shard = [{"action": {"type": "block"}, "trigger": {"url-filter": "ads"}}]
        data = encoded_rule_list(shard)
        shard_path = bundle / "network/network-0001.json"
        shard_path.write_bytes(data)
        manifest = {
            "schemaVersion": SCHEMA_VERSION,
            "bundleId": "sumi.adblock.bundle.test",
            "generationId": "test",
            "profileId": "currentDefault",
            "compiler": {"name": "adblock-rust", "version": ADAPTER_VERSION},
            "nativeCSSSafetyPolicyVersion": SAFETY_POLICY_VERSION,
            "generatedDate": "2026-05-17T00:00:00Z",
            "lists": [],
            "shards": [
                {
                    "kind": "network",
                    "group": "network",
                    "relativePath": "network/network-0001.json",
                    "hash": sha256_hex(data),
                    "byteSize": len(data),
                    "ruleCount": 1,
                    "webKitIdentifier": "sumi.adblock.network.test.0001.hash",
                }
            ],
            "diagnosticsSummary": {
                "inputRuleCount": 1,
                "finalRuleCount": 1,
                "finalShardCount": 1,
                "networkRuleCount": 1,
                "nativeCSSRuleCount": 0,
                "unsafeCSSFilteredCount": 0,
                "warnings": [],
            },
            "unsafeCSSFilteredCount": 0,
            "deduplication": {
                "inputRawRuleCount": 1,
                "rawDuplicateCountRemoved": 0,
                "nativeJSONDuplicateCountRemoved": 0,
                "skippedDedupeCount": 0,
                "skippedDedupeReasons": {},
                "finalRuleCount": 1,
                "finalShardCount": 1,
            },
        }
        write_json(bundle / "manifest.json", manifest)
        write_json(bundle / "diagnostics.json", {"ok": True})
        verify_bundle_dir(bundle, allow_empty_shards=False, quiet=True)


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build or verify Sumi native Adblock bundles.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build = subparsers.add_parser("build")
    build.add_argument("--profile", default="currentDefault")
    build.add_argument("--all-profiles", action="store_true")
    build.add_argument("--output", default=".build/sumi-adblock-bundles")
    build.add_argument("--cache-dir", default=".build/sumi-adblock-bundle/raw")
    build.add_argument("--adapter")
    build.add_argument("--refresh", action="store_true")
    build.add_argument("--offline", action="store_true")
    build.add_argument("--list-file", action="append", default=[])
    build.add_argument("--max-rules-per-shard", type=int, default=DEFAULT_MAX_RULES_PER_SHARD)
    build.add_argument("--max-bytes-per-shard", type=int, default=DEFAULT_MAX_BYTES_PER_SHARD)
    build.set_defaults(func=build_bundle)

    verify = subparsers.add_parser("verify")
    verify.add_argument("bundle")
    verify.add_argument("--allow-empty-shards", action="store_true")
    verify.set_defaults(func=verify_command)

    tests = subparsers.add_parser("self-test")
    tests.set_defaults(func=lambda _args: self_test())
    return parser


def main() -> None:
    parser = make_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
