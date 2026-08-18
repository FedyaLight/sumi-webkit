#!/usr/bin/env python3
"""Verify the unified Sumi persistence boundary and immutable fixtures."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MAP_PATH = ROOT / "docs/persistence/persistence-map.json"
MANIFEST_PATH = ROOT / "SumiTests/Fixtures/Persistence/manifest.json"
FIXTURE_ROOT = MANIFEST_PATH.parent
FIXTURE_TEST_PATH = ROOT / "SumiTests/PersistenceFixtureTests.swift"
PRODUCTION_ROOTS = ("App", "Sumi", "Settings", "Packages")

FORBIDDEN_SOURCE_PATTERNS = {
    "SwiftData import": re.compile(r"^\s*import\s+SwiftData\b", re.MULTILINE),
    "Core Data import": re.compile(r"^\s*import\s+CoreData\b", re.MULTILINE),
    "SwiftData model": re.compile(r"\B@Model\b"),
    "SwiftData container": re.compile(r"\bModelContainer\b|\bModelContext\b"),
    "Core Data container": re.compile(
        r"\bNSPersistentContainer\b|\bNSPersistentStoreDescription\b"
    ),
}

FORBIDDEN_RUNTIME_NAMES = (
    "default.store",
    "SumiBookmarks.sqlite",
    "permission-state.v1.json",
    "live-folders.json",
    "DownloadApplications.json",
    "settings.adblock.siteOverrides",
    "settings.adblock.zapper.statesByPersistentProfileAndHost.v1",
    "SumiCompiledContentRuleListIdentifiersByName.v1",
)

REMOVED_SOURCES = (
    "Sumi/ImportExport/SumiImportTransactionFileJournal.swift",
    "Sumi/Permissions/SwiftDataPermissionStore.swift",
    "Sumi/Common/Database/SumiCoreDataDatabase.swift",
    "Sumi/Bookmarks/SumiCoreDataBookmarkRepository.swift",
    "Sumi/Bookmarks/Store/BookmarksModel.xcdatamodeld",
)


def fail(message: str) -> None:
    raise ValueError(message)


def load_object(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path.relative_to(ROOT)}: {error}")
    if not isinstance(value, dict):
        fail(f"{path.relative_to(ROOT)} must contain an object")
    return value


def production_sources() -> list[Path]:
    sources: list[Path] = []
    for relative_root in PRODUCTION_ROOTS:
        root = ROOT / relative_root
        if root.exists():
            sources.extend(root.rglob("*.swift"))
    return sorted(set(sources))


def validate_architecture(inventory: dict[str, object]) -> None:
    if inventory.get("formatVersion") != 2:
        fail("persistence map formatVersion must be 2")

    canonical = inventory.get("canonicalDatabase")
    if not isinstance(canonical, dict):
        fail("canonicalDatabase must be an object")
    if canonical.get("fileName") != "Sumi.sqlite":
        fail("Sumi.sqlite must be the canonical database")
    if canonical.get("schemaVersion") != 5:
        fail("canonical database schemaVersion must match current version 5")
    if canonical.get("owner") != "SumiDatabase":
        fail("SumiDatabase must own the canonical database")

    families = inventory.get("families")
    if not isinstance(families, list) or not families:
        fail("persistence map must list storage families")
    family_ids = {
        family.get("id")
        for family in families
        if isinstance(family, dict)
    }
    required_families = {
        "unified-database",
        "scalar-preferences",
        "platform-stores",
        "specialized-app-files",
        "rebuildable-caches",
        "user-authored-files",
        "memory-only",
    }
    if family_ids != required_families:
        fail(
            "persistence family inventory drifted: "
            f"expected={sorted(required_families)} actual={sorted(family_ids)}"
        )

    for removed_source in REMOVED_SOURCES:
        if (ROOT / removed_source).exists():
            fail(f"removed persistence source returned: {removed_source}")

    violations: list[str] = []
    for path in production_sources():
        source = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT).as_posix()
        for label, pattern in FORBIDDEN_SOURCE_PATTERNS.items():
            if pattern.search(source):
                violations.append(f"{relative}: {label}")
        for runtime_name in FORBIDDEN_RUNTIME_NAMES:
            if runtime_name in source:
                violations.append(f"{relative}: obsolete runtime name {runtime_name}")
        creates_database = "DatabasePool(" in source or "DatabaseQueue(" in source
        is_canonical_database = (
            relative == "Sumi/Persistence/SumiDatabase.swift"
        )
        is_external_sqlite_artifact = (
            relative.startswith("Sumi/ImportExport/")
            and relative.endswith("SQLiteArtifactWriter.swift")
            and "Sumi.sqlite" not in source
        )
        if (
            creates_database
            and not is_canonical_database
            and not is_external_sqlite_artifact
        ):
            violations.append(
                f"{relative}: creates a database outside SumiDatabase"
            )
    if violations:
        fail("unified persistence violations:\n  " + "\n  ".join(violations))

    database_source = (
        ROOT / "Sumi/Persistence/SumiDatabase.swift"
    ).read_text(encoding="utf-8")
    required_database_fragments = (
        "DatabasePool(",
        "PRAGMA foreign_keys = ON",
        "PRAGMA user_version",
        "PRAGMA user_version = 5",
        "unsupportedSchemaVersion",
    )
    for fragment in required_database_fragments:
        if fragment not in database_source:
            fail(f"SumiDatabase lost required boundary: {fragment}")

    project = (ROOT / "Sumi.xcodeproj/project.pbxproj").read_text(
        encoding="utf-8"
    )
    if ".xcdatamodeld" in project:
        fail("Xcode project still references a Core Data model")


def validate_fixtures(
    inventory: dict[str, object],
    manifest: dict[str, object],
) -> None:
    if manifest.get("formatVersion") != 1:
        fail("fixture manifest formatVersion must be 1")
    fixtures = manifest.get("fixtures")
    if not isinstance(fixtures, list) or not fixtures:
        fail("fixture manifest must list fixtures")

    family_ids = {
        family.get("id")
        for family in inventory["families"]
        if isinstance(family, dict)
    }
    fixture_test = FIXTURE_TEST_PATH.read_text(encoding="utf-8")
    listed_paths: set[str] = set()
    for index, item in enumerate(fixtures):
        if not isinstance(item, dict):
            fail(f"fixtures[{index}] must be an object")
        required = (
            "path",
            "sha256",
            "bytes",
            "family",
            "role",
            "provenance",
            "test",
        )
        if any(field not in item for field in required):
            fail(f"fixtures[{index}] is incomplete")
        relative_path = item["path"]
        if not isinstance(relative_path, str) or relative_path in listed_paths:
            fail(f"invalid or duplicate fixture path: {relative_path}")
        listed_paths.add(relative_path)
        if item["family"] not in family_ids:
            fail(f"fixture has unknown family: {relative_path}")
        if item["test"] not in fixture_test:
            fail(f"fixture test is missing: {item['test']}")

        path = ROOT / relative_path
        if not path.is_file():
            fail(f"missing fixture: {relative_path}")
        payload = path.read_bytes()
        if item["bytes"] != len(payload):
            fail(f"fixture byte count drifted: {relative_path}")
        if item["sha256"] != hashlib.sha256(payload).hexdigest():
            fail(f"fixture hash drifted: {relative_path}")

    actual_paths = {
        path.relative_to(ROOT).as_posix()
        for path in FIXTURE_ROOT.rglob("*")
        if path.is_file() and path != MANIFEST_PATH
    }
    if listed_paths != actual_paths:
        fail(
            "fixture manifest mismatch: "
            f"unlisted={sorted(actual_paths - listed_paths)} "
            f"stale={sorted(listed_paths - actual_paths)}"
        )


def main() -> int:
    try:
        inventory = load_object(MAP_PATH)
        manifest = load_object(MANIFEST_PATH)
        validate_architecture(inventory)
        validate_fixtures(inventory, manifest)
    except ValueError as error:
        print(f"persistence inventory audit failed: {error}", file=sys.stderr)
        return 1
    print("persistence inventory audit passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
