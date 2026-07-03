#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

compositor="Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
status=0

role_declarations="$(grep -nE '^(struct WebsiteDisplayState|protocol WindowWebContentBrowserContext|final class BrowserManagerWindowWebContentContext|private func hostedWebViewCount|enum WindowWebContentPresentationDecision|final class WindowWebContentVisualHandoffFlowOwner)' "$compositor" || [[ $? -eq 1 ]])"
if [[ -n "$role_declarations" ]]; then
  printf 'Display state, browser context, and visual handoff flow roles must stay out of WebsiteCompositorView:\n%s\n' "$role_declarations" >&2
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  echo "website compositor boundary audit failed" >&2
  exit "$status"
fi

echo "website compositor boundary audit passed"
