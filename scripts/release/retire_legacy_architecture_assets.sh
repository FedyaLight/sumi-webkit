#!/usr/bin/env bash
set -euo pipefail

repo="FedyaLight/sumi-webkit"
apply=0

usage() {
  cat <<'EOF'
Usage: scripts/release/retire_legacy_architecture_assets.sh [--apply]

Lists historic Intel and Universal Sumi DMGs. With --apply, deletes them only
after both public Sparkle feeds no longer reference any candidate URL.
EOF
}

case "${1:-}" in
  "") ;;
  --apply) apply=1 ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if ! command -v gh >/dev/null; then
  echo "error: GitHub CLI (gh) is required." >&2
  exit 1
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/SumiRetireLegacyAssets.XXXXXX")"
trap 'rm -rf "${temporary_dir}"' EXIT
candidates_file="${temporary_dir}/candidates.tsv"

gh api --paginate "repos/${repo}/releases?per_page=100" \
  --jq '.[] | .tag_name as $tag | .assets[] | select(.name | test("-macos-(x86_64|universal)\\.dmg$")) | [$tag, .name, .browser_download_url] | @tsv' \
  > "${candidates_file}"

if [[ ! -s "${candidates_file}" ]]; then
  echo "No historic Intel or Universal Sumi DMGs found."
  exit 0
fi

while IFS=$'\t' read -r tag asset_name _; do
  if ! gh release view "${tag}" --repo "${repo}" --json assets --jq '.assets[].name' | grep -Eq -- '-macos-arm64\.dmg$'; then
    echo "error: Refusing to retire ${tag}/${asset_name}: no Arm64 DMG remains on that release." >&2
    exit 1
  fi
done < "${candidates_file}"

if [[ "${apply}" == "1" ]]; then
  alpha_appcast="${temporary_dir}/appcast-alpha.xml"
  bridge_appcast="${temporary_dir}/appcast.xml"
  curl --fail --location --silent --show-error \
    "https://fedyalight.github.io/sumi-webkit/appcast-alpha.xml" > "${alpha_appcast}"
  curl --fail --location --silent --show-error \
    "https://fedyalight.github.io/sumi-webkit/appcast.xml" > "${bridge_appcast}"

  while IFS=$'\t' read -r tag asset_name asset_url; do
    for appcast in "${alpha_appcast}" "${bridge_appcast}"; do
      if grep -Fq "${asset_url}" "${appcast}"; then
        echo "error: Refusing to retire ${tag}/${asset_name}: it is still referenced by ${appcast}." >&2
        exit 1
      fi
    done
  done < "${candidates_file}"
fi

if [[ "${apply}" == "0" ]]; then
  echo "Dry run only. The following assets would be retired after the new Arm-only feeds are public:"
fi

while IFS=$'\t' read -r tag asset_name _; do
  printf '%s\t%s\n' "${tag}" "${asset_name}"
  if [[ "${apply}" == "1" ]]; then
    gh release delete-asset "${tag}" "${asset_name}" --repo "${repo}" --yes
  fi
done < "${candidates_file}"

if [[ "${apply}" == "0" ]]; then
  echo "Run again with --apply only after publishing both Arm64 appcasts."
fi
