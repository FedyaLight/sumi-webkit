#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

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

fail() {
  echo "error: $*" >&2
  exit 1
}

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

[[ -f "$project_file" ]] || fail "missing Sumi project file: $project_file"
[[ -d "$scheme_dir" ]] || fail "missing Sumi shared schemes directory: $scheme_dir"

for root in "${forbidden_test_roots[@]}"; do
  [[ ! -e "$root" ]] || fail "upstream DDG test root must not be vendored: $root"
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
  fail "unexpected DDG package products linked by $project_file. Expected: ${ddg_library_products[*]}; actual: ${actual_ddg_products//$'\n'/ }"
fi

scheme_count=0
tested_scheme_count=0

while IFS= read -r scheme; do
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
    contains_active_testable "$testable_name" ||
      fail "$scheme references non-Sumi testable: $testable_name"
  done <<< "$testable_names"

  if sed -n '/<Testables>/,/<\/Testables>/p' "$scheme" | grep -Eq 'Vendor/DDG|BrowserServicesKit|URLPredictorTests'; then
    fail "$scheme references DDG vendor tests from its TestAction"
  fi
done < <(find "$scheme_dir" -type f -name "*.xcscheme" | sort)

if [[ "$scheme_count" -eq 0 ]]; then
  fail "no shared Xcode schemes found under $scheme_dir"
fi

if [[ "$tested_scheme_count" -eq 0 ]]; then
  fail "no shared Xcode schemes declare testables"
fi

echo "OK: no upstream DDG test trees are vendored."
echo "OK: Sumi DDG package products are limited to ${ddg_library_products[*]}."
echo "OK: Sumi shared scheme testables are limited to ${active_sumi_testables[*]}."
