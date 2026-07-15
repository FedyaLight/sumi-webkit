#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

compositor="Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
composition_root="Sumi/Components/WebsiteView/TabCompositorWrapper.swift"
display_state="Sumi/Components/WebsiteView/WebsiteDisplayState.swift"
browser_context="Sumi/Components/WebsiteView/WindowWebContentBrowserContext.swift"
presentation="Sumi/Models/Window/WindowSplitPresentation.swift"
projection="Sumi/Managers/SplitRuntime/WindowSplitProjection.swift"
obsolete_split_repair="Sumi/Components/WebsiteView/WindowWebContentSplitRepairScheduler.swift"
for source in \
  "$compositor" \
  "$composition_root" \
  "$display_state" \
  "$browser_context" \
  "$presentation" \
  "$projection"; do
  guard_require_file "$source"
done

embedded_wrapper_count="$(
  guard_count_matches 'struct TabCompositorWrapper' "$compositor"
)"
if (( embedded_wrapper_count > 0 )); then
  guard_record_failure 'TabCompositorWrapper returned to WebsiteCompositorView'
fi

composition_root_count="$(
  guard_count_matches \
    'struct TabCompositorWrapper: NSViewControllerRepresentable' \
    "$composition_root"
)"
if (( composition_root_count == 0 )); then
  guard_record_failure 'TabCompositorWrapper composition root is missing'
fi

raw_split_dependencies="$(
  guard_capture_matches \
    '^[[:space:]]+(resolveDragTab|splitPreviews|splitLayout|splitDrops|splitDropTargets|sidebarDragState):' \
    "$compositor"
)"
if [[ -n "$raw_split_dependencies" ]]; then
  guard_record_failure "raw split-host construction dependencies returned: $raw_split_dependencies"
fi

split_host_count="$(
  guard_count_matches \
    'containerView: WindowWebContentSplitHostLayoutView' \
    "$compositor"
)"
if (( split_host_count == 0 )); then
  guard_record_failure 'WindowWebContentController lost its composed split-host view'
fi

dependency_bags="$(
  guard_capture_matches \
    '(WindowWebContentControllerDependencies|WindowWebContentControllerGraph)' \
    "$compositor" "$composition_root"
)"
if [[ -n "$dependency_bags" ]]; then
  guard_record_failure "broad compositor dependency bag/graph returned: $dependency_bags"
fi

role_declarations="$(
  guard_capture_matches \
    '^(struct WebsiteDisplayState|protocol WindowWebContentBrowserContext|final class BrowserManagerWindowWebContentContext|private func hostedWebViewCount|enum WindowWebContentPresentationDecision|final class WindowWebContentVisualHandoffFlowOwner)' \
    "$compositor"
)"
if [[ -n "$role_declarations" ]]; then
  guard_record_failure "separate compositor roles returned to WebsiteCompositorView: $role_declarations"
fi

legacy_split_contracts="$(
  guard_capture_matches \
    'splitGroup: SplitGroup|activeSplitGroup|func removeSplitGroup' \
    "$compositor" "$display_state" "$browser_context"
)"
if [[ -n "$legacy_split_contracts" ]]; then
  guard_record_failure "durable split repair contract returned to compositor: $legacy_split_contracts"
fi

guard_expect_absent_path 'obsolete compositor split-repair scheduler' "$obsolete_split_repair"

retained_runtime_objects="$(
  guard_capture_matches \
    '^[[:space:]]*(let|var)[[:space:]].*(:[[:space:]]*|\[[[:space:]]*)(Tab|WKWebView|TrackedWebViewOwner)([?[:space:]\]]|$)' \
    "$presentation"
)"
if [[ -n "$retained_runtime_objects" ]]; then
  guard_record_failure "WindowSplitPresentation retained runtime objects: $retained_runtime_objects"
fi

for bounded_file in "$presentation" "$projection"; do
  guard_max \
    "$bounded_file window-split projection LOC" \
    "$(guard_count_lines "$bounded_file")" \
    150
done

guard_finish 'website compositor boundary audit'
