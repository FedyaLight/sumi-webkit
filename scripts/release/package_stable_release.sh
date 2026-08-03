#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${OUTPUT_DIR:-${repo_root}/release/artifacts}"

"${repo_root}/scripts/release/run_release_gates.sh"

for architecture in arm64 x86_64; do
  ARCHITECTURE="${architecture}" \
  CONFIGURATION="${CONFIGURATION:-Release}" \
  DERIVED_DATA_PATH="${DERIVED_DATA_PATH_ROOT:-${repo_root}/build/ReleaseStable}/${architecture}" \
  OUTPUT_DIR="${output_dir}" \
  RELEASE_CHANNEL=stable \
  SKIP_ARCHITECTURE_GUARDRAILS=1 \
    "${repo_root}/scripts/release/package_release_dmg.sh"
done

printf 'Created stable DMGs:\n'
find "${output_dir}" -maxdepth 1 -type f -name 'Sumi-*-macos-*.dmg' -print | sort
