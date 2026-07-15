#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

root='Sumi/Managers/ExtensionManager'
assembler="$root/ExtensionNormalTabRuntimeAssembler.swift"
factory="$root/ExtensionAttachedNormalTabRuntimeFactory.swift"
query="$root/ExtensionAttachedNormalTabQuery.swift"
lifecycle="$root/ExtensionAttachedNormalTabLifecycle.swift"
requested="$root/ExtensionAttachedRequestedTabs.swift"
open_transaction="$root/ExtensionNormalTabOpenTransaction.swift"
registration="$root/ExtensionNormalTabRegistration.swift"
rebind="$root/ExtensionTabLifecycleRebindTransaction.swift"

for file in "$assembler" "$factory" "$query" "$lifecycle" "$requested" \
  "$open_transaction" "$registration" "$rebind"; do
  guard_require_file "$file"
done

guard_expect_no_matches \
  'normal-tab runtime regained manager/root reach-through' \
  '\bExtensionManager\b|\bBrowserManager\b|struct (Dependencies|Actions)\b|\bExtensionManagerRuntime\b' \
  "$assembler" "$factory" "$query" "$lifecycle" "$requested" \
  "$open_transaction" "$registration" "$rebind"
guard_expect_no_matches \
  'normal-tab runtime uses fabricated profile authority' \
  '\?\? UUID\(\)' "$assembler" "$factory" "$query" "$lifecycle" \
  "$requested" "$open_transaction" "$registration" "$rebind"
python3 - "$assembler" "$factory" <<'PY'
import re
import sys
from pathlib import Path

assembler_path, factory_path = map(Path, sys.argv[1:])


def body(source: str, kind: str, name: str) -> str:
    match = re.search(rf"\b{kind}\s+{re.escape(name)}\s*\{{", source)
    if match is None:
        raise SystemExit(f"error: missing {kind}: {name}")
    opening = source.find("{", match.start())
    depth = 1
    index = opening + 1
    while index < len(source) and depth:
        depth += source[index] == "{"
        depth -= source[index] == "}"
        index += 1
    return source[opening + 1 : index - 1]


source = assembler_path.read_text()
runtime = body(source, "struct", "ExtensionAttachedNormalTabRuntime")
fields = re.findall(r"(?m)^\s*let\s+(\w+)\s*:", runtime)
if not 7 <= len(fields) <= 11:
    raise SystemExit(
        f"error: normal-tab lifetime storage is not bounded ({len(fields)} roles)"
    )
if re.search(r"(?m)^\s*(?:var|func|subscript|init)\b", runtime):
    raise SystemExit("error: normal-tab lifetime storage gained behavior or mutable state")
assembly = body(source, "enum", "ExtensionNormalTabRuntimeAssembler")
if len(re.findall(r"\bstatic func assemble\s*\(", assembly)) != 1:
    raise SystemExit("error: normal-tab runtime must be assembled atomically once")

factory = body(
    factory_path.read_text(), "final class", "ExtensionAttachedNormalTabRuntimeFactory"
)
factory_fields = re.findall(r"(?m)^\s*private let\s+(\w+)\s*:", factory)
if len(factory_fields) > 10:
    raise SystemExit(
        f"error: normal-tab attachment factory is unbounded ({len(factory_fields)} collaborators)"
    )
if len(re.findall(r"\bfunc assemble\s*\(", factory)) != 1:
    raise SystemExit("error: normal-tab attachment factory must expose one assembly operation")
PY

for projection in NormalTabQuery NormalTabLifecycle RequestedTabs; do
  count="$(guard_count_matches "final class $projection" \
    "$query" "$lifecycle" "$requested")"
  guard_exact "attached projection: $projection" "$count" 1
done

detached_guards="$(guard_count_matches 'attachedEnvironment\(\)' \
  "$query" "$lifecycle" "$requested")"
if (( detached_guards < 12 )); then
  guard_record_failure 'attached normal-tab projections lost fail-closed runtime checks'
fi

for proof in \
  'ExtensionRuntimePublicationEvidence' \
  'ExtensionTabPublicationAdmission' \
  'controllerRuntime.admission' \
  'ExtensionLoadRevision'; do
  count="$(guard_count_matches "$proof" "$assembler" "$open_transaction" \
    "$registration" "$rebind")"
  if (( count == 0 )); then
    guard_record_failure "normal-tab transaction lost exact authority: $proof"
  fi
done

guard_finish 'extension normal-tab runtime boundary'
