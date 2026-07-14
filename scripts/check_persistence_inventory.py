#!/usr/bin/env python3
"""Validate Sumi's persistence map and immutable migration fixtures."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MAP_PATH = ROOT / "docs/persistence/persistence-map.json"
MANIFEST_PATH = ROOT / "SumiTests/Fixtures/Persistence/manifest.json"
FIXTURE_ROOT = MANIFEST_PATH.parent
BACKUP_SCOPE_SOURCE = ROOT / "Sumi/ImportExport/SumiImportExportModels.swift"
BACKUP_SERVICE_SOURCE = ROOT / "Sumi/ImportExport/SumiBackupService.swift"
ROADMAP_PATH = ROOT / "docs/roadmap.md"
SOURCE_ROOTS = [
    "App",
    "Sumi",
    "Settings",
    "SidebarChrome",
    "FloatingBar",
    "UI",
    "Packages/SumiDomain/Sources",
    "Packages/SumiWebRuntime/Sources",
]

FILE_SIGNALS = {
    "file_write": re.compile(
        r"\.write\s*\(\s*to:|"
        r"(?:fileManager|FileManager\.default)\."
        r"(?:copyItem|moveItem|replaceItemAt)\s*\(|"
        r"Darwin\.(?:write|rename|renamex_np)\s*\(|guard\s+rename\s*\("
    ),
    "user_defaults": re.compile(
        r"@AppStorage|\bUserDefaults\b|\buserDefaults\."
        r"(?:set|removeObject)|\bdefaults\.(?:set|removeObject)|\bPersisted\."
    ),
    "keychain": re.compile(r"\bSecItem(?:Add|Update|Delete|CopyMatching)\s*\("),
    "core_data": re.compile(r"\bNSPersistentStoreDescription\s*\("),
    "webkit_persistent": re.compile(
        r"WKWebsiteDataStore\.default\s*\(|"
        r"WKWebsiteDataStore\s*\(\s*forIdentifier:|"
        r"WKWebExtensionController\.Configuration\s*\(|"
        r"WKContentRuleListStore\.(?:default)\s*\(|"
        r"WKContentRuleListStore\s*\(\s*url:"
    ),
    "swiftdata_schema": re.compile(r"\bVersionedSchema\b|\bModelConfiguration\s*\("),
}
VERSION_OWNER = re.compile(
    r"(?:"
    r"(?:private\s+|nonisolated\s+)*static\s+let\s+"
    r"(?:[A-Za-z_][A-Za-z0-9_]*)?(?:Version|version)[A-Za-z0-9_]*\s*=\s*[^\n]+"
    r"|guard\s+[A-Za-z_][A-Za-z0-9_]*\.(?:schemaVersion|formatVersion)\s*==\s*\d+[^\n]*"
    r")"
)
SWIFTDATA_MODEL = re.compile(
    r"@Model\s+(?:final\s+)?(?:class|actor)\s+([A-Za-z_][A-Za-z0-9_]*)"
)


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def swift_sources() -> list[Path]:
    result: list[Path] = []
    for source_root in SOURCE_ROOTS:
        directory = ROOT / source_root
        if directory.exists():
            result.extend(directory.rglob("*.swift"))
    return sorted(set(result))


def discover() -> dict[str, object]:
    signals: list[dict[str, str]] = []
    version_owners: list[dict[str, str]] = []
    swiftdata_models: list[dict[str, str]] = []

    for path in swift_sources():
        source = path.read_text(encoding="utf-8")
        source_path = relative(path)
        for kind, pattern in FILE_SIGNALS.items():
            if pattern.search(source):
                signals.append({"kind": kind, "path": source_path})
        for match in VERSION_OWNER.finditer(source):
            declaration = " ".join(match.group(0).split())
            version_owners.append(
                {"path": source_path, "declaration": declaration}
            )
        for match in SWIFTDATA_MODEL.finditer(source):
            swiftdata_models.append(
                {"path": source_path, "type": match.group(1)}
            )

    core_data_models: list[dict[str, object]] = []
    for path in sorted(ROOT.glob("**/*.xcdatamodel/contents")):
        if any(part.startswith(".") for part in path.relative_to(ROOT).parts):
            continue
        model = ET.parse(path).getroot()
        entities = sorted(
            entity.attrib["name"]
            for entity in model.findall("entity")
            if "name" in entity.attrib
        )
        core_data_models.append({"path": relative(path), "entities": entities})

    current_versions: list[dict[str, str]] = []
    for model_directory in sorted(ROOT.glob("**/*.xcdatamodeld")):
        path = model_directory / ".xccurrentversion"
        if not path.is_file():
            continue
        with path.open("rb") as stream:
            value = plistlib.load(stream).get("_XCCurrentVersionName")
        current_versions.append({"path": relative(path), "current": value})

    return {
        "signals": signals,
        "versionOwners": version_owners,
        "swiftDataModels": swiftdata_models,
        "coreDataModels": core_data_models,
        "coreDataCurrentVersions": current_versions,
    }


def load_json(path: Path) -> dict[str, object]:
    try:
        with path.open(encoding="utf-8") as stream:
            value = json.load(stream)
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read {relative(path)}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"{relative(path)} must contain a JSON object")
    return value


def require_text(record: dict[str, object], field: str, context: str) -> None:
    value = record.get(field)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{context}.{field} must be non-empty text")


def swift_enum_cases(source: str, enum_name: str) -> list[str]:
    declaration = re.search(rf"\benum\s+{re.escape(enum_name)}\b[^{{]*{{", source)
    if declaration is None:
        raise ValueError(f"missing Swift backup scope enum: {enum_name}")
    cases: list[str] = []
    for line in source[declaration.end():].splitlines():
        stripped = line.strip()
        if stripped.startswith("case "):
            cases.extend(value.strip() for value in stripped[5:].split(","))
        elif cases:
            break
    if not cases:
        raise ValueError(f"Swift backup scope enum has no cases: {enum_name}")
    return cases


def validate_backup_v1_scope(inventory: dict[str, object]) -> None:
    scope = inventory.get("logicalBackupV1Scope")
    if not isinstance(scope, dict):
        raise ValueError("logicalBackupV1Scope must be an object")
    if scope.get("versionOwner") != "SumiBackupV1Scope":
        raise ValueError("logicalBackupV1Scope must be owned by SumiBackupV1Scope")

    source = BACKUP_SCOPE_SOURCE.read_text(encoding="utf-8")
    expected_categories = swift_enum_cases(source, "SumiImportCategory")
    expected_exclusions = swift_enum_cases(
        source, "SumiBackupV1ExcludedDataFamily"
    )
    if scope.get("includedCategories") != expected_categories:
        raise ValueError("Backup v1 included categories drifted from Swift authority")
    if scope.get("excludedDataFamilies") != expected_exclusions:
        raise ValueError("Backup v1 exclusions drifted from Swift authority")

    service = BACKUP_SERVICE_SOURCE.read_text(encoding="utf-8")
    if "warnings: [SumiBackupV1Scope.warning]" not in service:
        raise ValueError("backup archives must publish the SumiBackupV1Scope warning")

    families = {
        family.get("id"): family
        for family in inventory.get("durableFamilies", [])
        if isinstance(family, dict)
    }
    policy_requirements = {
        "startup-swiftdata": ("History", "permission decisions", "extension metadata"),
        "preferences-userdefaults": ("no UserDefaults preferences",),
        "permissions-json": ("excludes permission decisions",),
        "extension-packages": ("excludes extension metadata", "package payloads"),
        "logical-backups": ("SumiBackupV1Scope", "regular tabs only"),
    }
    for family_id, phrases in policy_requirements.items():
        family = families.get(family_id)
        if not isinstance(family, dict):
            raise ValueError(f"missing Backup v1 policy family: {family_id}")
        policy = family.get("backupRestorePolicy", "")
        for phrase in phrases:
            if phrase not in policy:
                raise ValueError(
                    f"{family_id}.backupRestorePolicy lost Backup v1 scope phrase: {phrase}"
                )

    roadmap = ROADMAP_PATH.read_text(encoding="utf-8")
    roadmap_requirements = (
        "Backup v1 includes profiles, spaces and themes, bookmarks, essentials, "
        "pinned launchers, folders, and regular tabs.",
        "history, permission decisions, extension metadata and payloads",
        "preferences, and session settings",
    )
    for phrase in roadmap_requirements:
        if phrase not in roadmap:
            raise ValueError(f"roadmap lost truthful Backup v1 scope: {phrase}")


def validate_fixtures(manifest: dict[str, object], fixture_test: str) -> dict[str, str]:
    if manifest.get("formatVersion") != 1:
        raise ValueError("fixture manifest formatVersion must be 1")
    provenance = manifest.get("provenance")
    if not isinstance(provenance, list) or not provenance:
        raise ValueError("fixture manifest must list provenance")
    provenance_ids: set[str] = set()
    for index, raw in enumerate(provenance):
        if not isinstance(raw, dict):
            raise ValueError(f"provenance[{index}] must be an object")
        for field in ("id", "description", "limitations"):
            require_text(raw, field, f"provenance[{index}]")
        if raw["id"] in provenance_ids:
            raise ValueError(f"duplicate provenance id: {raw['id']}")
        provenance_ids.add(raw["id"])
    fixtures = manifest.get("fixtures")
    if not isinstance(fixtures, list) or not fixtures:
        raise ValueError("fixture manifest must list fixtures")

    listed: dict[str, str] = {}
    for index, raw in enumerate(fixtures):
        if not isinstance(raw, dict):
            raise ValueError(f"fixtures[{index}] must be an object")
        context = f"fixtures[{index}]"
        for field in ("path", "sha256", "family", "role", "provenance", "test"):
            require_text(raw, field, context)
        path = raw["path"]
        if path in listed:
            raise ValueError(f"duplicate fixture path: {path}")
        listed[path] = raw["family"]
        if raw["provenance"] not in provenance_ids:
            raise ValueError(f"unknown fixture provenance: {raw['provenance']}")
        fixture_path = ROOT / path
        try:
            fixture_path.relative_to(FIXTURE_ROOT)
        except ValueError as error:
            raise ValueError(f"fixture escapes fixture root: {path}") from error
        if not fixture_path.is_file():
            raise ValueError(f"missing fixture: {path}")
        payload = fixture_path.read_bytes()
        if raw.get("bytes") != len(payload):
            raise ValueError(f"fixture byte count drifted: {path}")
        digest = hashlib.sha256(payload).hexdigest()
        if raw["sha256"] != digest:
            raise ValueError(f"fixture hash drifted: {path}")
        if raw["test"] not in fixture_test:
            raise ValueError(f"fixture test is missing: {raw['test']}")

    actual = {
        relative(path)
        for path in FIXTURE_ROOT.rglob("*")
        if path.is_file() and path != MANIFEST_PATH
    }
    listed_paths = set(listed)
    if listed_paths != actual:
        missing = sorted(actual - listed_paths)
        stale = sorted(listed_paths - actual)
        raise ValueError(f"fixture manifest mismatch; unlisted={missing}, stale={stale}")
    return listed


def validate_map(
    inventory: dict[str, object],
    discovered: dict[str, object],
    fixture_families: dict[str, str],
) -> None:
    if inventory.get("formatVersion") != 1:
        raise ValueError("persistence map formatVersion must be 1")
    validate_backup_v1_scope(inventory)
    families = inventory.get("durableFamilies")
    if not isinstance(families, list) or not families:
        raise ValueError("persistence map must list durableFamilies")

    required = (
        "id",
        "name",
        "classification",
        "technology",
        "versionOwner",
        "locationPolicy",
        "backupRestorePolicy",
        "corruptionRecoveryPolicy",
        "legacySources",
        "productionTypes",
        "semanticSources",
        "fixtures",
    )
    family_ids: set[str] = set()
    family_sources: dict[str, set[str]] = {}
    mapped_fixtures: list[str] = []
    mapped_models: set[tuple[str, str]] = set()
    for index, raw in enumerate(families):
        if not isinstance(raw, dict):
            raise ValueError(f"durableFamilies[{index}] must be an object")
        context = f"durableFamilies[{index}]"
        for field in required:
            if field not in raw:
                raise ValueError(f"{context}.{field} is required")
        for field in required[:9]:
            require_text(raw, field, context)
        family_id = raw["id"]
        if family_id in family_ids:
            raise ValueError(f"duplicate durable family: {family_id}")
        family_ids.add(family_id)
        if raw["classification"] not in {"authoritative", "cache", "backup", "recovery"}:
            raise ValueError(f"invalid classification for {family_id}")
        for field in ("productionTypes", "semanticSources", "fixtures"):
            if not isinstance(raw[field], list):
                raise ValueError(f"{context}.{field} must be an array")
        family_sources[family_id] = set(raw["semanticSources"])
        mapped_fixtures.extend(raw["fixtures"])
        for fixture in raw["fixtures"]:
            if fixture_families.get(fixture) != family_id:
                raise ValueError(
                    f"fixture {fixture} is not manifested for family {family_id}"
                )
        for model in raw.get("swiftDataModels", []):
            mapped_models.add((model["path"], model["type"]))

    if len(mapped_fixtures) != len(set(mapped_fixtures)):
        raise ValueError("a fixture is assigned to more than one durable family")
    fixture_paths = set(fixture_families)
    if set(mapped_fixtures) != fixture_paths:
        raise ValueError(
            f"fixtures absent from durable families: {sorted(fixture_paths - set(mapped_fixtures))}"
        )

    ownership = inventory.get("semanticSignalOwnership")
    if not isinstance(ownership, list):
        raise ValueError("semanticSignalOwnership must be an array")
    expected_signals: dict[tuple[str, str], str] = {}
    for index, raw in enumerate(ownership):
        if not isinstance(raw, dict):
            raise ValueError(f"semanticSignalOwnership[{index}] must be an object")
        for field in ("owner", "kind"):
            require_text(raw, field, f"semanticSignalOwnership[{index}]")
        owner = raw["owner"]
        if owner not in family_ids:
            raise ValueError(f"unknown semantic signal owner: {owner}")
        paths = raw.get("paths")
        if not isinstance(paths, list) or not paths:
            raise ValueError(f"semanticSignalOwnership[{index}].paths must be non-empty")
        for path in paths:
            if not isinstance(path, str) or not path:
                raise ValueError(f"semanticSignalOwnership[{index}] has an invalid path")
            signal = (raw["kind"], path)
            if signal in expected_signals:
                raise ValueError(f"duplicate semantic signal ownership: {signal}")
            if path not in family_sources[owner]:
                raise ValueError(
                    f"semantic signal {signal} is absent from {owner}.semanticSources"
                )
            expected_signals[signal] = owner

    exclusions = inventory.get("semanticExclusions")
    if not isinstance(exclusions, list):
        raise ValueError("semanticExclusions must be an array")
    for index, raw in enumerate(exclusions):
        if not isinstance(raw, dict):
            raise ValueError(f"semanticExclusions[{index}] must be an object")
        require_text(raw, "kind", f"semanticExclusions[{index}]")
        require_text(raw, "path", f"semanticExclusions[{index}]")
        require_text(raw, "reason", f"semanticExclusions[{index}]")
        signal = (raw["kind"], raw["path"])
        if signal in expected_signals:
            raise ValueError(f"semantic signal is both owned and excluded: {signal}")
        expected_signals[signal] = "excluded"

    actual_signals = {
        (signal["kind"], signal["path"])
        for signal in discovered["signals"]
    }
    expected_signal_set = set(expected_signals)
    uncovered = actual_signals - expected_signal_set
    stale = expected_signal_set - actual_signals
    if uncovered or stale:
        raise ValueError(
            f"semantic signal coverage mismatch; uncovered={sorted(uncovered)}, stale={sorted(stale)}"
        )

    owner_signals = inventory.get("versionOwnerSignals", [])
    if not isinstance(owner_signals, list):
        raise ValueError("versionOwnerSignals must be an array")
    for index, item in enumerate(owner_signals):
        if not isinstance(item, dict):
            raise ValueError(f"versionOwnerSignals[{index}] must be an object")
        for field in ("path", "declaration", "owner"):
            require_text(item, field, f"versionOwnerSignals[{index}]")
        if item["owner"] == "excluded":
            require_text(item, "reason", f"versionOwnerSignals[{index}]")
        elif item["owner"] not in family_ids:
            raise ValueError(f"unknown version owner family: {item['owner']}")
    expected_owners = {
        (item["path"], item["declaration"])
        for item in owner_signals
    }
    actual_owners = {
        (item["path"], item["declaration"])
        for item in discovered["versionOwners"]
    }
    if expected_owners != actual_owners:
        raise ValueError(
            "version owner coverage mismatch; "
            f"new={sorted(actual_owners - expected_owners)}, stale={sorted(expected_owners - actual_owners)}"
        )

    actual_models = {
        (item["path"], item["type"])
        for item in discovered["swiftDataModels"]
    }
    if mapped_models != actual_models:
        raise ValueError(
            "SwiftData model coverage mismatch; "
            f"new={sorted(actual_models - mapped_models)}, stale={sorted(mapped_models - actual_models)}"
        )

    if inventory.get("coreDataModels") != discovered["coreDataModels"]:
        raise ValueError("Core Data model inventory drifted")
    if inventory.get("coreDataCurrentVersions") != discovered["coreDataCurrentVersions"]:
        raise ValueError("Core Data current-version inventory drifted")

    operations = inventory.get("crossStoreOperations")
    if not isinstance(operations, list) or not operations:
        raise ValueError("crossStoreOperations must be a non-empty array")
    for index, raw in enumerate(operations):
        if not isinstance(raw, dict):
            raise ValueError(f"crossStoreOperations[{index}] must be an object")
        for field in ("operation", "stores", "ordering", "compensation", "atomicity"):
            if field not in raw or not raw[field]:
                raise ValueError(f"crossStoreOperations[{index}].{field} is required")
        unknown_stores = set(raw["stores"]) - family_ids
        if unknown_stores:
            raise ValueError(
                f"crossStoreOperations[{index}] names unknown stores: {sorted(unknown_stores)}"
            )

    ephemeral = inventory.get("ephemeralState")
    if not isinstance(ephemeral, list) or not ephemeral:
        raise ValueError("ephemeralState must be a non-empty array")

    serialized = json.dumps(inventory, sort_keys=True)
    if re.search(r"/Users/|/home/|file://", serialized):
        raise ValueError("persistence map must use logical locations, not user paths")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--print-discovered", action="store_true")
    args = parser.parse_args()
    discovered = discover()
    if args.print_discovered:
        print(json.dumps(discovered, indent=2, sort_keys=True))
        return 0
    try:
        inventory = load_json(MAP_PATH)
        manifest = load_json(MANIFEST_PATH)
        fixture_test = (ROOT / "SumiTests/PersistenceFixtureTests.swift").read_text(
            encoding="utf-8"
        )
        fixture_families = validate_fixtures(manifest, fixture_test)
        validate_map(inventory, discovered, fixture_families)
    except ValueError as error:
        print(f"persistence inventory audit failed: {error}", file=sys.stderr)
        return 1
    print("persistence inventory audit passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
