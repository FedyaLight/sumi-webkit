#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

compositor="Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
composition_root="Sumi/Components/WebsiteView/TabCompositorWrapper.swift"
display_state="Sumi/Components/WebsiteView/WebsiteDisplayState.swift"
browser_context="Sumi/Components/WebsiteView/WindowWebContentBrowserContext.swift"
presentation="Sumi/Models/Window/WindowSplitPresentation.swift"
projection="Sumi/Managers/SplitRuntime/WindowSplitProjection.swift"
obsolete_split_repair="Sumi/Components/WebsiteView/WindowWebContentSplitRepairScheduler.swift"
status=0

if grep -q 'struct TabCompositorWrapper' "$compositor"; then
  echo "TabCompositorWrapper must remain a separate SwiftUI composition root." >&2
  status=1
fi

if ! grep -q 'struct TabCompositorWrapper: NSViewControllerRepresentable' "$composition_root"; then
  echo "TabCompositorWrapper composition root is missing." >&2
  status=1
fi

raw_split_dependencies="$(grep -nE '^[[:space:]]+(resolveDragTab|splitPreviews|splitLayout|splitDrops|splitDropTargets|sidebarDragState):' "$compositor" || [[ $? -eq 1 ]])"
if [[ -n "$raw_split_dependencies" ]]; then
  printf 'WindowWebContentController must receive a composed split-host view, not its raw construction dependencies:\n%s\n' "$raw_split_dependencies" >&2
  status=1
fi

if ! grep -q 'containerView: WindowWebContentSplitHostLayoutView' "$compositor"; then
  echo "WindowWebContentController must own an explicitly composed split-host view." >&2
  status=1
fi

dependency_bags="$(grep -nE '(WindowWebContentControllerDependencies|WindowWebContentControllerGraph)' "$compositor" "$composition_root" || [[ $? -eq 1 ]])"
if [[ -n "$dependency_bags" ]]; then
  printf 'Do not hide compositor dependencies in a broad bag or graph:\n%s\n' "$dependency_bags" >&2
  status=1
fi

role_declarations="$(grep -nE '^(struct WebsiteDisplayState|protocol WindowWebContentBrowserContext|final class BrowserManagerWindowWebContentContext|private func hostedWebViewCount|enum WindowWebContentPresentationDecision|final class WindowWebContentVisualHandoffFlowOwner)' "$compositor" || [[ $? -eq 1 ]])"
if [[ -n "$role_declarations" ]]; then
  printf 'Display state, browser context, and visual handoff flow roles must stay out of WebsiteCompositorView:\n%s\n' "$role_declarations" >&2
  status=1
fi

legacy_split_contracts="$(grep -nE 'splitGroup: SplitGroup|activeSplitGroup|func removeSplitGroup' "$compositor" "$display_state" "$browser_context" || [[ $? -eq 1 ]])"
if [[ -n "$legacy_split_contracts" ]]; then
  printf 'Website compositor must consume window-local split presentations and cannot repair durable groups:\n%s\n' "$legacy_split_contracts" >&2
  status=1
fi

if [[ -e "$obsolete_split_repair" ]]; then
  echo "WindowWebContentSplitRepairScheduler must stay deleted; compositor rendering cannot mutate durable split structure." >&2
  status=1
fi

retained_runtime_objects="$(grep -nE '^[[:space:]]*(let|var)[[:space:]].*(:[[:space:]]*|\[[[:space:]]*)(Tab|WKWebView|TrackedWebViewOwner)([?[:space:]\]]|$)' "$presentation" || [[ $? -eq 1 ]])"
if [[ -n "$retained_runtime_objects" ]]; then
  printf 'WindowSplitPresentation must contain identities only, not runtime objects:\n%s\n' "$retained_runtime_objects" >&2
  status=1
fi

for bounded_file in "$presentation" "$projection"; do
  line_count="$(wc -l < "$bounded_file" | tr -d ' ')"
  if (( line_count > 150 )); then
    echo "$bounded_file exceeds the 150-line window-split projection boundary ($line_count)." >&2
    status=1
  fi
done

if [[ "$status" -ne 0 ]]; then
  echo "website compositor boundary audit failed" >&2
  exit "$status"
fi

echo "website compositor boundary audit passed"
