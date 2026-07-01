#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

upstream_test_roots=(
  "Vendor/DDG/BrowserServicesKit/Tests"
  "Vendor/DDG/URLPredictor/Sources/URLPredictorTests"
)

active_sumi_testables=(
  "SumiTests"
  "SumiUITests"
)

ddg_library_products=(
  "Bookmarks"
  "Navigation"
  "Persistence"
  "PrivacyConfig"
  "URLPredictor"
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

require_file_mentions_path() {
  local file="$1"
  local path="$2"

  [[ -f "$file" ]] || fail "missing quarantine documentation: $file"
  grep -Fq "$path" "$file" || fail "$file does not mention $path"
}

doc_path="Vendor/DDG/UPSTREAM_TESTS.md"
project_file="Sumi.xcodeproj/project.pbxproj"
scheme_dir="Sumi.xcodeproj/xcshareddata/xcschemes"

[[ -f "$project_file" ]] || fail "missing Sumi project file: $project_file"
[[ -d "$scheme_dir" ]] || fail "missing Sumi shared schemes directory: $scheme_dir"

swift_test_file_count=0

for root in "${upstream_test_roots[@]}"; do
  [[ -d "$root" ]] || fail "missing upstream DDG test root: $root"
  [[ -f "$root/README.md" ]] || fail "missing quarantine marker: $root/README.md"
  require_file_mentions_path "$doc_path" "$root"

  while IFS= read -r _; do
    swift_test_file_count=$((swift_test_file_count + 1))
  done < <(find "$root" -type f -name "*.swift")
done

if [[ "$swift_test_file_count" -eq 0 ]]; then
  fail "DDG upstream test roots contain no Swift test files; update quarantine docs if the snapshot changed"
fi

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

echo "OK: DDG upstream tests are quarantined reference material."
echo "OK: Sumi DDG package products are limited to ${ddg_library_products[*]}."
echo "OK: Sumi shared scheme testables are limited to ${active_sumi_testables[*]}."
