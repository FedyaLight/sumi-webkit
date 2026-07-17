#!/usr/bin/env bash
# Narrow contract guard for manifest-owned process-level test sharding.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

python3 scripts/ci/test_ci_manifest.py
bash -n \
  scripts/ci/run_tests.sh \
  scripts/ci/preflight.sh \
  scripts/ci/check_test_sharding.sh \
  scripts/install_dev_hooks.sh \
  .githooks/pre-push
ruby -e 'require "yaml"; ARGV.each { |path| YAML.parse_file(path) }' \
  .github/workflows/sumi-ci.yml \
  .github/workflows/sumi-nightly.yml
scripts/ci/run_tests.sh validate
