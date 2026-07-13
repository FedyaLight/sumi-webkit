#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

python3 - <<'PY'
from pathlib import Path

manager_path = Path("Sumi/Bookmarks/SumiBookmarkManager.swift")
manager = manager_path.read_text()

required = (
    "@Published private(set) var publicationRevision",
    "private(set) var revision",
    "private var publicationTask: Task<Void, Never>?",
    "private func recordLocalMutation()",
    "private func publishPendingChanges()",
    "private func refreshFoldersCacheIfNeeded()",
)
for token in required:
    if token not in manager:
        raise SystemExit(f"bookmark publication guard: missing {token}")

if manager.count("publicationTask = Task") != 1:
    raise SystemExit("bookmark publication guard: publication must have one scheduler")

for forbidden in ("Timer", "asyncAfter", ".debounce(", ".throttle("):
    if forbidden in manager:
        raise SystemExit(f"bookmark publication guard: forbidden scheduler {forbidden}")

def function_body(name: str) -> str:
    marker = f"func {name}("
    start = manager.find(marker)
    if start < 0:
        raise SystemExit(f"bookmark publication guard: missing {name}")
    brace = manager.find("{", start)
    depth = 0
    for index in range(brace, len(manager)):
        if manager[index] == "{":
            depth += 1
        elif manager[index] == "}":
            depth -= 1
            if depth == 0:
                return manager[brace:index + 1]
    raise SystemExit(f"bookmark publication guard: unterminated {name}")

incremental_mutations = (
    "createBookmark",
    "updateBookmark",
    "createFolder",
    "createFolderWithBookmarks",
    "updateFolder",
    "removeEntities",
    "moveEntities",
)
for name in incremental_mutations:
    if "reload(" in function_body(name):
        raise SystemExit(
            f"bookmark publication guard: {name} must apply a delta, not reload"
        )

consumer_paths = (
    Path("Sumi/Bookmarks/SumiBookmarksPageViewModel.swift"),
    Path("App/SumiBookmarksCommands.swift"),
)
for path in consumer_paths:
    source = path.read_text()
    if "$revision" in source:
        raise SystemExit(
            f"bookmark publication guard: {path} observes semantic revision"
        )
    if "$publicationRevision" not in source:
        raise SystemExit(
            f"bookmark publication guard: {path} misses coalesced publication"
        )

repository = Path("Sumi/Bookmarks/SumiBookmarkRepository.swift").read_text()
if "removeEntities(ids: [String]) throws -> [SumiBookmark]" not in repository:
    raise SystemExit(
        "bookmark publication guard: recursive removal delta is not explicit"
    )
PY

echo "bookmark publication boundary guard passed"
