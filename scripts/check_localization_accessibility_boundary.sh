#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

app_roots=(App CommandPalette Settings Sumi SidebarChrome UI)
catalog="Sumi/Resources/Localizable.xcstrings"

for root in "${app_roots[@]}"; do
  guard_require_directory "$root"
done
catalogs="$(find "${app_roots[@]}" -type f -name '*.xcstrings' -print | sort)"
catalog_count="$(printf '%s\n' "$catalogs" | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "$catalog_count" -ne 1 || "$catalogs" != "$catalog" ]]; then
  printf 'expected exactly one app String Catalog at %s; found:\n' "$catalog" >&2
  printf '  %s\n' "${catalogs:-<none>}" >&2
  exit 1
fi

python3 - "$catalog" <<'PY'
import json
import sys

catalog_path = sys.argv[1]
with open(catalog_path, encoding="utf-8") as file:
    catalog = json.load(file)

if catalog.get("sourceLanguage") != "en":
    raise SystemExit("String Catalog sourceLanguage must remain en")
if not isinstance(catalog.get("version"), str) or not catalog["version"]:
    raise SystemExit("String Catalog version must be a non-empty string")

strings = catalog.get("strings")
if not isinstance(strings, dict):
    raise SystemExit("String Catalog strings must be a dictionary")

required_keys = {
    "Ask whether to open or save files",
    "Close Glance",
    "Find in page",
    "Go Back",
    "Open in Split View",
    "Rearrange Split",
    "Screenshot Settings",
    "Send Global Privacy Control signal",
}
missing = sorted(required_keys - strings.keys())
if missing:
    raise SystemExit("String Catalog is missing required product keys: " + ", ".join(missing))
PY

typed_descriptor_files=(
  "Sumi/Services/SumiBrowsingDataCleanupService.swift"
  "Sumi/Managers/DownloadManager/SumiDownloadPreferences.swift"
  "Sumi/Models/Window/SidebarPosition.swift"
  "Sumi/ImportExport/SumiImportExportModels.swift"
  "Sumi/Components/Sidebar/URLBarHubSnapshotActions.swift"
  "Sumi/Components/Sidebar/URLBarHubScreenshotSettingsPresenter.swift"
)
for file in "${typed_descriptor_files[@]}"; do
  guard_require_file "$file"
  literal_count="$(guard_count_matches 'LocalizedStringResource' -F "$file")"
  if (( literal_count == 0 )); then
    printf 'error: non-view product descriptors must retain localization metadata (%s)\n' \
      "$file" >&2
    exit 1
  fi
done

replacement_hits="$(guard_capture_matches \
  '(class|struct|actor|enum|protocol)[[:space:]]+(Sumi)?(LocalizationManager|LocalizationService|Localizer|AccessibilityManager)\b' \
  "${app_roots[@]}" --glob '*.swift')"
if [[ -n "$replacement_hits" ]]; then
  printf '%s\n' "$replacement_hits"
  echo 'localization/accessibility must not gain a manager, service, facade, or global replacement' >&2
  exit 1
fi

semantic_contracts=(
  "Sumi/Components/Glance/GlanceOverlayActionChrome.swift|glance-action-close"
  "Sumi/Components/Glance/GlanceOverlayActionChrome.swift|refusesFirstResponder = false"
  "Sumi/Components/WebsiteView/SplitPaneControlsView.swift|split-pane-rearrange"
  "Sumi/Components/WebsiteView/SplitPaneControlsView.swift|split-pane-expand-tab"
  "Sumi/Components/FindInPage/FindInPageViewController.swift|FindInPageController.nextButton"
  "Sumi/Components/FindInPage/FindInPageViewController.swift|Next match (Return)"
  "Sumi/Components/Sidebar/SumiNavigationToolbarControls.swift|navigation-go-back"
  "Sumi/Components/Sidebar/SumiNavigationToolbarControls.swift|navigation-reload-or-stop"
  "Sumi/Components/Sidebar/URLBarHubScreenshotSettingsPresenter.swift|screenshot-settings-confirm"
  "Sumi/Components/Settings/PrivacySettingsView.swift|privacy-global-privacy-control"
  "Sumi/Components/Settings/PrivacySettingsView.swift|privacy-update-protection-bundles"
  "App/SumiCommands.swift|dynamicShortcut(.findInPage)"
  "App/SumiCommands.swift|dynamicShortcut(.refresh)"
)
for contract in "${semantic_contracts[@]}"; do
  file="${contract%%|*}"
  literal="${contract#*|}"
  guard_require_file "$file"
  literal_count="$(guard_count_matches "$literal" -F "$file")"
  if (( literal_count == 0 )); then
    printf 'error: required semantic or keyboard contract is missing (%s)\n' "$file" >&2
    exit 1
  fi
done

echo 'localization and accessibility boundary guard passed'
