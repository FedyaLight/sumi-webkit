import Foundation

#if DEBUG
import Darwin

struct SumiProtectionStartupRestoreDiagnosticsSnapshot: Equatable, Sendable {
    let appliedProtectionLevel: String
    let activeGenerationId: String?
    let remoteReleaseVersion: String?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let expectedShardIdentifiers: [String]
    let wkContentRuleListStoreLookupAttempted: Bool
    let lookupHitCount: Int
    let lookupMissCount: Int
    let lookupFailedIdentifiers: [String]
    let metadataOnlyRestoreUsed: Bool
    let payloadBackedRestoreUsed: Bool
    let repairCompileUsed: Bool
    let totalShardJSONBytesRead: Int
    let shardJSONFileReadCount: Int
    let fallbackReason: String?
    let generationConsideredStale: Bool?
    let generationStaleReason: String?
    let compiledRuleListsRemovedOrInvalidated: Bool
    let removedOrInvalidatedCompiledRuleListIdentifiers: [String]
    let compiledRuleListInvalidationReasons: [String]

    var reportLines: [String] {
        [
            "appliedProtectionLevel=\(appliedProtectionLevel)",
            "activeGenerationId=\(activeGenerationId ?? "nil")",
            "remoteReleaseVersion=\(remoteReleaseVersion ?? "nil")",
            "nativeRuleBundleId=\(nativeRuleBundleId ?? "nil")",
            "bundleProfileId=\(bundleProfileId ?? "nil")",
            "expectedShardIdentifiers=\(expectedShardIdentifiers.joined(separator: ","))",
            "wkContentRuleListStoreLookupAttempted=\(wkContentRuleListStoreLookupAttempted)",
            "lookupHitCount=\(lookupHitCount)",
            "lookupMissCount=\(lookupMissCount)",
            "lookupFailedIdentifiers=\(lookupFailedIdentifiers.joined(separator: ","))",
            "metadataOnlyRestoreUsed=\(metadataOnlyRestoreUsed)",
            "payloadBackedRestoreUsed=\(payloadBackedRestoreUsed)",
            "repairCompileUsed=\(repairCompileUsed)",
            "totalShardJSONBytesRead=\(totalShardJSONBytesRead)",
            "shardJSONFileReadCount=\(shardJSONFileReadCount)",
            "fallbackReason=\(fallbackReason ?? "nil")",
            "generationConsideredStale=\(generationConsideredStale.map(String.init) ?? "nil")",
            "generationStaleReason=\(generationStaleReason ?? "nil")",
            "compiledRuleListsRemovedOrInvalidated=\(compiledRuleListsRemovedOrInvalidated)",
            "removedOrInvalidatedCompiledRuleListIdentifiers=\(removedOrInvalidatedCompiledRuleListIdentifiers.joined(separator: ","))",
            "compiledRuleListInvalidationReasons=\(compiledRuleListInvalidationReasons.joined(separator: " | "))",
        ]
    }

    var developerReport: String {
        (["Sumi Protection startup restore diagnostics"] + reportLines).joined(separator: "\n")
    }
}

final class SumiProtectionStartupRestoreDiagnostics: @unchecked Sendable {
    static let shared = SumiProtectionStartupRestoreDiagnostics()

    private struct MutableState {
        var appliedProtectionLevel = "unknown"
        var trackedGenerationId: String?
        var activeGenerationId: String?
        var remoteReleaseVersion: String?
        var nativeRuleBundleId: String?
        var bundleProfileId: String?
        var expectedShardIdentifiers = Set<String>()
        var wkContentRuleListStoreLookupAttempted = false
        var lookupHitIdentifiers = [String]()
        var lookupMissIdentifiers = [String]()
        var metadataOnlyRestoreUsed = false
        var payloadBackedRestoreUsed = false
        var repairCompileUsed = false
        var totalShardJSONBytesRead = 0
        var shardJSONFileReadCount = 0
        var fallbackReason: String?
        var generationConsideredStale: Bool?
        var generationStaleReason: String?
        var removedOrInvalidatedCompiledRuleListIdentifiers = Set<String>()
        var compiledRuleListInvalidationReasons = [String]()
    }

    private let lock = NSLock()
    private var activeToken: UUID?
    private var state = MutableState()
    private var lastSnapshotStorage: SumiProtectionStartupRestoreDiagnosticsSnapshot?

    private init() {}

    var latestSnapshot: SumiProtectionStartupRestoreDiagnosticsSnapshot? {
        lock.withLock { lastSnapshotStorage }
    }

    @discardableResult
    func begin(
        appliedLevel: SumiProtectionLevel,
        trackedGenerationId: String? = nil
    ) -> UUID {
        lock.withLock {
            let token = UUID()
            activeToken = token
            state = MutableState(
                appliedProtectionLevel: appliedLevel.rawValue,
                trackedGenerationId: trackedGenerationId
            )
            return token
        }
    }

    @discardableResult
    func finish(_ token: UUID) -> SumiProtectionStartupRestoreDiagnosticsSnapshot {
        lock.withLock {
            let snapshot = makeSnapshot()
            if activeToken == token {
                activeToken = nil
                lastSnapshotStorage = snapshot
            }
            return snapshot
        }
    }

    func resetForTests() {
        lock.withLock {
            activeToken = nil
            state = MutableState()
            lastSnapshotStorage = nil
        }
    }

    func recordManifest(_ manifest: AdblockCompiledGenerationManifest?) {
        guard let manifest else { return }
        mutateActiveState {
            guard shouldRecord(generationId: manifest.activeGenerationId, in: $0) else { return }
            $0.activeGenerationId = manifest.activeGenerationId
            $0.remoteReleaseVersion = manifest.remoteReleaseVersion
            $0.nativeRuleBundleId = manifest.nativeRuleBundleId
            $0.bundleProfileId = manifest.bundleProfileId
            $0.expectedShardIdentifiers.formUnion(manifest.webKitRuleListIdentifiers)
        }
    }

    func recordExpectedShardIdentifiers(_ identifiers: [String]) {
        mutateActiveState {
            $0.expectedShardIdentifiers.formUnion(filtered(identifiers, in: $0))
        }
    }

    func recordLookupAttempt(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        mutateActiveState {
            let identifiers = filtered(identifiers, in: $0)
            guard !identifiers.isEmpty else { return }
            $0.wkContentRuleListStoreLookupAttempted = true
            $0.expectedShardIdentifiers.formUnion(identifiers)
        }
    }

    func recordLookupHit(_ identifier: String) {
        mutateActiveState {
            guard shouldRecord(identifier: identifier, in: $0) else { return }
            $0.lookupHitIdentifiers.append(identifier)
        }
    }

    func recordLookupMiss(_ identifier: String) {
        mutateActiveState {
            guard shouldRecord(identifier: identifier, in: $0) else { return }
            $0.lookupMissIdentifiers.append(identifier)
        }
    }

    func recordMetadataOnlyRestoreUsed() {
        mutateActiveState {
            $0.metadataOnlyRestoreUsed = true
        }
    }

    func recordPayloadBackedRestoreUsed(reason: String) {
        mutateActiveState {
            guard shouldRecord(reason: reason, in: $0) else { return }
            $0.payloadBackedRestoreUsed = true
            $0.fallbackReason = $0.fallbackReason ?? reason
        }
    }

    func recordRepairCompileUsed(reason: String) {
        mutateActiveState {
            guard shouldRecord(reason: reason, in: $0) else { return }
            $0.repairCompileUsed = true
            $0.fallbackReason = $0.fallbackReason ?? reason
        }
    }

    func recordFallback(reason: String) {
        mutateActiveState {
            guard shouldRecord(reason: reason, in: $0) else { return }
            $0.fallbackReason = $0.fallbackReason ?? reason
        }
    }

    func recordShardJSONRead(identifier: String?, path: String, byteCount: Int, reason: String) {
        mutateActiveState {
            if let identifier {
                guard shouldRecord(identifier: identifier, in: $0) else { return }
            } else {
                guard shouldRecord(reason: reason, in: $0) else { return }
            }
            if let identifier {
                $0.expectedShardIdentifiers.insert(identifier)
            }
            $0.totalShardJSONBytesRead += byteCount
            $0.shardJSONFileReadCount += 1
            if $0.payloadBackedRestoreUsed == false {
                $0.payloadBackedRestoreUsed = true
                $0.fallbackReason = $0.fallbackReason ?? reason
            }
        }
        _ = path
    }

    func recordGenerationStaleCheck(consideredStale: Bool, reason: String) {
        mutateActiveState {
            guard shouldRecord(reason: reason, in: $0) else { return }
            $0.generationConsideredStale = consideredStale
            $0.generationStaleReason = reason
        }
    }

    func recordCompiledRuleListRemoval(identifiers: [String], reason: String) {
        guard !identifiers.isEmpty else { return }
        mutateActiveState {
            let identifiers = filtered(identifiers, in: $0)
            guard !identifiers.isEmpty else { return }
            $0.removedOrInvalidatedCompiledRuleListIdentifiers.formUnion(identifiers)
            $0.compiledRuleListInvalidationReasons.append(reason)
        }
    }

    private func mutateActiveState(_ mutation: (inout MutableState) -> Void) {
        lock.withLock {
            guard activeToken != nil else { return }
            mutation(&state)
        }
    }

    private func makeSnapshot() -> SumiProtectionStartupRestoreDiagnosticsSnapshot {
        SumiProtectionStartupRestoreDiagnosticsSnapshot(
            appliedProtectionLevel: state.appliedProtectionLevel,
            activeGenerationId: state.activeGenerationId,
            remoteReleaseVersion: state.remoteReleaseVersion,
            nativeRuleBundleId: state.nativeRuleBundleId,
            bundleProfileId: state.bundleProfileId,
            expectedShardIdentifiers: Array(state.expectedShardIdentifiers).sorted(),
            wkContentRuleListStoreLookupAttempted: state.wkContentRuleListStoreLookupAttempted,
            lookupHitCount: state.lookupHitIdentifiers.count,
            lookupMissCount: state.lookupMissIdentifiers.count,
            lookupFailedIdentifiers: Array(Set(state.lookupMissIdentifiers)).sorted(),
            metadataOnlyRestoreUsed: state.metadataOnlyRestoreUsed,
            payloadBackedRestoreUsed: state.payloadBackedRestoreUsed,
            repairCompileUsed: state.repairCompileUsed,
            totalShardJSONBytesRead: state.totalShardJSONBytesRead,
            shardJSONFileReadCount: state.shardJSONFileReadCount,
            fallbackReason: state.fallbackReason,
            generationConsideredStale: state.generationConsideredStale,
            generationStaleReason: state.generationStaleReason,
            compiledRuleListsRemovedOrInvalidated: !state.removedOrInvalidatedCompiledRuleListIdentifiers.isEmpty,
            removedOrInvalidatedCompiledRuleListIdentifiers: Array(state.removedOrInvalidatedCompiledRuleListIdentifiers).sorted(),
            compiledRuleListInvalidationReasons: state.compiledRuleListInvalidationReasons
        )
    }

    private func filtered(_ identifiers: [String], in state: MutableState) -> [String] {
        guard let trackedGenerationId = state.trackedGenerationId else { return identifiers }
        return identifiers.filter { $0.contains(trackedGenerationId) }
    }

    private func shouldRecord(identifier: String, in state: MutableState) -> Bool {
        guard let trackedGenerationId = state.trackedGenerationId else { return true }
        return identifier.contains(trackedGenerationId)
    }

    private func shouldRecord(generationId: String, in state: MutableState) -> Bool {
        guard let trackedGenerationId = state.trackedGenerationId else { return true }
        return generationId == trackedGenerationId
    }

    private func shouldRecord(reason: String, in state: MutableState) -> Bool {
        guard let trackedGenerationId = state.trackedGenerationId else { return true }
        return reason.contains(trackedGenerationId)
    }
}

enum AdblockProcessMemorySampler {
    static func residentMemoryBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }
}
#endif
