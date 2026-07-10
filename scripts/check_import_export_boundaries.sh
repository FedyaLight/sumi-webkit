#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

service="Sumi/ImportExport/SumiBrowserImportService.swift"
status=0

legacy_applier="$(find Sumi/ImportExport -maxdepth 1 -name 'SumiImportApplier.swift' -print)"
if [[ -n "$legacy_applier" ]]; then
  printf 'The monolithic import applier must not be restored:\n%s\n' "$legacy_applier" >&2
  status=1
fi

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
  if [[ ! -f "$file" ]]; then
    printf 'Missing import transaction component: %s\n' "$file" >&2
    status=1
  fi
done

manager_coupling="$(grep -nH 'BrowserManager' "${transaction_files[@]}" 2>/dev/null || true)"
if [[ -n "$manager_coupling" ]]; then
  printf 'Import planning and transaction components must depend on narrow ports, not BrowserManager:\n%s\n' "$manager_coupling" >&2
  status=1
fi

import_owner_declarations="$(grep -nHE '^(final )?(class|struct|enum|protocol) [A-Za-z0-9_]*Import[A-Za-z0-9_]*Owner\b' Sumi/ImportExport/*.swift || true)"
if [[ -n "$import_owner_declarations" ]]; then
  printf 'Import responsibilities need concrete names instead of Owner surfaces:\n%s\n' "$import_owner_declarations" >&2
  status=1
fi

compression_imports="$(grep -nE '^import Compression$' "$service" || [[ $? -eq 1 ]])"
if [[ -n "$compression_imports" ]]; then
  printf 'SumiBrowserImportService must not import Compression directly:\n%s\n' "$compression_imports" >&2
  status=1
fi

parser_declarations="$(grep -nE '^(struct SumiArcImportParser|struct SumiArcImportResult|private struct ArcSpaceInfo|struct SumiZenImportParser|struct SumiZenImportResult|private enum SumiMozLZ4|enum SumiPortableFolderHierarchyRepair)' "$service" || [[ $? -eq 1 ]])"
if [[ -n "$parser_declarations" ]]; then
  printf 'Browser-specific import parsing and shared repair helpers must stay out of SumiBrowserImportService:\n%s\n' "$parser_declarations" >&2
  status=1
fi

file_preview_details="$(grep -nE '(importBrowser2ZenDocument|readBackup[(]|isSumiBackupCandidate)' "$service" || [[ $? -eq 1 ]])"
if [[ -n "$file_preview_details" ]]; then
  printf 'File preview decoding and backup detection must stay out of SumiBrowserImportService:\n%s\n' "$file_preview_details" >&2
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  echo "import/export boundary audit failed" >&2
  exit "$status"
fi

echo "import/export boundary audit passed"
