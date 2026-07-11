#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

compositor="Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
display_state="Sumi/Components/WebsiteView/WebsiteDisplayState.swift"
browser_context="Sumi/Components/WebsiteView/WindowWebContentBrowserContext.swift"
presentation="Sumi/Models/Window/WindowSplitPresentation.swift"
projection="Sumi/Managers/SplitRuntime/WindowSplitProjection.swift"
obsolete_split_repair="Sumi/Components/WebsiteView/WindowWebContentSplitRepairScheduler.swift"
status=0

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
