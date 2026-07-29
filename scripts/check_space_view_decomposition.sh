#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

space_root="Sumi/Components/Sidebar/SpaceSection"
section_files=(
  "$space_root/SpaceSidebarListView.swift"
  "$space_root/SpacePinnedListEntryViews.swift"
  "$space_root/SpaceRegularSplitGroupEntryView.swift"
  "$space_root/SpaceRegularTabActionOwner.swift"
  "$space_root/SpaceRegularTabEntryView.swift"
  "$space_root/SpaceScrollChrome.swift"
  "$space_root/TabFolderBodyEntryViews.swift"
  "$space_root/TabFolderHeaderRow.swift"
  "$space_root/TabFolderHeaderView.swift"
)
guard_require_directory "$space_root"
for file in "${section_files[@]}" "$space_root/SpaceView.swift"; do
  guard_require_file "$file"
done
guard_expect_no_matches \
  'retired split placeholder policy returned' \
  'SplitPlaceholderRow|ShortcutRestoreGap|SpaceShortcutRestore|shortcutRestoreSession|onPrepareShortcutRestoreGap|onPerformShortcutRestoreWithPreparedGap' \
  -g '*.swift' "$space_root"

space_extension_hits="$(guard_capture_matches '^extension SpaceView\b' "$space_root" -g '*.swift')"
if [[ -n "$space_extension_hits" ]]; then
  printf '%s\n' "$space_extension_hits"
  echo "SpaceView decomposition guard: feature-section extensions may not regrow" >&2
  exit 1
fi

for declaration in \
  'struct SpaceSidebarListView: View' \
  'struct SpaceSidebarListContentView: View' \
  'struct SpaceFlatFolderHeaderView: View' \
  'struct SpacePinnedShortcutEntryView: View' \
  'struct SpacePinnedSplitGroupEntryView: View' \
  'struct SpaceRegularTabEntryView: View' \
  'struct SpaceRegularSplitGroupEntryView: View' \
  'struct SpaceRegularTabActionOwner' \
  'struct TabFolderShortcutEntryView: View' \
  'struct TabFolderLiveItemEntryView: View' \
  'struct TabFolderSplitGroupEntryView: View' \
  'struct SpaceScrollChromeSurface<Content: View>: View' \
  'enum SpacePinnedDisclosureProjection'; do
  declaration_count="$(guard_count_matches "$declaration" -F "$space_root")"
  if (( declaration_count == 0 )); then
    echo "SpaceView decomposition guard: missing semantic boundary: $declaration" >&2
    exit 1
  fi
done

broad_bag_hits="$(
  guard_capture_matches '\bSpaceView(Context|Dependencies|Actions|Model)\b' "$space_root" -g '*.swift'
)"
if [[ -n "$broad_bag_hits" ]]; then
  printf '%s\n' "$broad_bag_hits"
  echo "SpaceView decomposition guard: broad SpaceView bags are forbidden" >&2
  exit 1
fi

relay_hits="$(
  guard_capture_matches '\b(ObservableObject|@Published)\b' \
    "$space_root/SpacePinnedListEntryViews.swift" \
    "$space_root/SpaceRegularSplitGroupEntryView.swift" \
    "$space_root/SpaceRegularTabEntryView.swift" \
    "$space_root/SpaceScrollChrome.swift" \
    "$space_root/TabFolderBodyEntryViews.swift" \
    "$space_root/TabFolderHeaderRow.swift" \
    "$space_root/TabFolderHeaderView.swift" \
    "$space_root/SpaceView.swift"
)"
if [[ -n "$relay_hits" ]]; then
  printf '%s\n' "$relay_hits"
  echo "SpaceView decomposition guard: blanket observable relays are forbidden" >&2
  exit 1
fi

python3 - "$space_root" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
roots = {
    "SpaceView.swift": ["SpaceView"],
    "SpaceSidebarListView.swift": [
        "SpaceSidebarListView", "SpaceSidebarListContentView",
        "SpaceFlatFolderHeaderView",
    ],
    "SpacePinnedListEntryViews.swift": [
        "SpacePinnedShortcutEntryView", "SpacePinnedSplitGroupEntryView",
    ],
    "SpaceRegularSplitGroupEntryView.swift": ["SpaceRegularSplitGroupEntryView"],
    "SpaceRegularTabEntryView.swift": ["SpaceRegularTabEntryView"],
    "SpaceScrollChrome.swift": ["SpaceScrollChromeSurface"],
    "TabFolderBodyEntryViews.swift": [
        "TabFolderShortcutEntryView", "TabFolderLiveItemEntryView",
        "TabFolderSplitGroupEntryView",
    ],
    "TabFolderHeaderRow.swift": ["TabFolderHeaderRow"],
    "TabFolderHeaderView.swift": ["TabFolderHeaderView"],
}

def mask_comments_and_strings(source: str) -> str:
    """Mask Swift comments and strings while preserving byte offsets/newlines."""
    result = list(source)
    index = 0
    length = len(source)

    def blank(start: int, end: int) -> None:
        for position in range(start, end):
            if result[position] != "\n":
                result[position] = " "

    while index < length:
        if source.startswith("//", index):
            end = source.find("\n", index + 2)
            if end < 0:
                end = length
            blank(index, end)
            index = end
            continue

        if source.startswith("/*", index):
            start = index
            depth = 1
            index += 2
            while index < length and depth:
                if source.startswith("/*", index):
                    depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            if depth:
                raise SystemExit("SpaceView decomposition guard: unterminated block comment")
            blank(start, index)
            continue

        hash_count = 0
        quote_index = index
        while quote_index < length and source[quote_index] == "#":
            hash_count += 1
            quote_index += 1
        if quote_index < length and source[quote_index] == '"':
            start = index
            triple = source.startswith('"""', quote_index)
            delimiter = ('"""' if triple else '"') + ("#" * hash_count)
            index = quote_index + (3 if triple else 1)
            while index < length:
                if source.startswith(delimiter, index):
                    index += len(delimiter)
                    break
                if not triple and hash_count == 0 and source[index] == "\\":
                    index = min(index + 2, length)
                else:
                    index += 1
            else:
                raise SystemExit("SpaceView decomposition guard: unterminated string literal")
            blank(start, index)
            continue

        index += 1

    return "".join(result)


def block(source: str, opening_brace: int, description: str) -> str:
    depth = 0
    for index in range(opening_brace, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[opening_brace + 1:index]
    raise SystemExit(f"SpaceView decomposition guard: unterminated {description}")


def struct_body(source: str, name: str, requires_view: bool = True) -> str:
    inheritance = r"\s*:\s*View" if requires_view else r"[^{{]*"
    match = re.search(
        rf"\bstruct\s+{re.escape(name)}(?:<[^{{]+>)?{inheritance}\s*{{",
        source,
    )
    if not match:
        kind = "View declaration" if requires_view else "declaration"
        raise SystemExit(f"SpaceView decomposition guard: missing {kind} {name}")
    start = source.find("{", match.start())
    return block(source, start, f"declaration {name}")


def view_body(struct_source: str, name: str) -> str:
    match = re.search(r"\bvar\s+body\s*:\s*some\s+View\s*{", struct_source)
    if not match:
        raise SystemExit(f"SpaceView decomposition guard: missing body on {name}")
    return block(struct_source, struct_source.find("{", match.start()), f"body on {name}")


def root_properties(struct_source: str) -> list[tuple[str, str, str]]:
    properties = []
    depth = 0
    pattern = re.compile(
        r"^\s*((?:(?:@\w+(?:\([^)]*\))?\s+)|"
        r"(?:(?:private|fileprivate|internal|package|public|static|nonisolated)\s+))*)"
        r"(let|var)\s+(\w+)\s*(?::\s*([^={]+))?"
    )
    for line in struct_source.splitlines():
        if depth == 0:
            match = pattern.match(line)
            if match and "static" not in match.group(1).split():
                is_computed = match.group(2) == "var" and "{" in line and "=" not in line
                if not is_computed:
                    properties.append(
                        (match.group(2), match.group(3), (match.group(4) or "").strip())
                    )
        depth += line.count("{") - line.count("}")
    return properties


def call_labels(source: str, callee: str) -> list[set[str]]:
    calls = []
    pattern = re.compile(rf"\b{re.escape(callee)}\s*\(")
    cursor = 0
    while match := pattern.search(source, cursor):
        opening = source.find("(", match.start())
        depth = 0
        brace_depth = 0
        bracket_depth = 0
        segment_start = opening + 1
        segments = []
        closing = None
        for index in range(opening, len(source)):
            char = source[index]
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    segments.append(source[segment_start:index])
                    closing = index
                    break
            elif char == "{" and depth >= 1:
                brace_depth += 1
            elif char == "}" and depth >= 1:
                brace_depth -= 1
            elif char == "[" and depth >= 1:
                bracket_depth += 1
            elif char == "]" and depth >= 1:
                bracket_depth -= 1
            elif char == "," and depth == 1 and brace_depth == 0 and bracket_depth == 0:
                segments.append(source[segment_start:index])
                segment_start = index + 1
        if closing is None:
            raise SystemExit(
                f"SpaceView decomposition guard: unterminated call to {callee}"
            )
        labels = set()
        for segment in segments:
            label = re.match(r"\s*([A-Za-z_]\w*)\s*:", segment)
            if label:
                labels.add(label.group(1))
        calls.append(labels)
        cursor = closing + 1
    return calls


sources = {path: path.read_text() for path in root.glob("*.swift")}
masked_sources = {path: mask_comments_and_strings(source) for path, source in sources.items()}
view_structs: dict[str, tuple[Path, str]] = {}
view_pattern = re.compile(r"\bstruct\s+(\w+)(?:<[^{}]+>)?\s*:\s*View\s*{")
for path, source in masked_sources.items():
    for match in view_pattern.finditer(source):
        name = match.group(1)
        if name in view_structs:
            raise SystemExit(f"SpaceView decomposition guard: duplicate View declaration {name}")
        opening = source.find("{", match.start())
        view_structs[name] = (path, block(source, opening, f"View declaration {name}"))

for filename, names in roots.items():
    path = root / filename
    source = masked_sources[path]
    if filename != "SpaceSidebarListView.swift" and len(source.splitlines()) > 500:
        raise SystemExit(f"SpaceView decomposition guard: monolith regrowth in {filename}")
    for name in names:
        body = struct_body(source, name)
        if "@EnvironmentObject" in body or "SidebarDragState" in body:
            raise SystemExit(
                f"SpaceView decomposition guard: coarse drag observation leaked into renderer {name}"
            )

permitted_coarse_drag_readers = set()
drag_reader_pattern = re.compile(
    r"@EnvironmentObject\b(?:\s*\([^)]*\))?\s+"
    r"(?:(?:private|fileprivate|internal|package|public)\s+)?"
    r"var\s+\w+\s*:\s*SidebarDragState\b"
)
actual_drag_readers = {
    name for name, (_, body) in view_structs.items() if drag_reader_pattern.search(body)
}
unexpected_drag_readers = actual_drag_readers - permitted_coarse_drag_readers
if unexpected_drag_readers:
    raise SystemExit(
        "SpaceView decomposition guard: coarse drag observation reached unexpected "
        f"views {sorted(unexpected_drag_readers)}"
    )

for name in {
    "SpacePinnedDragSnapshot", "SpaceRegularDragSnapshot", "SidebarFolderDragSnapshot"
}:
    declaration = None
    for source in masked_sources.values():
        if re.search(rf"\bstruct\s+{re.escape(name)}\b", source):
            declaration = struct_body(source, name, requires_view=False)
            break
    if declaration is None:
        raise SystemExit(f"SpaceView decomposition guard: missing snapshot {name}")
    properties = root_properties(declaration)
    mutable_fields = {property_name for kind, property_name, _ in properties if kind == "var"}
    if mutable_fields:
        raise SystemExit(
            f"SpaceView decomposition guard: {name} must remain an immutable snapshot; "
            f"found mutable fields {sorted(mutable_fields)}"
        )

space_view_source = view_structs["SpaceView"][1]
if "SidebarDragState" in space_view_source or re.search(r"\bdragState\s*\.", space_view_source):
    raise SystemExit("SpaceView decomposition guard: SpaceView may not observe broad drag state")
if not re.search(
    r"\brenderMode\s*\.\s*resolvesInteraction\s*\(\s*"
    r"allowsInteraction\s*:\s*allowsInteraction\s*\)",
    space_view_source,
):
    raise SystemExit(
        "SpaceView decomposition guard: SpaceView must resolve the exact fail-closed "
        "render-mode and runtime interaction gate"
    )

folder_interaction_views = {
    "SpaceSidebarListView", "SpaceSidebarListContentView",
    "SpaceFlatFolderHeaderView", "SpacePinnedShortcutEntryView",
    "SpacePinnedSplitGroupEntryView", "SpaceRegularTabEntryView",
    "SpaceRegularSplitGroupEntryView", "TabFolderHeaderView",
    "TabFolderShortcutEntryView", "TabFolderLiveItemEntryView",
    "TabFolderSplitGroupEntryView",
}
for name in folder_interaction_views:
    body = view_structs[name][1]
    properties = root_properties(body)
    if any("SpaceViewRenderMode" in property_type for _, _, property_type in properties):
        raise SystemExit(
            f"SpaceView decomposition guard: {name} must consume the exact interaction "
            "gate instead of re-deriving it from render mode"
        )
    gates = [
        property_name for _, property_name, property_type in properties
        if property_name == "isInteractive" and property_type == "Bool"
    ]
    if len(gates) != 1:
        raise SystemExit(
            f"SpaceView decomposition guard: {name} must store exactly one Bool "
            "isInteractive gate"
        )
# Drop commits use the ordinary content-layout animation in the list sections;
# whole-surface suppression must not regrow around SpaceView.
if re.search(r"\bSpaceDropCommitSignalReader\b", space_view_source):
    raise SystemExit(
        "SpaceView decomposition guard: whole-surface drop commit suppression "
        "may not regrow around SpaceView"
    )

adoption = {
    "SpaceSidebarListContentView": {
        "SpaceFlatFolderHeaderView",
        "SpacePinnedShortcutEntryView", "SpacePinnedSplitGroupEntryView",
        "SpaceRegularTabEntryView", "SpaceRegularSplitGroupEntryView",
        "TabFolderShortcutEntryView", "TabFolderLiveItemEntryView",
        "TabFolderSplitGroupEntryView",
    },
}
for parent, children in adoption.items():
    parent_body = masked_sources[view_structs[parent][0]]
    for child in children:
        if not call_labels(parent_body, child):
            raise SystemExit(
                f"SpaceView decomposition guard: {parent} does not adopt {child}"
            )

forbidden_parent_calls = {
    "SpaceSidebarListContentView": {
        "SpaceTab", "SplitGroupSidebarRow", "ShortcutSidebarRow",
        "ShortcutHostedSplitGroupRow", "makeSidebarTabContextMenuEntries",
    },
}
for parent, forbidden_callees in forbidden_parent_calls.items():
    parent_body = masked_sources[view_structs[parent][0]]
    leaked = sorted(callee for callee in forbidden_callees if call_labels(parent_body, callee))
    if leaked:
        raise SystemExit(
            f"SpaceView decomposition guard: {parent} bypasses cohesive leaves {leaked}"
        )

banned_fanout_names = {
    "profileManager", "liveFolderManager", "splitLayout", "emptySplitCreation",
    "faviconImageReader", "showShortcutEditor", "showFolderEditor",
    "showFolderSearchPopover", "folderSearchAnchorHoverChanged",
    "presentSharingServicePicker", "splitCommands", "requestUserTabActivation",
    "openForegroundTab", "pinShortcutGlobally", "unloadShortcutPin",
    "unloadShortcutPins", "browserWindowRegistry", "onUngroup", "onDelete",
}
banned_fanout_types = {
    "BrowserManager", "TabManager", "ProfileManager", "SumiLiveFolderManager",
    "SplitLayoutService", "EmptySplitCreationWorkflow", "SidebarSplitCommands",
}
precise_favicon_leaves = {"SpacePinnedShortcutEntryView", "TabFolderShortcutEntryView"}
guarded_filenames = set(roots)
fanout_guard_views = {
    name for name, (path, _) in view_structs.items() if path.name in guarded_filenames
}
for name, (_, body) in view_structs.items():
    if name not in fanout_guard_views:
        continue
    for _, property_name, property_type in root_properties(body):
        if property_name in banned_fanout_names:
            if property_name == "faviconImageReader" and name in precise_favicon_leaves:
                continue
            raise SystemExit(
                f"SpaceView decomposition guard: {name} stores rejected raw fan-out "
                f"input {property_name}"
            )
        leaked_types = sorted(
            type_name for type_name in banned_fanout_types
            if re.search(rf"\b{re.escape(type_name)}\b", property_type)
        )
        if leaked_types:
            raise SystemExit(
                f"SpaceView decomposition guard: {name} stores rejected manager types "
                f"{leaked_types}"
            )

fanout_guard_callees = {
    "SpaceSidebarListView", "SpaceSidebarListContentView",
    "SpaceFlatFolderHeaderView", "SpacePinnedShortcutEntryView",
    "SpacePinnedSplitGroupEntryView", "SpaceRegularTabEntryView",
    "SpaceRegularSplitGroupEntryView", "TabFolderShortcutEntryView",
    "TabFolderLiveItemEntryView", "TabFolderSplitGroupEntryView",
}
for path, source in masked_sources.items():
    for callee in fanout_guard_callees:
        for labels in call_labels(source, callee):
            allowed_labels = (
                {"faviconImageReader"}
                if callee in precise_favicon_leaves
                else set()
            )
            leaked = sorted((labels & banned_fanout_names) - allowed_labels)
            if leaked:
                raise SystemExit(
                    f"SpaceView decomposition guard: call to {callee} in {path.name} "
                    f"forwards rejected raw dependencies {leaked}"
                )

browser_context_views = {
    name for name, (_, body) in view_structs.items()
    if any(
        property_name == "browserContext" and property_type == "SidebarBrowserContext"
        for _, property_name, property_type in root_properties(body)
    )
}
allowed_browser_context_views = {
    "SpaceView",
    "SpaceSidebarListView", "SpaceSidebarListContentView",
    "SpaceFlatFolderHeaderView", "SpacePinnedSplitGroupEntryView",
    "SpaceNestedPinnedStickyEntryView",
    "SpaceRegularNewTabRow", "SpaceRegularSplitGroupEntryView",
    "TabFolderHeaderView",
    "TabFolderSplitGroupEntryView", "SpaceSidebarBoundaryView",
}
unexpected_browser_context_views = browser_context_views - allowed_browser_context_views
if unexpected_browser_context_views:
    raise SystemExit(
        "SpaceView decomposition guard: SidebarBrowserContext reached unexpected views "
        f"{sorted(unexpected_browser_context_views)}"
    )

PY

echo "SpaceView decomposition guard passed"
