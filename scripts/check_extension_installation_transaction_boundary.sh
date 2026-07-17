#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$root"

capture_matches() {
    guard_capture_matches "$@"
}

require_matches() {
    local pattern="$1"
    shift
    local count
    count="$(guard_count_matches "$pattern" "$@")" || return
    if (( count == 0 )); then
        printf 'error: required installation production invariant missing: %s\n' "$pattern" >&2
        return 1
    fi
}

scan_has_matches() {
    local pattern="$1"
    shift
    local count
    count="$(guard_count_matches "$pattern" "$@")" || exit $?
    (( count > 0 ))
}
service="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationService.swift"
record="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationRecordTransaction.swift"
policy="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationFailurePolicy.swift"
settlement="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationFailureSettlement.swift"
identity="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationIdentityResolver.swift"
admission="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationAdmission.swift"
package="$root/Sumi/Managers/ExtensionManager/ExtensionPackageInstallTransaction.swift"
prepared_package="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationPackage.swift"
layout="$root/Sumi/Managers/ExtensionManager/ExtensionPackageLayout.swift"
maintenance="$root/Sumi/Managers/ExtensionManager/ExtensionPackageMaintenance.swift"
metadata_store="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationMetadataStore.swift"

if scan_has_matches 'struct (Environment|Dependencies)|ExtensionInstallationService\.Environment' \
    "$service" "$record" "$policy" "$settlement" "$identity" "$admission"; then
    echo "installation transaction roles must not hide collaborators in dependency bags" >&2
    exit 1
fi

if scan_has_matches 'ExtensionManager|BrowserManager|\bOwner\b' \
    "$service" "$record" "$policy" "$settlement" "$identity" "$admission"; then
    echo "focused installation roles must remain manager-root and Owner-free" >&2
    exit 1
fi

if scan_has_matches 'installDirectoryExtension|installSafariAppExtension|rollbackPersistedRecord' \
    "$service"; then
    echo "duplicated package-specific installation transactions must not return" >&2
    exit 1
fi

service_lines="$(wc -l < "$service" | tr -d ' ')"
if (( service_lines > 430 )); then
    echo "ExtensionInstallationService grew beyond the 430-line transaction ratchet" >&2
    exit 1
fi

claim_line="$(capture_matches 'sourceAdmission\.begin' "$service" | head -1 | cut -d: -f1)"
async_install_line="$(capture_matches '^    \) async throws -> InstalledExtension' "$service" | head -1 | cut -d: -f1)"
pre_claim_await_hits=""
if [[ -n "$claim_line" && -n "$async_install_line" ]]; then
    pre_claim_await_hits="$(
        sed -n "${async_install_line},${claim_line}p" "$service" \
            | guard_capture_matches '\bawait\b' -
    )"
fi
if [[ -z "$claim_line" || -z "$async_install_line" ]] \
    || [[ -n "$pre_claim_await_hits" ]]; then
    echo "source identity must be claimed before the first runtime await" >&2
    exit 1
fi

require_matches '^actor ExtensionPackageInstallTransaction' "$package"
require_matches 'func rollback\(\) async throws' "$package"
require_matches '^    func commit\(\) async \{$' "$package"
if scan_has_matches 'func commit\(\) async throws' "$package" "$prepared_package"; then
    echo "durable package commit must remain nonthrowing" >&2
    exit 1
fi
if scan_has_matches '@MainActor' "$package"; then
    echo "package filesystem transaction must not run on MainActor" >&2
    exit 1
fi
if scan_has_matches 'Task\.detached' "$package"; then
    echo "blocking package I/O must not occupy Swift's cooperative executor" >&2
    exit 1
fi
require_matches 'DispatchQueue\(label: label, qos: \.utility\)' "$package"
require_matches 'withCheckedThrowingContinuation' "$package"
for operation in prepareStaging copyStagedPackage prepareMaterialization \
    materializePackage inspectMaterializedPackage deleteRollbackArtifacts; do
    require_matches "\\.${operation}" "$package"
done
require_matches 'scanAndMoveStagedPackage' "$package"
require_matches 'rejectSymbolicLinks\(in: destination\)' "$package"
require_matches 'validateCopiedManifest' "$package"
if scan_has_matches 'fingerprint\(fileAt:' "$package" "$prepared_package"; then
    echo "transactional manifest fingerprints must come from throwing Data reads" >&2
    exit 1
fi
final_scan_line="$(capture_matches 'rejectSymbolicLinks\(in: stagedPackageRoot\)' "$package" | tail -1 | cut -d: -f1)"
move_line="$(capture_matches 'try FileManager\.default\.moveItem' "$package" | head -1 | cut -d: -f1)"
critical_section_await_hits=""
if [[ -n "$final_scan_line" && -n "$move_line" ]]; then
    critical_section_await_hits="$(
        sed -n "${final_scan_line},${move_line}p" "$package" \
            | guard_capture_matches '\bawait\b' -
    )"
fi
if [[ -z "$final_scan_line" || -z "$move_line" ]] \
    || (( final_scan_line >= move_line )) \
    || [[ -n "$critical_section_await_hits" ]]; then
    echo "final package scan and materializing move must share one non-suspending critical operation" >&2
    exit 1
fi
require_matches 'manifestRootFingerprint: materialized\.manifestFingerprint' "$service"
require_matches 'fileExecutor: packageFileExecutor' "$service"
claiming_staging_line="$(capture_matches 'phase = \.claimingStaging' "$package" | head -1 | cut -d: -f1)"
begin_staging_line="$(capture_matches 'activeGenerations\.begin\(stagedPackageRoot\)' "$package" | head -1 | cut -d: -f1)"
claiming_generation_line="$(capture_matches 'phase = \.claimingGeneration' "$package" | head -1 | cut -d: -f1)"
begin_generation_line="$(capture_matches 'activeGenerations\.begin\(destination\)' "$package" | head -1 | cut -d: -f1)"
if [[ -z "$claiming_staging_line" || -z "$begin_staging_line" \
   || -z "$claiming_generation_line" || -z "$begin_generation_line" ]] \
    || (( claiming_staging_line >= begin_staging_line )) \
    || (( claiming_generation_line >= begin_generation_line )); then
    echo "transaction phase must become non-reentrant before generation registry hops" >&2
    exit 1
fi
require_matches 'UUID\(\)\.uuidString' "$layout"
require_matches 'ExtensionPackageLayout' "$package"
require_matches 'activePackageGenerations' "$service"
require_matches 'quarantineOrphans' "$maintenance"
require_matches 'case volatileCandidatePublished' "$record"
require_matches 'case volatileExactRuntime' "$root/Sumi/Managers/ExtensionManager/InstalledExtensionCollection.swift"
require_matches 'try persistence\.persist' "$record"
require_matches 'installedRecords\.upsert' "$record"
require_matches 'changed its declared extension identity' "$identity"
require_matches 'ExtensionInstallationFailurePolicy\.resolve' "$settlement"
require_matches 'failureSettlement\.settle' "$service"
echo "extension installation transaction boundary passed"
