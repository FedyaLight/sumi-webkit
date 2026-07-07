#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
configuration="${CONFIGURATION:-Release}"
derived_data_path="${DERIVED_DATA_PATH:-${repo_root}/build/ReleaseDmg}"
output_dir="${OUTPUT_DIR:-${HOME}/Downloads}"
destination="${DESTINATION:-platform=macOS,arch=arm64}"
volume_name="Sumi"
mounted_volume="/Volumes/${volume_name}"
staging_dir="${repo_root}/build/ReleaseDmgStage"
rw_dmg="${repo_root}/build/Sumi-release-rw.dmg"

cd "${repo_root}"

if [[ -e "${mounted_volume}" ]]; then
  echo "error: ${mounted_volume} is already mounted. Eject it before packaging." >&2
  exit 1
fi

"${repo_root}/scripts/check_architecture_guardrails.sh"
"${repo_root}/scripts/bootstrap_vendor_binaries.sh"
"${repo_root}/scripts/verify_vendor_checksums.sh"

rm -rf "${derived_data_path}"
mkdir -p "${derived_data_path}"

xcodebuild \
  -quiet \
  -project "${repo_root}/Sumi.xcodeproj" \
  -scheme Sumi \
  -configuration "${configuration}" \
  -destination "${destination}" \
  -derivedDataPath "${derived_data_path}" \
  build

app_path="${derived_data_path}/Build/Products/${configuration}/Sumi.app"
if [[ ! -d "${app_path}" ]]; then
  echo "error: Missing app bundle: ${app_path}" >&2
  exit 1
fi

info_plist="${app_path}/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")"
output_path="${OUTPUT_PATH:-${output_dir}/Sumi-${version}-${build}-release.dmg}"

rm -rf "${staging_dir}" "${rw_dmg}" "${rw_dmg}.shadow"
mkdir -p "${staging_dir}" "${output_dir}"
ditto "${app_path}" "${staging_dir}/Sumi.app"
ln -s /Applications "${staging_dir}/Applications"

hdiutil create \
  -volname "${volume_name}" \
  -srcfolder "${staging_dir}" \
  -ov \
  -format UDRW \
  "${rw_dmg}"

cleanup() {
  if [[ -e "${mounted_volume}" ]]; then
    hdiutil detach "${mounted_volume}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

hdiutil attach -readwrite -noverify -noautoopen "${rw_dmg}" >/dev/null

osascript <<'OSA'
tell application "Finder"
  set theDisk to disk "Sumi"
  open theDisk
  delay 1
  set theWindow to container window of theDisk
  set current view of theWindow to icon view
  set toolbar visible of theWindow to false
  set statusbar visible of theWindow to false
  try
    set pathbar visible of theWindow to false
  end try
  set bounds of theWindow to {160, 140, 720, 400}
  set theOptions to icon view options of theWindow
  set arrangement of theOptions to not arranged
  set icon size of theOptions to 112
  set text size of theOptions to 13
  set position of item "Sumi.app" of theDisk to {170, 95}
  set position of item "Applications" of theDisk to {390, 95}
  update theDisk without registering applications
  delay 2
  close theWindow
end tell
OSA

cp "${app_path}/Contents/Resources/logo.icns" "${mounted_volume}/.VolumeIcon.icns"
SetFile -a V "${mounted_volume}/.VolumeIcon.icns"
SetFile -a C "${mounted_volume}"
rm -rf "${mounted_volume}/.fseventsd"
sync

hdiutil detach "${mounted_volume}" >/dev/null
trap - EXIT

rm -f "${output_path}"
hdiutil convert "${rw_dmg}" -format UDZO -o "${output_path}" -ov >/dev/null

hdiutil verify "${output_path}" >/dev/null
codesign --verify --deep --strict --verbose=1 "${app_path}"

rm -rf "${staging_dir}" "${rw_dmg}" "${rw_dmg}.shadow"

printf 'Created release DMG:\n%s\n' "${output_path}"
shasum -a 256 "${output_path}"
