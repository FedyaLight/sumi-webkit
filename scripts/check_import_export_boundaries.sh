#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

service="Sumi/ImportExport/SumiBrowserImportService.swift"
status=0

compression_imports="$(grep -nE '^import Compression$' "$service" || [[ $? -eq 1 ]])"
if [[ -n "$compression_imports" ]]; then
  printf 'SumiBrowserImportService must not import Compression directly:\n%s\n' "$compression_imports" >&2
  status=1
fi

parser_declarations="$(grep -nE '^(struct SumiZenImportParser|struct SumiZenImportResult|private enum SumiMozLZ4|enum SumiPortableFolderHierarchyRepair)' "$service" || [[ $? -eq 1 ]])"
if [[ -n "$parser_declarations" ]]; then
  printf 'Zen import parsing and shared repair helpers must stay out of SumiBrowserImportService:\n%s\n' "$parser_declarations" >&2
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  echo "import/export boundary audit failed" >&2
  exit "$status"
fi

echo "import/export boundary audit passed"
