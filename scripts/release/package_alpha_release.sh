#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$(
  xcodebuild -project "${repo_root}/Sumi.xcodeproj" \
    -target Sumi -configuration "${CONFIGURATION:-Release}" \
    -showBuildSettings \
    | awk '$1 == "MARKETING_VERSION" && $2 == "=" { print $3; exit }'
)"
if [[ -z "${version}" ]]; then
  echo "error: Could not resolve MARKETING_VERSION for Sumi." >&2
  exit 1
fi
output_dir="${OUTPUT_DIR:-${repo_root}/release/artifacts/${version}}"

"${repo_root}/scripts/release/run_release_gates.sh"

for architecture in arm64 x86_64 universal; do
  ARCHITECTURE="${architecture}" \
  CONFIGURATION="${CONFIGURATION:-Release}" \
  DERIVED_DATA_PATH="${DERIVED_DATA_PATH_ROOT:-${repo_root}/build/ReleaseAlpha}/${architecture}" \
  OUTPUT_DIR="${output_dir}" \
  RELEASE_CHANNEL=alpha \
  SKIP_ARCHITECTURE_GUARDRAILS=1 \
    "${repo_root}/scripts/release/package_release_dmg.sh"
done

printf 'Created alpha DMGs:\n'
find "${output_dir}" -maxdepth 1 -type f -name 'Sumi-*-macos-*.dmg' -print | sort
