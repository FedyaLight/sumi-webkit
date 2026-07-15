#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

# Upstream DDG test trees must NOT be vendored: Sumi's only test gates are the
# shared schemes running SumiTests/SumiUITests, and dead upstream test code is
# not allowed back into the snapshot.
forbidden_test_roots=(
  "Vendor/DDG/BrowserServicesKit/Tests"
)

active_sumi_testables=(
  "SumiTests"
  "SumiUITests"
)

ddg_library_products=(
  "Navigation"
)

contains_active_testable() {
  local candidate="$1"
  local allowed

  for allowed in "${active_sumi_testables[@]}"; do
    if [[ "$candidate" == "$allowed" ]]; then
      return 0
    fi
  done

  return 1
}

project_file="Sumi.xcodeproj/project.pbxproj"
scheme_dir="Sumi.xcodeproj/xcshareddata/xcschemes"

guard_require_file "$project_file"
guard_require_directory "$scheme_dir"

for root in "${forbidden_test_roots[@]}"; do
  if [[ -e "$root" || -L "$root" ]]; then
    guard_record_failure "upstream DDG test root must not be vendored: $root"
    exit 1
  fi
done

expected_ddg_products="$(printf "%s\n" "${ddg_library_products[@]}" | sort)"
actual_ddg_products="$(
  sed -n '/\/\* Begin XCSwiftPackageProductDependency section \*\//,/\/\* End XCSwiftPackageProductDependency section \*\//p' "$project_file" |
    awk '
      / = \{/ {
        product = ""
        is_ddg = 0
      }
      /package = .*Vendor\/DDG\/(BrowserServicesKit|URLPredictor)/ {
        is_ddg = 1
      }
      /productName = / {
        product = $0
        sub(/^[[:space:]]*productName = /, "", product)
        sub(/;[[:space:]]*$/, "", product)
      }
      /^[[:space:]]*};/ {
        if (is_ddg && product != "") {
          print product
        }
        product = ""
        is_ddg = 0
      }
    ' |
    sort
)"

if [[ "$actual_ddg_products" != "$expected_ddg_products" ]]; then
  guard_record_failure "unexpected DDG package products linked by $project_file. Expected: ${ddg_library_products[*]}; actual: ${actual_ddg_products//$'\n'/ }"
  exit 1
fi

scheme_count=0
tested_scheme_count=0

scheme_files="$(
  find "$scheme_dir" -type f -name '*.xcscheme' -print | sort
)"
while IFS= read -r scheme; do
  [[ -n "$scheme" ]] || continue
  scheme_count=$((scheme_count + 1))

  testable_names="$(
    sed -n '/<Testables>/,/<\/Testables>/p' "$scheme" |
      sed -n 's/.*BlueprintName = "\([^"]*\)".*/\1/p'
  )"

  if [[ -z "$testable_names" ]]; then
    continue
  fi

  tested_scheme_count=$((tested_scheme_count + 1))

  while IFS= read -r testable_name; do
    [[ -n "$testable_name" ]] || continue
    if ! contains_active_testable "$testable_name"; then
      guard_record_failure "$scheme references non-Sumi testable: $testable_name"
      exit 1
    fi
  done <<< "$testable_names"

  testables_xml="$(sed -n '/<Testables>/,/<\/Testables>/p' "$scheme")"
  vendor_test_reference_count="$(
    guard_count_matches 'Vendor/DDG|BrowserServicesKit|URLPredictorTests' - <<< "$testables_xml"
  )"
  if (( vendor_test_reference_count > 0 )); then
    guard_record_failure "$scheme references DDG vendor tests from its TestAction"
    exit 1
  fi
done <<< "$scheme_files"

if [[ "$scheme_count" -eq 0 ]]; then
  guard_record_failure "no shared Xcode schemes found under $scheme_dir"
  exit 1
fi

if [[ "$tested_scheme_count" -eq 0 ]]; then
  guard_record_failure "no shared Xcode schemes declare testables"
  exit 1
fi

echo "OK: no upstream DDG test trees are vendored."
echo "OK: Sumi DDG package products are limited to ${ddg_library_products[*]}."
echo "OK: Sumi shared scheme testables are limited to ${active_sumi_testables[*]}."
