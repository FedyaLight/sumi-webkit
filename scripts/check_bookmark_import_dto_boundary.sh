#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

legacy_files=(
  "Sumi/Bookmarks/Store/BookmarkImportSource.swift"
  "Sumi/Bookmarks/Store/BookmarkOrFolder.swift"
  "Sumi/Bookmarks/Store/BookmarksImportSummary.swift"
  "Sumi/Bookmarks/SumiBookmarkImportExportAdapter.swift"
)

for file in "${legacy_files[@]}"; do
  guard_expect_absent_path 'retired bookmark import model/adapter' "$file"
done

legacy_symbols='(^|[^[:alnum:]_])(BookmarkImportSource|BookmarkImportReaderKind|BookmarkOrFolder|BookmarksImportSummary)([^[:alnum:]_]|$)'
legacy_references="$(
  guard_capture_matches \
    "$legacy_symbols" \
    -g '*.swift' Sumi/Bookmarks SumiTests
)"
if [[ -n "$legacy_references" ]]; then
  guard_record_failure \
    "bookmark import must use the canonical SumiBookmarkImport value model: $legacy_references"
fi

canonical_types=(
  SumiBookmarkImportReaderKind
  SumiBookmarkImportSource
  SumiBookmarkImportNode
  SumiBookmarksImportSummary
)
for type in "${canonical_types[@]}"; do
  guard_exact \
    "$type canonical declaration" \
    "$(
      guard_count_swift_matches \
        "^(enum|struct) ${type}\\b" \
        Sumi/Bookmarks
    )" \
    1
done

guard_expect_no_matches \
  'retired bookmark import adapter conversion seams' \
  '(storeBookmarkOrFolder|storeImportSummary|storeImportSource|storeReaderKind)' \
  -g '*.swift' Sumi/Bookmarks

canonical_source='Sumi/Bookmarks/Store/SumiBookmarkImportSource.swift'
guard_require_file "$canonical_source"
if (( $(
  guard_count_matches \
    '^extension SumiBookmarkImportSource \{' \
    "$canonical_source"
) == 0 )); then
  guard_record_failure \
    'bookmark parsers do not consume canonical SumiBookmarkImportSource directly'
fi

guard_finish 'bookmark import DTO boundary'
