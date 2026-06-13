#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
configuration="${CONFIGURATION:-Release}"
derived_data_path="${DERIVED_DATA_PATH:-${repo_root}/build/ReleaseAlpha}"
output_dir="${OUTPUT_DIR:-${repo_root}/release/artifacts}"
app_path="${APP_PATH:-}"
skip_build="${SKIP_BUILD:-0}"

mkdir -p "${output_dir}"

if [[ -z "${app_path}" ]]; then
  if [[ "${skip_build}" != "1" ]]; then
    xcodebuild \
      -project "${repo_root}/Sumi.xcodeproj" \
      -scheme Sumi \
      -configuration "${configuration}" \
      -derivedDataPath "${derived_data_path}" \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY=- \
      DEVELOPMENT_TEAM= \
      build
  fi

  app_path="${derived_data_path}/Build/Products/${configuration}/Sumi.app"
fi

if [[ ! -d "${app_path}" ]]; then
  echo "Missing app bundle: ${app_path}" >&2
  exit 1
fi

info_plist="${app_path}/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")"
archive_name="Sumi-${version}-${build}-alpha-macos.zip"
archive_path="${output_dir}/${archive_name}"

rm -f "${archive_path}"
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${archive_path}"

printf 'Created alpha archive:\n%s\n' "${archive_path}"
