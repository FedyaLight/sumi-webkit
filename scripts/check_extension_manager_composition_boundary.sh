#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

extension_root='Sumi/Managers/ExtensionManager'
manager="$extension_root/ExtensionManager.swift"
graphs="$extension_root/ExtensionManagerGraphs.swift"
publication_graph="$extension_root/ExtensionRuntimePublicationGraph.swift"
factories="$extension_root/ExtensionManagerSubsystemAssemblyFactories.swift"
root_assembler="$extension_root/ExtensionManagerRootAssembler.swift"
graph_finalizer="$extension_root/ExtensionManagerGraphFinalizer.swift"
attachment="$extension_root/ExtensionBrowserAttachmentAuthority.swift"
attached_runtime="$extension_root/ExtensionAttachedBrowserRuntime.swift"
attached_runtime_assembler="$extension_root/ExtensionAttachedBrowserRuntimeAssembler.swift"
runtime_assembler="$extension_root/ExtensionManagerAssemblerRuntime.swift"

for file in "$manager" "$graphs" "$publication_graph" \
  "$factories" "$root_assembler" "$graph_finalizer" "$attachment" \
  "$attached_runtime" "$attached_runtime_assembler"; do
  guard_require_file "$file"
done

guard_max \
  'ExtensionManager production runtime assembly LOC' \
  "$(guard_count_lines "$runtime_assembler")" \
  180
guard_max \
  'ExtensionManager graph finalizer LOC' \
  "$(guard_count_lines "$graph_finalizer")" \
  350
guard_expect_no_matches \
  'runtime phase regained the complete assembly foundation' \
  '\bExtensionManagerAssemblyFoundation\b' \
  "$extension_root" -g 'ExtensionManagerRuntime*Phase*.swift'

for retired in \
  "$extension_root/ExtensionManagerRuntime.swift" \
  "$extension_root/ExtensionManagerRuntimeDebugAssembler.swift" \
  "$extension_root/ExtensionBrowserContentInventory.swift" \
  'Sumi/Managers/BrowserManager/BrowserExtensionManagerRuntimeFactory.swift'; do
  guard_expect_absent_path 'retired broad extension runtime surface' "$retired"
done

runtime_assembly_entry_count="$(
  guard_count_matches '\bstatic[[:space:]]+func[[:space:]]+assembleRuntime[[:space:]]*\(' \
    "$runtime_assembler"
)"
guard_exact 'single runtime assembly orchestration' "$runtime_assembly_entry_count" 1
core_assembly_entry_count="$(
  guard_count_matches '\bprivate[[:space:]]+static[[:space:]]+func[[:space:]]+assembleCore[[:space:]]*\(' \
    "$extension_root/ExtensionManagerAssemblerCore.swift"
)"
guard_exact 'single core assembly orchestration' "$core_assembly_entry_count" 1

manager_lines="$(guard_count_lines "$manager")"
guard_max 'ExtensionManager composition-root LOC' "$manager_lines" 350

guard_expect_no_matches \
  'extension graph regained lazy or manager-root construction' \
  '\blazy[[:space:]]+var\b|manager:[[:space:]]*self\b' \
  "$extension_root" -g '*.swift'
guard_expect_no_matches \
  'extension leaf retained a manager backreference' \
  'private[[:space:]]+(weak[[:space:]]+)?(let|var)[[:space:]]+(manager|extensionManager)\b|init\([^)]*manager:[[:space:]]*ExtensionManager' \
  "$extension_root" -g '*.swift'
guard_expect_no_matches \
  'ExtensionManager exposes mutable browser/runtime mirrors' \
  '(browserRuntimeState|extension(Window|Tab|WebView|Auxiliary|RequestedWindow)[A-Za-z]*[[:space:]]*:|@[A-Za-z]+[[:space:]]+var|private\(set\)[[:space:]]+var)' \
  "$manager"
guard_expect_no_matches \
  'a consumer can recover a retained lifetime node' \
  '\.lifetime\.' Sumi -g '*.swift'
guard_expect_no_matches \
  'generic attached-runtime accessor regrew' \
  '\bwithAttached\b' "$extension_root" -g '*.swift'
guard_expect_no_matches \
  'attached-runtime test inspection escaped into product code' \
  '\bExtensionAttachedBrowserRuntimeInspection\b' \
  "$extension_root" -g '*.swift' \
  -g '!ExtensionAttachedBrowserRuntime.swift' \
  -g '!ExtensionBrowserAttachmentAuthority.swift'

aggregate_use_files="$(guard_capture_files \
  '\bExtensionAttachedBrowserRuntime\b' \
  "$extension_root" -g '*.swift')"
while IFS= read -r aggregate_use_file; do
  [[ -n "$aggregate_use_file" ]] || continue
  case "$aggregate_use_file" in
    "$attachment"|"$attached_runtime"|"$attached_runtime_assembler")
      ;;
    *)
      guard_record_failure \
        "attached runtime aggregate escaped lifetime construction: $aggregate_use_file"
      ;;
  esac
done <<< "$aggregate_use_files"

graph_count="$({
  guard_count_matches '^struct Extension[A-Za-z0-9]+Graph[[:space:]]*\{' \
    "$graphs" "$publication_graph"
})"
guard_exact 'sealed extension graph count' "$graph_count" 6

manager_graph_count="$({
  guard_count_matches 'private let[[:space:]]+[A-Za-z0-9]+:[[:space:]]*Extension[A-Za-z0-9]+Graph\b' \
    "$manager" -U
})"
guard_exact 'manager-owned sealed graph count' "$manager_graph_count" 6

python3 - "$manager" "$graphs" "$publication_graph" "$extension_root" "$factories" \
  "$graph_finalizer" <<'PY'
import re
import sys
from pathlib import Path

manager_path, graphs_path, publication_path, owners_root_path, factories_path, root_path = map(
    Path, sys.argv[1:]
)


def declarations(source: str, kind: str, suffix: str):
    pattern = re.compile(rf"\b{kind}\s+(\w+{suffix})\s*\{{")
    for match in pattern.finditer(source):
        opening = source.find("{", match.start())
        depth = 1
        index = opening + 1
        while index < len(source) and depth:
            depth += source[index] == "{"
            depth -= source[index] == "}"
            index += 1
        if depth:
            raise SystemExit(f"error: unterminated {kind}: {match.group(1)}")
        yield match.group(1), source[opening + 1 : index - 1]


graph_sources = graphs_path.read_text() + "\n" + publication_path.read_text()
graphs = list(declarations(graph_sources, "struct", "Graph"))
if len(graphs) != 6:
    raise SystemExit(f"error: expected six sealed graphs, found {len(graphs)}")
for name, body in graphs:
    fields = re.findall(r"(?m)^\s*let\s+(\w+)\s*:\s*([\w.]+)", body)
    lifetime_fields = [
        (field, field_type)
        for field, field_type in fields
        if field_type.endswith(("Owner", "Lifetime"))
    ]
    if not lifetime_fields:
        raise SystemExit(f"error: {name} lacks its passive lifetime seal")
    if len(fields) > 10:
        raise SystemExit(f"error: {name} exposes too many terminal roles ({len(fields)} > 10)")
    if re.search(r"(?m)^\s*(?:var|func|subscript|init|typealias)\b", body):
        raise SystemExit(f"error: {name} gained behavior or mutable/forwarded state")

graph_owner_types = re.findall(
    r"let\s+\w*[Ll]ifetime\s*:\s*(Extension\w+(?:Owner|Lifetime))",
    graph_sources,
)
if len(graph_owner_types) != len(set(graph_owner_types)):
    raise SystemExit("error: a passive lifetime owner is shared by sealed graphs")
graph_owner_types = set(graph_owner_types)
declared_owner_bodies = {}
for owner_path in owners_root_path.glob("*.swift"):
    declared_owner_bodies.update(
        declarations(owner_path.read_text(), "final class", "")
    )
owners = [
    (name, declared_owner_bodies[name])
    for name in sorted(graph_owner_types)
    if name in declared_owner_bodies
]
if not 6 <= len(graph_owner_types) <= 18 or len(owners) != len(graph_owner_types):
    raise SystemExit("error: sealed graph lifetime topology is missing or unbounded")
owner_names = {name for name, _ in owners}
for name, body in owners:
    fields = re.findall(r"(?m)^\s*private let\s+(\w+)\s*:", body)
    if not fields or len(fields) > 8:
        raise SystemExit(f"error: {name} is empty or unbounded ({len(fields)} retained nodes)")
    if re.search(r"(?m)^\s*(?!private let\b)(?:\w+\s+)?(?:let|var)\s+\w+\s*:", body):
        raise SystemExit(f"error: {name} publishes or mutates a retained node")
    if re.search(r"(?m)^\s*(?:func|subscript)\b", body):
        raise SystemExit(f"error: {name} gained forwarding behavior")

if graph_owner_types != owner_names:
    raise SystemExit("error: sealed graphs and lifetime owners are not one-to-one")

factory_source = factories_path.read_text()
factory_names = re.findall(r"\benum\s+(Extension\w+Factory)\s*\{", factory_source)
if len(factory_names) != 6:
    raise SystemExit(f"error: expected six assembly factories, found {len(factory_names)}")
for name in factory_names:
    body = next(body for candidate, body in declarations(factory_source, "enum", "Factory") if candidate == name)
    if len(re.findall(r"\bstatic func make\s*\(", body)) != 1:
        raise SystemExit(f"error: {name} must expose exactly one ephemeral make operation")
    if re.search(r"(?m)^[ \t]{4}(?:let|var|subscript)\b", body):
        raise SystemExit(f"error: {name} retained partial assembly state")

manager = manager_path.read_text()
manager_graph_types = re.findall(
    r"(?m)^\s*private let \w+\s*:\s*(Extension\w+Graph)\b", manager
)
if len(manager_graph_types) != 6 or set(manager_graph_types) != {name for name, _ in graphs}:
    raise SystemExit("error: ExtensionManager does not retain exactly the six sealed graphs")
if re.search(r"\b(?:func|var)\s+\w+[^\n]*Extension\w+Graph", manager):
    raise SystemExit("error: ExtensionManager publishes a graph getter")

root = root_path.read_text()
if len(re.findall(r"\bExtensionManagerRootGraphs\s*\(", root)) != 1:
    raise SystemExit("error: root assembly must seal one complete graph set")
PY

python3 - "$extension_root" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])


def declarations(source: str, suffix: str):
    pattern = re.compile(rf"\bstruct\s+(\w+{suffix})\s*\{{")
    for match in pattern.finditer(source):
        opening = source.find("{", match.start())
        depth = 1
        index = opening + 1
        while index < len(source) and depth:
            depth += source[index] == "{"
            depth -= source[index] == "}"
            index += 1
        if depth:
            raise SystemExit(f"error: unterminated struct: {match.group(1)}")
        yield match.group(1), source[opening + 1:index - 1]


def matching_paren(source: str, opening: int) -> int:
    depth = 1
    index = opening + 1
    while index < len(source) and depth:
        depth += source[index] == "("
        depth -= source[index] == ")"
        index += 1
    if depth:
        raise SystemExit("error: unterminated phase assembler parameter list")
    return index - 1


def parameter_count(parameters: str) -> int:
    if not parameters.strip():
        return 0
    round_depth = square_depth = angle_depth = 0
    count = 1
    for character in parameters:
        if character == "(":
            round_depth += 1
        elif character == ")":
            round_depth -= 1
        elif character == "[":
            square_depth += 1
        elif character == "]":
            square_depth -= 1
        elif character == "<":
            angle_depth += 1
        elif character == ">":
            angle_depth = max(0, angle_depth - 1)
        elif character == "," and not (round_depth or square_depth or angle_depth):
            count += 1
    return count


phase_paths = sorted(root.glob("ExtensionManagerRuntime*Phase*.swift"))
if not phase_paths:
    raise SystemExit("error: runtime phase source inventory is empty")
for path in phase_paths:
    source = path.read_text()
    for name, body in declarations(source, "PhaseProduct"):
        fields = re.findall(r"(?m)^\s*let\s+\w+\s*:", body)
        if not fields or len(fields) > 8:
            raise SystemExit(
                f"error: {name} is empty or exceeds eight exact roles ({len(fields)})"
            )
    for match in re.finditer(r"\bstatic\s+func\s+(assemble\w*Phase)\s*\(", source):
        opening = source.find("(", match.start())
        closing = matching_paren(source, opening)
        count = parameter_count(source[opening + 1:closing])
        if count > 8:
            raise SystemExit(
                f"error: {match.group(1)} in {path.name} has {count} raw inputs (> 8)"
            )

core_source = (root / "ExtensionManagerAssemblerCore.swift").read_text()
core_products = list(declarations(core_source, "CoreAssembly"))
if len(core_products) != 1:
    raise SystemExit("error: expected one ExtensionManagerCoreAssembly")
core_fields = re.findall(r"(?m)^\s*let\s+\w+\s*:", core_products[0][1])
if not core_fields or len(core_fields) > 8:
    raise SystemExit(
        f"error: ExtensionManagerCoreAssembly exposes {len(core_fields)} phase products"
    )

assembly_paths = sorted(root.glob("*.swift"))
for path in assembly_paths:
    for name, body in declarations(path.read_text(), "AssemblyProduct"):
        fields = re.findall(r"(?m)^\s*let\s+\w+\s*:", body)
        if not fields or len(fields) > 8:
            raise SystemExit(
                f"error: {name} is empty or exceeds eight exact roles ({len(fields)})"
            )

factory_paths = [
    root / "ExtensionManagerSubsystemAssemblyFactories.swift",
    root / "ExtensionManagerToolbarRuntimeFactory.swift",
    root / "ExtensionManagerGraphFinalizer.swift",
    root / "ExtensionManagerRuntimeResultFactory.swift",
]
for path in factory_paths:
    source = path.read_text()
    for match in re.finditer(r"\b(?:private\s+)?static\s+func\s+(make\w*)\s*\(", source):
        opening = source.find("(", match.start())
        closing = matching_paren(source, opening)
        count = parameter_count(source[opening + 1:closing])
        if count > 8:
            raise SystemExit(
                f"error: {match.group(1)} in {path.name} has {count} raw inputs (> 8)"
            )
PY

python3 - "$extension_root" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
debug_only_files = [
    root / "ExtensionManagerDebugSignals.swift",
    root / "ExtensionManagerRuntimeTestInspector.swift",
    root / "ExtensionManagerTestAssemblyOverrides.swift",
    root / "ExtensionManagerTestInspection.swift",
]

for path in debug_only_files:
    source = path.read_text()
    significant = [
        line.strip()
        for line in source.splitlines()
        if line.strip() and not line.lstrip().startswith("//")
    ]
    if not significant or significant[0] != "#if DEBUG" or significant[-1] != "#endif":
        raise SystemExit(f"error: {path.name} must be a whole-file DEBUG seam")


def release_projection(source: str) -> str:
    output = []
    stack = []
    active = True

    def debug_value(condition: str):
        compact = re.sub(r"\s+", "", condition)
        if compact == "DEBUG":
            return False
        if compact in {"!DEBUG", "not(DEBUG)"}:
            return True
        return None

    for line in source.splitlines():
        directive = line.strip()
        if directive.startswith("#if "):
            condition = directive[4:].strip()
            value = debug_value(condition)
            stack.append({
                "parent": active,
                "controlled": value is not None,
                "taken": bool(value),
            })
            active = active and (value if value is not None else True)
            continue
        if directive.startswith("#elseif "):
            if not stack:
                raise SystemExit("error: unmatched #elseif")
            frame = stack[-1]
            condition = directive[8:].strip()
            value = debug_value(condition)
            if frame["controlled"] and value is not None:
                branch_active = not frame["taken"] and value
                frame["taken"] = frame["taken"] or bool(value)
            else:
                frame["controlled"] = False
                branch_active = True
            active = frame["parent"] and branch_active
            continue
        if directive == "#else":
            if not stack:
                raise SystemExit("error: unmatched #else")
            frame = stack[-1]
            branch_active = not frame["taken"] if frame["controlled"] else True
            frame["taken"] = True
            active = frame["parent"] and branch_active
            continue
        if directive == "#endif":
            if not stack:
                raise SystemExit("error: unmatched #endif")
            active = stack.pop()["parent"]
            continue
        if active:
            output.append(line)
    if stack:
        raise SystemExit("error: unterminated conditional compilation block")
    return "\n".join(output)


banned_release_seams = re.compile(
    r"\b(?:ExtensionManagerDebugSignals|ExtensionManagerRuntimeTestInspector|"
    r"ExtensionManagerTestAssemblyOverrides|ExtensionManagerTestInspection|"
    r"debugSignals|installDebug\w*|debugBefore\w*|debugDid\w*|debugEvent|"
    r"debugBackground\w*|debugReconcile\w*|debugUnload\w*|debugIsLoaded\w*)\b"
)
for path in root.glob("*.swift"):
    projected = release_projection(path.read_text())
    if banned_release_seams.search(projected):
        raise SystemExit(f"error: DEBUG/test seam survives Release projection: {path.name}")

retirement = release_projection((root / "ExtensionContextRetirement.swift").read_text())
if re.search(r"\b(?:unloadContext|isLoadedContext)\b", retirement):
    raise SystemExit("error: context retirement retained test-injectable Release operations")
PY

guard_expect_no_matches \
  'cosmetic nested lifetime bag returned' \
  'Extension(ContextRuntimeAuthority|RuntimeStateAuthority|RuntimeRevisionAuthority|ContextTransaction|ContextLoadResidency|ContextPublicationDiagnostics|ActionSurface|ActionPolicy|ActionPopupState|ActionPopupRuntime|ActionPopup|ActionToolbar|ActionCommand)Lifetime' \
  Sumi -g '*.swift'

guard_finish 'extension manager composition boundary'
