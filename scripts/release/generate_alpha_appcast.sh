#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
archive_dir="${1:-${repo_root}/release/artifacts}"
download_url_prefix="${DOWNLOAD_URL_PREFIX:-}"
output_appcast="${OUTPUT_APPCAST:-${repo_root}/docs/appcast-alpha.xml}"
bridge_output_appcast="${BRIDGE_OUTPUT_APPCAST:-}"
maximum_versions="${MAXIMUM_VERSIONS:-3}"
generate_appcast="$("${repo_root}/scripts/release/find_sparkle_tool.sh" generate_appcast)"

if [[ ! -d "${archive_dir}" ]]; then
  echo "Archive directory does not exist: ${archive_dir}" >&2
  exit 1
fi

mkdir -p "$(dirname "${output_appcast}")"

args=("-o" "${output_appcast}" "--maximum-versions" "${maximum_versions}")

if [[ -n "${download_url_prefix}" ]]; then
  args+=("--download-url-prefix" "${download_url_prefix}")
fi

if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  args+=("--ed-key-file" "${SPARKLE_ED_KEY_FILE}")
fi

args+=("${archive_dir}")

"${generate_appcast}" "${args[@]}"
"${repo_root}/scripts/release/validate_appcast_signatures.sh" "${output_appcast}"

if [[ -n "${bridge_output_appcast}" ]]; then
  if [[ "${bridge_output_appcast}" == "${output_appcast}" ]]; then
    echo "BRIDGE_OUTPUT_APPCAST must differ from OUTPUT_APPCAST." >&2
    exit 1
  fi
  mkdir -p "$(dirname "${bridge_output_appcast}")"
  cp "${output_appcast}" "${bridge_output_appcast}"
  "${repo_root}/scripts/release/validate_appcast_signatures.sh" "${bridge_output_appcast}"
  printf 'Generated legacy 0.0.1 bridge appcast:\n%s\n' "${bridge_output_appcast}"
fi

printf 'Generated alpha appcast:\n%s\n' "${output_appcast}"
