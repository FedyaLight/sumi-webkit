#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fixture_dir="SumiUITests/Fixtures/SmokeStore"
manifest="$fixture_dir/sumi-ui-smoke-store-manifest.json"
fixture_support="SumiUITests/SumiLaunchSmokeUIFixtureSupport.swift"
fixture_resolver="SumiUITests/SumiLaunchSmokeStoreFixture.swift"
test_case="SumiUITests/SumiLaunchSmokeUITestCase.swift"

for file in "$manifest" "$fixture_support" "$fixture_resolver" "$test_case"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: UI smoke fixture boundary file missing: %s\n' "$file" >&2
    exit 1
  fi
done

python3 - "$fixture_dir" "$manifest" <<'PY'
import hashlib
import json
import pathlib
import sys

fixture_dir = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

expected_names = ["default.store", "default.store-shm", "default.store-wal"]
if manifest.get("version") != 1:
    raise SystemExit("error: UI smoke fixture manifest version must be 1")
if manifest.get("family") != "sumi-ui-smoke-startup-swiftdata":
    raise SystemExit("error: UI smoke fixture manifest family is not the pinned UI family")
if [entry.get("name") for entry in manifest.get("files", [])] != expected_names:
    raise SystemExit(f"error: UI smoke fixture manifest must list exact ordered family {expected_names}")

provenance = manifest.get("provenance", {})
required_provenance = {
    "sourcePath",
    "sourceFamily",
    "sourceProvenance",
    "copiedForUIOwnershipAt",
}
if set(provenance) != required_provenance:
    raise SystemExit("error: UI smoke fixture provenance fields are incomplete or unexpected")

actual_names = sorted(
    path.name for path in fixture_dir.iterdir()
    if path.name != manifest_path.name
)
if actual_names != sorted(expected_names):
    raise SystemExit(
        f"error: UI smoke fixture directory must contain only the exact SQLite family; found {actual_names}"
    )

for entry in manifest["files"]:
    path = fixture_dir / entry["name"]
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"error: UI smoke fixture member must be a regular non-symlink: {path}")
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if len(data) != entry.get("bytes") or digest != entry.get("sha256"):
        raise SystemExit(
            f"error: UI smoke fixture integrity mismatch for {path}: "
            f"bytes={len(data)} sha256={digest}"
        )
PY

if rg -n 'Thread\.sleep' SumiUITests --glob '*.swift'; then
  echo 'error: SumiUITests must synchronize on observable UI state, not Thread.sleep' >&2
  exit 1
fi

runtime_files=(
  "$fixture_support"
  "$fixture_resolver"
  "$test_case"
)
forbidden_runtime_pattern='getpwuid|homeDirectoryForCurrentUser|NSHomeDirectory|Library/Application Support/com\.sumi\.browser/default\.store|SumiTests/Fixtures|#filePath'
if rg -n "$forbidden_runtime_pattern" "${runtime_files[@]}"; then
  echo 'error: UI fixture runtime must not resolve source-tree, home-directory, or developer app-support state' >&2
  exit 1
fi

python3 - "$fixture_support" "$fixture_resolver" "$test_case" <<'PY'
import pathlib
import sys

support = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
resolver = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
test_case = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")

required_resolver_tokens = [
    "Bundle(for: SumiLaunchSmokeUITestCase.self)",
    "try family.verifyIntegrity()",
    "func copyVerifiedFamily",
]
required_support_tokens = [
    "SumiSmokeStoreFixture.resolveBundledFamily()",
    "fixtureFamily.copyVerifiedFamily(to: directory)",
    "seedSmokeStore(at: storeURL)",
]
required_launch_tokens = [
    "if smokeAppSupportURL == nil",
    "_ = try prepareSmokeStoreURL()",
]

for token in required_resolver_tokens:
    if token not in resolver:
        raise SystemExit(f"error: UI fixture resolver lost semantic boundary token: {token}")
for token in required_support_tokens:
    if token not in support:
        raise SystemExit(f"error: UI fixture preparation lost semantic boundary token: {token}")
if support.index("fixtureFamily.copyVerifiedFamily(to: directory)") > support.index("seedSmokeStore(at: storeURL)"):
    raise SystemExit("error: UI smoke rows must be seeded only after the verified family copy")
for token in required_launch_tokens:
    if token not in test_case:
        raise SystemExit(f"error: UI launch path can bypass hermetic fixture preparation: {token}")
PY

echo "UI test fixture boundary passed"
