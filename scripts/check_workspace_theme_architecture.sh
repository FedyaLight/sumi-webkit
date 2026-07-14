#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

schema_file="Packages/SumiDomain/Sources/SumiDomain/WorkspaceTheme/WorkspaceTheme.swift"
rendering_file="Sumi/Theme/WorkspaceThemeRendering.swift"
coding_file="Sumi/Theme/WorkspaceThemeCoding.swift"
production_roots=(App FloatingBar Settings Sumi SidebarChrome UI Packages/SumiDomain/Sources)
app_roots=(App FloatingBar Settings Sumi SidebarChrome UI)
failures=0

strip_swift_comments() {
  perl -0777 -pe 's{/\*.*?\*/}{}gs; s{//[^\n]*}{}g' "$1"
}

record_error() {
  printf 'error: %s\n' "$1" >&2
  failures=$((failures + 1))
}

count_declarations() {
  local pattern="$1"
  local hits
  hits="$(swift_declaration_hits "$pattern" "${production_roots[@]}")"
  if [[ -z "$hits" ]]; then
    printf '0\n'
  else
    printf '%s\n' "$hits" | wc -l | tr -d ' '
  fi
}

swift_declaration_hits() {
  local pattern="$1"
  shift
  local file
  local hits

  while IFS= read -r file; do
    hits="$(strip_swift_comments "$file" | rg -n "$pattern" || true)"
    if [[ -n "$hits" ]]; then
      printf '%s\n' "$hits" | sed "s#^#$file:#"
    fi
  done < <(rg -l 'WorkspaceTheme' -g '*.swift' "$@" || true)
}

printf '%s\n' 'Workspace theme architecture guardrail'
printf '%s\n' '--------------------------------------'

for file in "$schema_file" "$rendering_file" "$coding_file"; do
  if [[ ! -f "$file" ]]; then
    record_error "required workspace-theme authority is missing: $file"
  fi
done

if [[ -f "$schema_file" ]]; then
  unexpected_imports="$(rg -n '^import ' "$schema_file" | rg -v '^1:import Foundation$' || true)"
  if [[ -n "$unexpected_imports" ]]; then
    printf '%s\n' "$unexpected_imports" >&2
    record_error "canonical workspace-theme schema must import only Foundation"
  fi

  schema_forbidden_pattern='\b(SwiftUI|AppKit|Combine|Observation|OSLog|Dispatch|Color|NSColor|CGColor|NSGradient|WorkspaceResolvedGradient|WorkspaceGradientStop|Angle|Observable|Published|MainActor|Task|Timer|Logger|RuntimeDiagnostics|DispatchQueue|os_log)\b|\b(renderGradient|interpolated|visuallyEquals|accentHex|themePerceivedLightness|customChromeTheme[A-Za-z0-9_]*|customChromeTexture[A-Za-z0-9_]*)\b'
  schema_forbidden_hits="$(strip_swift_comments "$schema_file" | rg -n "$schema_forbidden_pattern" || true)"
  if [[ -n "$schema_forbidden_hits" ]]; then
    printf '%s\n' "$schema_forbidden_hits" >&2
    record_error "canonical workspace-theme schema contains app rendering/runtime authority"
  fi
fi

canonical_names=(
  WorkspaceTheme
  WorkspaceGradientTheme
  WorkspaceThemeColor
  WorkspaceThemePosition
  WorkspaceThemeColorAlgorithm
  WorkspaceThemeColorType
)
swift_declaration_prefix='^[[:space:]]*((@[A-Za-z_][A-Za-z0-9_.]*(\([^)]*\))?|private|fileprivate|package|internal|public|open|final|indirect|distributed|nonisolated(\(unsafe\))?)[[:space:]]+)*'
canonical_patterns=(
  "${swift_declaration_prefix}struct[[:space:]]+WorkspaceTheme[[:space:]]*:"
  "${swift_declaration_prefix}struct[[:space:]]+WorkspaceGradientTheme[[:space:]]*:"
  "${swift_declaration_prefix}struct[[:space:]]+WorkspaceThemeColor[[:space:]]*:"
  "${swift_declaration_prefix}struct[[:space:]]+WorkspaceThemePosition[[:space:]]*:"
  "${swift_declaration_prefix}enum[[:space:]]+WorkspaceThemeColorAlgorithm[[:space:]]*:"
  "${swift_declaration_prefix}enum[[:space:]]+WorkspaceThemeColorType[[:space:]]*:"
)

app_duplicate_pattern="${swift_declaration_prefix}((struct|enum|class|actor)[[:space:]]+[A-Za-z0-9_]*WorkspaceTheme[A-Za-z0-9_]*[[:space:]]*:[^{]*(Codable|Encodable|Decodable)\\b|extension[[:space:]]+(WorkspaceTheme|WorkspaceGradientTheme|WorkspaceThemeColor|WorkspaceThemePosition|WorkspaceThemeColorAlgorithm|WorkspaceThemeColorType)[[:space:]]*:[^{]*(Codable|Encodable|Decodable)\\b|typealias[[:space:]]+(WorkspaceTheme|WorkspaceGradientTheme|WorkspaceThemeColor|WorkspaceThemePosition|WorkspaceThemeColorAlgorithm|WorkspaceThemeColorType)\\b)"

for index in "${!canonical_names[@]}"; do
  type_name="${canonical_names[$index]}"
  count="$(count_declarations "${canonical_patterns[$index]}")"
  if [[ "$count" != 1 ]]; then
    record_error "$type_name must have exactly one production declaration (found $count)"
  fi
done

app_duplicate_hits="$(swift_declaration_hits "$app_duplicate_pattern" "${app_roots[@]}")"
if [[ -n "$app_duplicate_hits" ]]; then
  printf '%s\n' "$app_duplicate_hits" >&2
  record_error "app target contains a duplicate Codable workspace-theme schema or compatibility typealias"
fi

authority_names=(
  resolved-gradient
  gradient-stop
  gradient-construction
  gradient-interpolation
  chrome-handoff
  color-lightness
)
authority_patterns=(
  '^[[:space:]]*struct[[:space:]]+WorkspaceResolvedGradient[[:space:]]*:'
  '^[[:space:]]*struct[[:space:]]+WorkspaceGradientStop[[:space:]]*:'
  '^[[:space:]]*var[[:space:]]+renderGradient[[:space:]]*:[[:space:]]*WorkspaceResolvedGradient'
  '^[[:space:]]*func[[:space:]]+interpolated\(to other:[[:space:]]*WorkspaceResolvedGradient'
  '^[[:space:]]*var[[:space:]]+customChromeThemeMaterialHandoffProgress[[:space:]]*:[[:space:]]*Double'
  '^[[:space:]]*static[[:space:]]+func[[:space:]]+defaultLightness\(for hex:'
)

for index in "${!authority_names[@]}"; do
  authority="${authority_names[$index]}"
  hits="$(rg -n "${authority_patterns[$index]}" -g '*.swift' "${app_roots[@]}" || true)"
  count="$(printf '%s\n' "$hits" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" != 1 ]] || [[ "$hits" != "$rendering_file:"* ]]; then
    [[ -n "$hits" ]] && printf '%s\n' "$hits" >&2
    record_error "$authority must have one authority in $rendering_file (found $count)"
  fi
done

coding_names=(encode decode)
coding_patterns=(
  '^[[:space:]]*var[[:space:]]+encoded[[:space:]]*:[[:space:]]*Data\?'
  '^[[:space:]]*static[[:space:]]+func[[:space:]]+decode\(_ data:[[:space:]]*Data\)[[:space:]]*->[[:space:]]*WorkspaceTheme\?'
)

for index in "${!coding_names[@]}"; do
  authority="${coding_names[$index]}"
  hits="$(rg -n "${coding_patterns[$index]}" -g '*.swift' "${app_roots[@]}" || true)"
  count="$(printf '%s\n' "$hits" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" != 1 ]] || [[ "$hits" != "$coding_file:"* ]]; then
    [[ -n "$hits" ]] && printf '%s\n' "$hits" >&2
    record_error "workspace-theme $authority adapter must have one authority in $coding_file (found $count)"
  fi
done

if (( failures > 0 )); then
  exit 1
fi

printf 'workspace theme architecture guardrail passed (%d canonical schema types, 8 app authorities)\n' "${#canonical_names[@]}"
