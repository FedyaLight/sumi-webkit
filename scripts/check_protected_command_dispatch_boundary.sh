#!/usr/bin/env bash
# Protected commands are split into pure authority, admission, processing, and
# stateless execution. This guard prevents those responsibilities from merging.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

runtime='Sumi/Managers/WebViewRuntime'
authority="$runtime/DeferredWebViewCommandAuthority.swift"
executor="$runtime/DeferredWebViewCommandExecutor.swift"
admission="$runtime/DeferredProtectedCommandAdmissionService.swift"
processor="$runtime/DeferredProtectedCommandProcessor.swift"
command='Packages/SumiWebRuntime/Sources/SumiWebRuntime/Commands/DeferredWebViewCommand.swift'

for file in "$authority" "$executor" "$admission" "$processor" "$command"; do
  guard_require_file "$file"
done

obsolete=(
  "$runtime/WebViewProtectedCommandDispatchOwner.swift"
  "$runtime/WebViewDeferredProtectedCommandExecutionOwner.swift"
  "$runtime/DeferredProtectedCommandScheduler.swift"
)
for file in "${obsolete[@]}"; do
  guard_expect_absent_path 'obsolete protected-command god surface' "$file"
done

guard_expect_no_matches \
  'obsolete protected-command symbols' \
  'WebViewProtectedCommandDispatchOwner|WebViewDeferredProtectedCommandExecutionOwner' \
  -g '*.swift' Sumi SumiTests
guard_expect_no_matches \
  'generic protected-command responsibility bags' \
  'struct (Dependencies|Runtime|ValidationContext)' \
  "$authority" "$executor" "$admission" "$processor"
guard_expect_no_matches \
  'execution/task/model/dispatch ownership in protected-command admission' \
  '\b(Tab|WebViewSessionRepository|VisibleWebViewRuntimeOwner|WebViewWindowServices|DeferredWebViewCommandExecutor)\b|\bTask\b|switch[[:space:]]+command' \
  "$admission"
guard_expect_no_matches \
  'model validation/dispatch in protected-command processor' \
  '\b(Tab|WebViewSessionRepository|VisibleWebViewRuntimeOwner|WebViewWindowServices)\b|switch[[:space:]]+command' \
  "$processor"
guard_expect_no_matches \
  'scheduling/protection state in protected-command executor' \
  '\bTask\b|retryTasks|retryAttempts|WebViewMediaProtectionOwner' \
  "$executor"

raw_switch_files="$(
  guard_capture_matches 'switch[[:space:]]+command' -g '*.swift' "$runtime" \
    | cut -d: -f1 \
    | sort -u
)"
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    "$authority"|"$executor") ;;
    *)
      guard_record_failure "deferred command switch escaped authority/executor: $file"
      ;;
  esac
done <<< "$raw_switch_files"

if (( $(
  guard_count_matches \
    'enum DeferredProtectedCommandExecutionOutcome' \
    "$command"
) == 0 )); then
  guard_record_failure 'deferred command execution lost its typed outcome'
fi

guard_finish 'protected command authority/admission/processor/executor boundary'
