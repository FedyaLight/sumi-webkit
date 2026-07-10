#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

composition='Sumi/Managers/BrowserManager/BrowserExtensionBridgeComposition.swift'
adapter_files=(
  Sumi/Managers/ExtensionManager/BrowserExtensionAuxiliaryWindowAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionTabMutationAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionTabQueryAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionWebViewAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionWindowActivationAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionWindowPresentationAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionWindowQueryAdapter.swift
  Sumi/Managers/ExtensionManager/BrowserRequestedTabTargetAdapter.swift
)
required_files=(
  "$composition"
  Sumi/Managers/ExtensionManager/ExtensionBridge.swift
  "${adapter_files[@]}"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: extension browser bridge boundary missing: %s\n' "$file" >&2
    status=1
  fi
done

removed_files=(
  Sumi/Managers/BrowserManager/BrowserExtensionBridgeBundle.swift
  Sumi/Managers/ExtensionManager/BrowserExtensionBridgeAdapter.swift
)

for file in "${removed_files[@]}"; do
  if [[ -e "$file" ]]; then
    printf 'error: retired extension bridge god surface returned: %s\n' \
      "$file" >&2
    status=1
  fi
done

legacy_hits="$(
  rg -n '\b(ExtensionBrowserBridgeContext|BrowserExtensionBridgeAdapter|BrowserExtensionBridgeBundle|browserBridgeContext|extensionBridgeBundle)\b' \
    App Sumi SumiTests -g '*.swift' || true
)"
fail_matches "retired aggregate extension bridge returned" "$legacy_hits"

unused_mutation_hits="$(
  rg -n '\b(assignExtensionWebView|replaceUntrackedExtensionWebView)\b' \
    App Sumi SumiTests -g '*.swift' || true
)"
fail_matches "unused broad WebView mutation escaped the bridge split" "$unused_mutation_hits"

if (( ${#adapter_files[@]} > 0 )); then
  manager_hits="$(
    rg -n '\bBrowserManager\b|\bbrowserManager\b' \
      "${adapter_files[@]}" || true
  )"
  fail_matches "concrete extension adapter reaches back into BrowserManager" "$manager_hits"

  owner_declarations="$(
    rg -n '^(private )?(final )?(class|struct|enum|protocol) [A-Za-z0-9_]*Owner\b' \
      "${adapter_files[@]}" || true
  )"
  fail_matches "extension bridge responsibility hidden behind an Owner type" "$owner_declarations"

  for file in "${adapter_files[@]}"; do
    [[ -f "$file" ]] || continue
    lines="$(wc -l < "$file" | tr -d ' ')"
    if (( lines > 160 )); then
      printf 'error: extension capability adapter grew beyond one responsibility (%s: %s > 160 LOC)\n' \
        "$file" "$lines" >&2
      status=1
    fi
  done
fi

if [[ -f "$composition" ]]; then
  stored_manager_hits="$(
    rg -n '^[[:space:]]+(private[[:space:]]+)?(weak[[:space:]]+)?(let|var)[[:space:]]+browserManager\b' \
      "$composition" || true
  )"
  fail_matches "extension bridge composition stores BrowserManager" "$stored_manager_hits"

  composition_forwarders="$(
    awk '
      /final class BrowserExtensionBridgeComposition/ { in_composition = 1 }
      in_composition && /^[[:space:]]+func[[:space:]]/ { print NR ":" $0 }
    ' "$composition"
  )"
  fail_matches "extension bridge composition grew forwarding methods" "$composition_forwarders"

  composition_lines="$(wc -l < "$composition" | tr -d ' ')"
  if (( composition_lines > 320 )); then
    printf 'error: extension bridge composition grew beyond assembly duties (%s > 320 LOC)\n' \
      "$composition_lines" >&2
    status=1
  fi
fi

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo "extension browser bridge architecture boundary passed"
