#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$root"
catalog="$root/Sumi/Managers/ExtensionManager/InstalledExtensionCatalog.swift"
guard_require_file "$catalog"

publish_line="$(
  guard_capture_matches '^    func publish\(' "$catalog" -m 1 | cut -d: -f1
)"
fetch_guard_line="$(
  guard_capture_matches 'guard result\.didFetchPersistedMetadata else' \
    "$catalog" -m 1 | cut -d: -f1
)"
set_all_line="$(
  guard_capture_matches 'environment\.installedRecords\.setAll' \
    "$catalog" -m 1 | cut -d: -f1
)"
loaded_line="$(
  guard_capture_matches 'environment\.markCatalogLoaded\(\)' \
    "$catalog" -m 1 | cut -d: -f1
)"

if [[ -z "$publish_line" || -z "$fetch_guard_line" \
    || -z "$set_all_line" || -z "$loaded_line" ]] \
    || (( publish_line >= fetch_guard_line )) \
    || (( fetch_guard_line >= set_all_line )) \
    || (( set_all_line >= loaded_line )); then
    echo "failed metadata fetch must be rejected before catalog and readiness publication" >&2
    exit 1
fi

echo "installed-extension catalog boundary passed"
