#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

profile_manager="Sumi/Managers/ProfileManager/ProfileManager.swift"
startup_persistence="Sumi/Services/SumiStartupPersistence.swift"
database_schema="Sumi/Persistence/SumiDatabase.swift"
profile_transition="Sumi/Managers/WebViewRuntime/ProfileTransitionService.swift"
batch_transition="Sumi/Managers/WebViewRuntime/PreparedProfileAssignmentBatchTransitionService.swift"
retirement_store="Sumi/Services/ProfileRetirementStore.swift"
retirement_workflow="Sumi/Services/SumiProfileMaintenanceService.swift"
retirement_recovery="Sumi/Services/ProfileRetirementStartupRecovery.swift"
startup_recovery="Sumi/Services/SumiStartupRecoveryTransaction.swift"
app_root="App/SumiApp.swift"
browser_retirement_coordinator="Sumi/Managers/BrowserManager/BrowserProfileReferenceRetirementCoordinator.swift"
browser_deletion_workflow="Sumi/Managers/BrowserManager/BrowserProfileDeletionWorkflow.swift"
browser_retirement_recovery="Sumi/Managers/BrowserManager/BrowserProfileRetirementStartupRecovery.swift"
browser_profile_lifecycle="Sumi/Managers/BrowserManager/BrowserProfileLifecycleBundle.swift"
production_roots=(App Sumi Settings SidebarChrome CommandPalette UI Packages)

for source in \
  "$profile_manager" \
  "$startup_persistence" \
  "$database_schema" \
  "$profile_transition" \
  "$batch_transition" \
  "$retirement_store" \
  "$retirement_workflow" \
  "$retirement_recovery" \
  "$startup_recovery" \
  "$browser_retirement_coordinator" \
  "$browser_deletion_workflow" \
  "$browser_retirement_recovery" \
  "$browser_profile_lifecycle" \
  "$app_root"; do
  guard_require_file "$source"
done

printf '%s\n' 'Profile-retirement boundary audit'
printf '%s\n' '---------------------------------'

guard_expect_no_matches \
  'stub profile cleanup participants' \
  '\bStubProfileCleanupParticipant\b' \
  --glob '*.swift' "${production_roots[@]}"

guard_expect_no_matches \
  'ProfileManager-owned deletion entry points' \
  'func[[:space:]]+deleteProfile[[:space:]]*\(' \
  "$profile_manager"

guard_expect_no_matches \
  'direct ProfileManager deletion calls' \
  '\bprofileManager[[:space:]]*\.[[:space:]]*deleteProfile[[:space:]]*\(' \
  --glob '*.swift' "${production_roots[@]}"

guard_expect_no_matches \
  'browser profile retirement manager reachback' \
  '\b(BrowserManager|TabManager|browserManager|tabManager)\b' \
  "$browser_retirement_coordinator" \
  "$browser_deletion_workflow" \
  "$browser_retirement_recovery"
guard_expect_no_matches \
  'browser profile retirement generic dependency bags' \
  '\bstruct[[:space:]]+(Context|Dependencies|Actions|Environment|Capabilities)\b' \
  "$browser_retirement_coordinator" \
  "$browser_deletion_workflow" \
  "$browser_retirement_recovery"
guard_expect_no_matches \
  'browser profile retirement live manager factories' \
  'BrowserProfileReferenceRetirementCoordinator\.live|BrowserProfileRetirementStartupRecovery\.make[[:space:]]*\([[:space:]]*browserManager:' \
  --glob '*.swift' "${production_roots[@]}"
guard_expect_no_matches \
  'profile lifecycle manager-fed initializer' \
  'BrowserProfileLifecycleBundle[[:space:]]*\([[:space:]]*browserManager:' \
  --glob '*.swift' "${production_roots[@]}"
guard_expect_no_matches \
  'profile-switch manager-shaped host' \
  '\bBrowserProfileSwitchTransitionHost\b|host:[[:space:]]*browserManager' \
  --glob '*.swift' "${production_roots[@]}"

schema_version_count="$({
  guard_count_matches \
    'PRAGMA user_version = 1' \
    "$database_schema"
})"
guard_exact 'unified database schema version declaration' "$schema_version_count" 1

retirement_table_count="$({
  guard_count_matches \
    'database\.create\(table: "profile_retirements"\)' \
    "$database_schema"
})"
guard_exact 'retirement journal table in unified database schema' "$retirement_table_count" 1

transition_entry_count="$({
  guard_count_matches '^    func transition[[:space:]]*\(' "$profile_transition"
})"
transition_admission_count="$({
  guard_count_matches 'profileAdmissions\.admitReference[[:space:]]*\(' "$profile_transition"
})"
transition_wrapper_count="$({
  guard_count_matches 'ProfileReferenceAdmittedModelTransaction[[:space:]]*\(' "$profile_transition"
})"
guard_exact 'single-profile async transition entry points' "$transition_entry_count" 2
guard_exact 'single-profile transition admission receipts' "$transition_admission_count" 2
guard_exact 'single-profile admitted model wrappers' "$transition_wrapper_count" 2

batch_entry_count="$({
  guard_count_matches '^    func transition[[:space:]]*\(' "$batch_transition"
})"
batch_admission_count="$({
  guard_count_matches 'profileAdmissions\.admitReference[[:space:]]*\(' "$batch_transition"
})"
batch_wrapper_count="$({
  guard_count_matches 'ProfileReferenceAdmittedModelTransaction[[:space:]]*\(' "$batch_transition"
})"
guard_exact 'batch profile transition entry points' "$batch_entry_count" 1
guard_exact 'batch profile transition admission sites' "$batch_admission_count" 1
guard_exact 'batch admitted model wrappers' "$batch_wrapper_count" 1

migrating_phase_count="$({
  guard_count_matches '^    case migratingReferences$' "$retirement_store"
})"
guard_exact 'durable reference-migration phase' "$migrating_phase_count" 1

workflow_begin_count="$({
  guard_count_matches 'beginReferenceMigration\(token\)' "$retirement_workflow"
})"
workflow_cancel_count="$({
  guard_count_matches 'cancelReservation\(token, using: context\)' "$retirement_workflow"
})"
guard_exact 'single point-of-no-return transition' "$workflow_begin_count" 1
guard_exact 'reservation cancellation before point-of-no-return' "$workflow_cancel_count" 2

app_startup_authority_count="$({
  guard_count_matches '@State private var startupRecovery = SumiStartupRecoveryTransaction\(\)' "$app_root"
})"
runtime_start_count="$({
  guard_count_matches 'browserManager\.startRuntimeAfterStartupRecovery\(\)' "$app_root"
})"
guard_exact 'single app startup-recovery authority' "$app_startup_authority_count" 1
guard_exact 'single post-recovery runtime start' "$runtime_start_count" 1

migration_begin_line="$(guard_capture_matches 'beginReferenceMigration\(token\)' "$retirement_workflow" | head -1 | cut -d: -f1)"
forward_migration_line="$(guard_capture_matches 'let migration = await context\.migrateProfileReferences' "$retirement_workflow" | head -1 | cut -d: -f1)"
last_cancel_line="$(guard_capture_matches 'cancelReservation\(token, using: context\)' "$retirement_workflow" | tail -1 | cut -d: -f1)"
logical_delete_line="$(guard_capture_matches 'commitLogicalDeletion\(token\)' "$retirement_workflow" | head -1 | cut -d: -f1)"
runtime_seal_line="$(guard_capture_matches 'sealProfileRuntime\(profile\.id\)' "$retirement_workflow" | head -1 | cut -d: -f1)"
if [[ -z "$last_cancel_line" || -z "$migration_begin_line" || -z "$forward_migration_line" || -z "$logical_delete_line" || -z "$runtime_seal_line" ]] \
  || (( migration_begin_line >= forward_migration_line )) \
  || (( last_cancel_line >= forward_migration_line )) \
  || (( forward_migration_line >= logical_delete_line )) \
  || (( logical_delete_line >= runtime_seal_line )); then
  guard_record_failure 'retirement ordering must be cancelable preflight → migrating → logical deletion → irreversible runtime seal'
fi

guard_finish 'profile-retirement boundary audit'
