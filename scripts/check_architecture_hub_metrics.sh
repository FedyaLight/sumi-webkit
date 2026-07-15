#!/usr/bin/env bash
set -euo pipefail

# Compatibility entry point for focused local runs. Living structural budgets
# and semantic boundaries are intentionally separate; historical tombstones
# are run independently by check_architecture_guardrails.sh.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/check_architecture_structural_metrics.sh"
"$script_dir/check_architecture_structural_boundaries.sh"

printf '\narchitecture living-structure guards passed\n'
