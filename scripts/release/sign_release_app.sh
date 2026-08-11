#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Sumi.app" >&2
  exit 2
fi

app_path="$1"
if [[ ! -d "${app_path}" ]]; then
  echo "error: Missing app bundle: ${app_path}" >&2
  exit 1
fi

temporary_root="$(mktemp -d /tmp/SumiReleaseSigning.XXXXXX)"
trap 'rm -rf "${temporary_root}"' EXIT

certificate_dir="${temporary_root}/certificates"
mkdir -p "${certificate_dir}"
(
  cd "${certificate_dir}"
  codesign -d --extract-certificates "${app_path}"
)
signing_identity="$(shasum -a 1 "${certificate_dir}/codesign0" | awk '{print $1}')"

sign_code_object() {
  codesign \
    --force \
    --sign "${signing_identity}" \
    --preserve-metadata=identifier,entitlements,flags,runtime,requirements \
    "$1"
}

frameworks_dir="${app_path}/Contents/Frameworks"
shopt -s nullglob
frameworks=("${frameworks_dir}"/*.framework)
if (( ${#frameworks[@]} == 0 )); then
  echo "error: App contains no embedded frameworks: ${frameworks_dir}" >&2
  exit 1
fi

signed_objects=()
for framework_path in "${frameworks[@]}"; do
  if [[ "$(basename "${framework_path}")" == "Sparkle.framework" ]]; then
    sparkle_version="${framework_path}/Versions/Current"
    sparkle_helpers=(
      "${sparkle_version}/Autoupdate"
      "${sparkle_version}/Updater.app"
      "${sparkle_version}/XPCServices/Downloader.xpc"
      "${sparkle_version}/XPCServices/Installer.xpc"
    )
    for helper_path in "${sparkle_helpers[@]}"; do
      if [[ ! -e "${helper_path}" ]]; then
        echo "error: Missing Sparkle code object: ${helper_path}" >&2
        exit 1
      fi
      sign_code_object "${helper_path}"
      signed_objects+=("${helper_path}")
    done
  fi
  sign_code_object "${framework_path}"
  signed_objects+=("${framework_path}")
done

sign_code_object "${app_path}"
codesign --verify --deep --strict --verbose=1 "${app_path}"

team_identifier() {
  codesign -dv --verbose=4 "$1" 2>&1 \
    | awk -F= '$1 == "TeamIdentifier" { print $2; exit }'
}

expected_team="$(team_identifier "${app_path}")"
if [[ -z "${expected_team}" || "${expected_team}" == "not set" ]]; then
  echo "error: Release app is not signed by a development team" >&2
  exit 1
fi

for object_path in "${signed_objects[@]}"; do
  actual_team="$(team_identifier "${object_path}")"
  if [[ "${actual_team}" != "${expected_team}" ]]; then
    echo "error: ${object_path} is signed by team '${actual_team}', expected '${expected_team}'" >&2
    exit 1
  fi
done

printf 'Signed and verified %s with team %s\n' "${app_path}" "${expected_team}"
