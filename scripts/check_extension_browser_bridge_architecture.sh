#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

extension_root='Sumi/Managers/ExtensionManager'
browser_root='Sumi/Managers/BrowserManager'
bridge="$browser_root/BrowserExtensionBridgeComposition.swift"
attachment="$extension_root/ExtensionBrowserAttachmentAuthority.swift"
attached_runtime="$extension_root/ExtensionAttachedBrowserRuntime.swift"
assembler="$extension_root/ExtensionAttachedBrowserRuntimeAssembler.swift"
attacher="$extension_root/ExtensionBrowserRuntimeAttacher.swift"
roles="$extension_root/ExtensionBrowserRuntimeRoles.swift"

for file in "$bridge" "$attachment" "$attached_runtime" "$assembler" \
  "$attacher" "$roles"; do
  guard_require_file "$file"
done

guard_expect_no_matches \
  'broad extension runtime transport returned' \
  '\bExtensionManagerRuntime\b|\bExtensionBrowserContentInventory\b' \
  Sumi -g '*.swift'
guard_expect_no_matches \
  'browser bridge retained ExtensionManager or a generic dependency bag' \
  '\bExtensionManager\b|struct (Dependencies|Actions|Environment)\b' \
  "$bridge"
guard_expect_no_matches \
  'browser attachment exposes mutable service storage' \
  '^[[:space:]]*(internal |public )?(let|var)[[:space:]]+(attached|runtime|bridge|tabs|windows|webViews|adapters|publications)[[:space:]]*:' \
  "$attachment"
guard_expect_no_matches \
  'attached graph escaped through a public result' \
  '->[[:space:]]*ExtensionAttachedBrowserRuntime\b' \
  "$extension_root" -g '*.swift'

for state in detached attached retired; do
  state_count="$(guard_count_matches "case $state" "$attachment")"
  guard_exact "browser attachment state: $state" "$state_count" 1
done
for admission in install alreadyAttached rejectDifferentBrowser rejectRetired; do
  count="$(guard_count_matches "case .$admission" "$attacher")"
  guard_exact "browser attachment admission: $admission" "$count" 1
done

route_line="$(guard_capture_matches 'routeInstaller\.install\(' "$attacher" -m 1 | cut -d: -f1)"
publish_line="$(guard_capture_matches 'attachment\.install\(' "$attacher" -m 1 | cut -d: -f1)"
settle_line="$(guard_capture_matches 'profiles\.settleInstalledAttachment\(' "$attacher" -m 1 | cut -d: -f1)"
if [[ -z "$route_line" || -z "$publish_line" || -z "$settle_line" ]] \
  || (( route_line >= publish_line || publish_line >= settle_line )); then
  guard_record_failure \
    'browser attachment must install routes, publish the complete runtime, then settle profiles'
fi

attached_users="$(guard_capture_files '\bExtensionAttachedBrowserRuntime\b' \
  "$extension_root" -g '*.swift')"
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  case "$file" in
    "$attached_runtime"|"$assembler"|"$attachment"|*TestInspection.swift)
      ;;
    *)
      guard_record_failure \
        "attached runtime aggregate escaped composition/retention boundaries: $file"
      ;;
  esac
done <<< "$attached_users"

python3 - "$bridge" "$attached_runtime" "$assembler" <<'PY'
import re
import sys
from pathlib import Path

bridge_path, runtime_path, assembler_path = map(Path, sys.argv[1:])


def declaration_body(source: str, kind: str, name: str) -> str:
    match = re.search(rf"\b{kind}\s+{re.escape(name)}\s*\{{", source)
    if match is None:
        raise SystemExit(f"error: required {kind} is missing: {name}")
    opening = source.find("{", match.start())
    depth = 1
    index = opening + 1
    while index < len(source) and depth:
        depth += source[index] == "{"
        depth -= source[index] == "}"
        index += 1
    if depth:
        raise SystemExit(f"error: unterminated {kind}: {name}")
    return source[opening + 1 : index - 1]


bridge = declaration_body(
    bridge_path.read_text(), "final class", "BrowserExtensionBridgeComposition"
)
bridge_fields = re.findall(r"(?m)^[ \t]{4}let\s+(\w+)\s*:", bridge)
if not 8 <= len(bridge_fields) <= 14:
    raise SystemExit(
        f"error: browser bridge is not a bounded exact-capability composition ({len(bridge_fields)} fields)"
    )
if re.search(r"(?m)^[ \t]{4}(?:func|subscript)\b", bridge):
    raise SystemExit("error: browser bridge gained forwarding behavior")

runtime = declaration_body(
    runtime_path.read_text(), "struct", "ExtensionAttachedBrowserRuntime"
)
runtime_fields = re.findall(r"(?m)^[ \t]{4}let\s+(\w+)\s*:", runtime)
if not 6 <= len(runtime_fields) <= 12:
    raise SystemExit(
        f"error: attached runtime is not bounded lifetime storage ({len(runtime_fields)} fields)"
    )
if re.search(r"(?m)^[ \t]{4}(?:var|func|subscript|init)\b", runtime):
    raise SystemExit("error: attached runtime aggregate gained behavior or mutable state")

assembler = declaration_body(
    assembler_path.read_text(), "final class", "ExtensionAttachedBrowserRuntimeAssembler"
)
factory_fields = re.findall(
    r"(?m)^[ \t]{4}private let\s+(\w+)\s*:", assembler
)
if len(factory_fields) != 6:
    raise SystemExit(
        f"error: attachment assembler must coordinate six bounded factories, found {len(factory_fields)}"
    )
if len(re.findall(r"\bfunc assemble\s*\(", assembler)) != 1:
    raise SystemExit("error: attachment assembler must expose one complete assembly operation")
PY

guard_finish 'extension browser bridge architecture'
