#!/usr/bin/env bash
set -euo pipefail

tool_name="${1:?usage: find_sparkle_tool.sh TOOL_NAME}"

if [[ -n "${SPARKLE_BIN:-}" && -x "${SPARKLE_BIN}/${tool_name}" ]]; then
  printf '%s\n' "${SPARKLE_BIN}/${tool_name}"
  exit 0
fi

if [[ -n "${SPARKLE_TOOLS_DIR:-}" && -x "${SPARKLE_TOOLS_DIR}/${tool_name}" ]]; then
  printf '%s\n' "${SPARKLE_TOOLS_DIR}/${tool_name}"
  exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

candidate_roots=(
  "${repo_root}/.build/artifacts/sparkle/Sparkle/bin"
  "${repo_root}/SourcePackages/artifacts/sparkle/Sparkle/bin"
  "${HOME}/Library/Developer/Xcode/DerivedData"
)

for root in "${candidate_roots[@]}"; do
  [[ -d "${root}" ]] || continue
  if [[ -x "${root}/${tool_name}" ]]; then
    printf '%s\n' "${root}/${tool_name}"
    exit 0
  fi
  found="$(find "${root}" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/${tool_name}" -type f -perm -111 -print -quit 2>/dev/null || true)"
  if [[ -n "${found}" ]]; then
    printf '%s\n' "${found}"
    exit 0
  fi
done

cat >&2 <<EOF
Could not find Sparkle tool: ${tool_name}

Resolve Swift packages first:
  xcodebuild -resolvePackageDependencies -project Sumi.xcodeproj -scheme Sumi

Or set one of:
  SPARKLE_BIN=/path/to/Sparkle/bin
  SPARKLE_TOOLS_DIR=/path/to/Sparkle/bin
EOF
exit 1
