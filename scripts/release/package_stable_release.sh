#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
configuration="${CONFIGURATION:-Release}"
build_settings="$(
  xcodebuild -project "${repo_root}/Sumi.xcodeproj" \
    -target Sumi -configuration "${configuration}" \
    -showBuildSettings
)"
version="$(awk '$1 == "MARKETING_VERSION" && $2 == "=" { print $3; exit }' <<<"${build_settings}")"
build="$(awk '$1 == "CURRENT_PROJECT_VERSION" && $2 == "=" { print $3; exit }' <<<"${build_settings}")"
if [[ -z "${version}" || -z "${build}" ]]; then
  echo "error: Could not resolve Sumi version and build settings." >&2
  exit 1
fi
output_dir="${OUTPUT_DIR:-${repo_root}/release/artifacts/${version}}"
archive_path="${output_dir}/Sumi-${version}-build${build}-macos-arm64.dmg"

"${repo_root}/scripts/release/run_release_gates.sh"

ARCHITECTURE=arm64 \
CONFIGURATION="${configuration}" \
DERIVED_DATA_PATH="${DERIVED_DATA_PATH_ROOT:-${repo_root}/build/ReleaseStable}/arm64" \
OUTPUT_DIR="${output_dir}" \
OUTPUT_PATH="${archive_path}" \
RELEASE_CHANNEL=stable \
SKIP_ARCHITECTURE_GUARDRAILS=1 \
  "${repo_root}/scripts/release/package_release_dmg.sh"

printf 'Created stable release DMG:\n%s\n' "${archive_path}"
