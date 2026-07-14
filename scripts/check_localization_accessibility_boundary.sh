#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

app_roots=(App FloatingBar Settings Sumi SidebarChrome UI)
catalog="Sumi/Resources/Localizable.xcstrings"

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
if catalog.get("version") != "1.0":
    raise SystemExit("String Catalog version must remain 1.0")

strings = catalog.get("strings")
if not isinstance(strings, dict):
    raise SystemExit("String Catalog strings must be a dictionary")
expected_extracted_key_count = 393
if len(strings) != expected_extracted_key_count:
    raise SystemExit(
        "String Catalog must match the checked-in full-target extraction "
        f"(found {len(strings)} entries; expected {expected_extracted_key_count})"
    )

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

require_literal() {
  local literal="$1"
  local file="$2"
  local message="$3"
  if ! rg -qF "$literal" "$file"; then
    printf 'error: %s (%s)\n' "$message" "$file" >&2
    exit 1
  fi
}

typed_descriptor_files=(
  "Sumi/Services/SumiBrowsingDataCleanupService.swift"
  "Sumi/Managers/DownloadManager/SumiDownloadPreferences.swift"
  "Sumi/Models/Window/SidebarPosition.swift"
  "Sumi/ImportExport/SumiImportExportModels.swift"
  "Sumi/Components/Sidebar/URLBarHubSnapshotActions.swift"
  "Sumi/Components/Sidebar/URLBarHubScreenshotSettingsPresenter.swift"
)
for file in "${typed_descriptor_files[@]}"; do
  require_literal 'LocalizedStringResource' "$file" \
    "non-view product descriptors must retain localization metadata"
done

if rg -n \
  '(class|struct|actor|enum|protocol)[[:space:]]+(Sumi)?(LocalizationManager|LocalizationService|Localizer|AccessibilityManager)\b' \
  "${app_roots[@]}" --glob '*.swift'; then
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
  require_literal "$literal" "$file" "required semantic or keyboard contract is missing"
done

echo 'localization and accessibility boundary guard passed'
