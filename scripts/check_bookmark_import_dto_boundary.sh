#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0
legacy_files=(
  "Sumi/Bookmarks/Store/BookmarkImportSource.swift"
  "Sumi/Bookmarks/Store/BookmarkOrFolder.swift"
  "Sumi/Bookmarks/Store/BookmarksImportSummary.swift"
  "Sumi/Bookmarks/SumiBookmarkImportExportAdapter.swift"
)

for file in "${legacy_files[@]}"; do
  if [[ -e "$file" ]]; then
    printf 'Retired bookmark import model/adapter file was restored: %s\n' "$file" >&2
    status=1
  fi
done

legacy_symbols='(^|[^[:alnum:]_])(BookmarkImportSource|BookmarkImportReaderKind|BookmarkOrFolder|BookmarksImportSummary)([^[:alnum:]_]|$)'
legacy_references="$(grep -RInE --include='*.swift' "$legacy_symbols" Sumi/Bookmarks SumiTests || true)"
if [[ -n "$legacy_references" ]]; then
  printf 'Bookmark import must use the single SumiBookmarkImport value model:\n%s\n' "$legacy_references" >&2
  status=1
fi

canonical_types=(
  SumiBookmarkImportReaderKind
  SumiBookmarkImportSource
  SumiBookmarkImportNode
  SumiBookmarksImportSummary
)
for type in "${canonical_types[@]}"; do
  count="$(grep -RhcE "^(enum|struct) ${type}\\b" Sumi/Bookmarks --include='*.swift' | awk '{ total += $1 } END { print total + 0 }')"
  if [[ "$count" -ne 1 ]]; then
    printf 'Expected exactly one %s declaration, found %s.\n' "$type" "$count" >&2
    status=1
  fi
done

if grep -RInE --include='*.swift' '(storeBookmarkOrFolder|storeImportSummary|storeImportSource|storeReaderKind)' Sumi/Bookmarks; then
  echo 'Bookmark import adapter conversion seams must not be restored.' >&2
  status=1
fi

if ! grep -q '^extension SumiBookmarkImportSource {' Sumi/Bookmarks/Store/SumiBookmarkImportSource.swift; then
  echo 'Bookmark parsers must consume the canonical SumiBookmarkImportSource directly.' >&2
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  echo 'bookmark import DTO boundary failed' >&2
  exit "$status"
fi

echo 'bookmark import DTO boundary passed'
