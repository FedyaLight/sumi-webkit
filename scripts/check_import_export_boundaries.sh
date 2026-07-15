#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

service="Sumi/ImportExport/SumiBrowserImportService.swift"
guard_require_directory Sumi/ImportExport
guard_require_file "$service"
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

compression_imports="$(guard_capture_matches '^import Compression$' "$service")"
if [[ -n "$compression_imports" ]]; then
  guard_record_failure "SumiBrowserImportService imports Compression directly: $compression_imports"
fi

parser_declarations="$(
  guard_capture_matches \
    '^(struct SumiArcImportParser|struct SumiArcImportResult|private struct ArcSpaceInfo|struct SumiZenImportParser|struct SumiZenImportResult|private enum SumiMozLZ4|enum SumiPortableFolderHierarchyRepair)' \
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
