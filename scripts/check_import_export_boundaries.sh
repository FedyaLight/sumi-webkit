#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

service="Sumi/ImportExport/SumiBrowserImportService.swift"
guard_require_directory Sumi/ImportExport
guard_require_directory Sumi/ImportExport/Sources
guard_require_file "$service"
guard_require_file Sumi/ImportExport/Sources/SumiImportSQLiteSnapshotReader.swift
guard_require_file Sumi/ImportExport/Sources/SumiMozillaLZ4Decoder.swift
guard_expect_absent_path \
  'monolithic import applier' \
  Sumi/ImportExport/SumiImportApplier.swift

transaction_files=(
  Sumi/ImportExport/SumiImportBookmarkStore.swift
  Sumi/ImportExport/SumiImportPlanBuilder.swift
  Sumi/ImportExport/SumiImportRuntimeMaterializer.swift
  Sumi/ImportExport/SumiImportRuntimeState.swift
  Sumi/ImportExport/SumiImportRuntimeStore.swift
  Sumi/ImportExport/SumiImportTransaction.swift
  Sumi/ImportExport/SumiImportTransactionModels.swift
)
for file in "${transaction_files[@]}"; do
  guard_require_file "$file"
done

manager_coupling="$(guard_capture_matches 'BrowserManager' "${transaction_files[@]}")"
if [[ -n "$manager_coupling" ]]; then
  guard_record_failure "import transaction components depend on BrowserManager: $manager_coupling"
fi

import_owner_declarations="$(
  guard_capture_matches \
    '^(final )?(class|struct|enum|protocol) [A-Za-z0-9_]*Import[A-Za-z0-9_]*Owner\b' \
    -g '*.swift' Sumi/ImportExport
)"
if [[ -n "$import_owner_declarations" ]]; then
  guard_record_failure "import responsibilities use generic Owner surfaces: $import_owner_declarations"
fi

# Decoding, database access, and cryptography belong to the source readers, not
# to the service that merely dispatches to them.
low_level_imports="$(guard_capture_matches '^import (Compression|SQLite3|CommonCrypto)$' "$service")"
if [[ -n "$low_level_imports" ]]; then
  guard_record_failure "SumiBrowserImportService imports a source-decoding module directly: $low_level_imports"
fi

# Raw SQLite handles are opened in exactly two places: the snapshot reader that
# copies WAL sidecars, and the bookmark import source it is being migrated from.
sqlite_open_hits="$(
  guard_capture_matches \
    'sqlite3_open' \
    --glob '*.swift' Sumi SidebarChrome App Packages
)"
while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  case "${match%%:*}" in
    Sumi/ImportExport/Sources/SumiImportSQLiteSnapshotReader.swift) ;;
    Sumi/Bookmarks/Store/SumiBookmarkImportSource.swift) ;;
    *) guard_record_failure "SQLite is opened outside the import snapshot reader: $match" ;;
  esac
done <<<"$sqlite_open_hits"

parser_declarations="$(
  guard_capture_matches \
    '^(struct SumiArcImportParser|struct SumiArcImportResult|struct ArcSpaceInfo|struct SumiZenImportParser|struct SumiZenImportResult|enum SumiMozillaLZ4Decoder|enum SumiPortableFolderHierarchyRepair)' \
    "$service"
)"
if [[ -n "$parser_declarations" ]]; then
  guard_record_failure "browser-specific parsing remains in SumiBrowserImportService: $parser_declarations"
fi

file_preview_details="$(
  guard_capture_matches \
    '(importBrowser2ZenDocument|readBackup[(]|isSumiBackupCandidate)' \
    "$service"
)"
if [[ -n "$file_preview_details" ]]; then
  guard_record_failure "file preview/backup decoding remains in SumiBrowserImportService: $file_preview_details"
fi

guard_finish 'import/export boundary audit'
