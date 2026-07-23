#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

schema_file="Packages/SumiDomain/Sources/SumiDomain/WorkspaceTheme/WorkspaceTheme.swift"
rendering_file="Sumi/Theme/WorkspaceThemeRendering.swift"
coding_file="Sumi/Theme/WorkspaceThemeCoding.swift"
production_roots=(App CommandPalette Settings Sumi SidebarChrome UI Packages/SumiDomain/Sources)
app_roots=(App CommandPalette Settings Sumi SidebarChrome UI)

strip_swift_comments() {
  perl -0777 -pe 's{/\*.*?\*/}{}gs; s{//[^\n]*}{}g' "$1"
}

record_error() {
  guard_record_failure "$1"
}

count_declarations() {
  local pattern="$1"
  local hits
  hits="$(swift_declaration_hits "$pattern" "${production_roots[@]}")" || return
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
  local candidate_hits

  candidate_hits="$(
    guard_capture_matches 'WorkspaceTheme' -g '*.swift' "$@"
  )" || return
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    hits="$(
      strip_swift_comments "$file" \
        | guard_capture_matches "$pattern" -
    )" || return
    if [[ -n "$hits" ]]; then
      printf '%s\n' "$hits" | sed "s#^#$file:#"
    fi
  done < <(
    printf '%s\n' "$candidate_hits" \
      | sed '/^$/d' \
      | cut -d: -f1 \
      | sort -u
  )
}

printf '%s\n' 'Workspace theme architecture guardrail'
printf '%s\n' '--------------------------------------'

for file in "$schema_file" "$rendering_file" "$coding_file"; do
  guard_require_file "$file"
done

schema_imports="$(guard_capture_matches '^import ' "$schema_file")"
unexpected_imports=''
while IFS= read -r import_line; do
  [[ -n "$import_line" ]] || continue
  [[ "$import_line" == '1:import Foundation' ]] && continue
  unexpected_imports+="$import_line"$'\n'
done <<< "$schema_imports"
if [[ -n "$unexpected_imports" ]]; then
  record_error \
    "canonical workspace-theme schema must import only Foundation: $unexpected_imports"
fi

schema_forbidden_pattern='\b(SwiftUI|AppKit|Combine|Observation|OSLog|Dispatch|Color|NSColor|CGColor|NSGradient|WorkspaceResolvedGradient|WorkspaceGradientStop|Angle|Observable|Published|MainActor|Task|Timer|Logger|RuntimeDiagnostics|DispatchQueue|os_log)\b|\b(renderGradient|interpolated|visuallyEquals|accentHex|themePerceivedLightness|customChromeTheme[A-Za-z0-9_]*|customChromeTexture[A-Za-z0-9_]*)\b'
schema_forbidden_hits="$(
  strip_swift_comments "$schema_file" \
    | guard_capture_matches "$schema_forbidden_pattern" -
)"
if [[ -n "$schema_forbidden_hits" ]]; then
  record_error \
    "canonical workspace-theme schema contains app rendering/runtime authority: $schema_forbidden_hits"
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
  hits="$(
    guard_capture_matches \
      "${authority_patterns[$index]}" \
      -g '*.swift' "${app_roots[@]}"
  )"
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
  hits="$(
    guard_capture_matches \
      "${coding_patterns[$index]}" \
      -g '*.swift' "${app_roots[@]}"
  )"
  count="$(printf '%s\n' "$hits" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" != 1 ]] || [[ "$hits" != "$coding_file:"* ]]; then
    [[ -n "$hits" ]] && printf '%s\n' "$hits" >&2
    record_error "workspace-theme $authority adapter must have one authority in $coding_file (found $count)"
  fi
done

guard_finish \
  "workspace theme architecture guardrail (${#canonical_names[@]} canonical schema types, 8 app authorities)"
