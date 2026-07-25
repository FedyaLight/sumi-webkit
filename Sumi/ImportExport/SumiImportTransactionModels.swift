import Foundation

struct SumiImportRequest: Sendable {
    let sourceKind: SumiImportSourceKind
    let data: SumiPortableData
    let categories: Set<SumiImportCategory>
    let mode: SumiImportApplyMode
    /// Bulk payloads staged during preview, and which of them the user chose.
    /// Kept separate from `categories` so the logical backup format's declared
    /// scope stays exactly what it was.
    var bulkStaging: SumiImportBulkStagingManifest? = nil
    var bulkKinds: Set<SumiImportBulkKind> = []
}

struct SumiImportReport: Sendable {
    let warnings: [String]
    let preRestoreBackupURL: URL?
    let appliedCategories: Set<SumiImportCategory>
    let bookmarkSummary: SumiBookmarksImportSummary?
}

struct SumiImportRecoveryReport: Sendable {
    let preRestoreBackupURL: URL?
}

enum SumiImportBookmarkMutation: Equatable, Sendable {
    case none
    case merge([SumiPortableBookmarkNode])
    case replace([SumiPortableBookmarkNode])

    var changesBookmarks: Bool {
        switch self {
        case .none:
            return false
        case .merge(let nodes):
            return !nodes.isEmpty
        case .replace:
            return true
        }
    }
}

struct SumiImportPlan: Equatable, Sendable {
    let baseline: SumiPortableData
    let targetRuntimeData: SumiPortableData
    let bookmarkMutation: SumiImportBookmarkMutation
    let categories: Set<SumiImportCategory>
    let mode: SumiImportApplyMode
    let warnings: [String]
    let profileTransition: SumiImportProfileTransition

    init(
        baseline: SumiPortableData,
        targetRuntimeData: SumiPortableData,
        bookmarkMutation: SumiImportBookmarkMutation,
        categories: Set<SumiImportCategory>,
        mode: SumiImportApplyMode,
        warnings: [String],
        profileTransition: SumiImportProfileTransition = .none
    ) {
        self.baseline = baseline
        self.targetRuntimeData = targetRuntimeData
        self.bookmarkMutation = bookmarkMutation
        self.categories = categories
        self.mode = mode
        self.warnings = warnings
        self.profileTransition = profileTransition
    }

    var changesRuntime: Bool {
        targetRuntimeData.profiles != baseline.profiles
            || targetRuntimeData.spaces != baseline.spaces
            || targetRuntimeData.folders != baseline.folders
            || targetRuntimeData.essentials != baseline.essentials
            || targetRuntimeData.pinnedLaunchers != baseline.pinnedLaunchers
            || targetRuntimeData.regularTabs != baseline.regularTabs
    }

    var hasMutations: Bool {
        changesRuntime || bookmarkMutation.changesBookmarks
    }
}

struct SumiImportProfileTransition: Codable, Equatable, Sendable {
    let sourceToTargetProfileID: [String: String]
    let createdProfileIDs: Set<UUID>
    let retiringProfileIDs: Set<UUID>
    let fallbackProfileID: UUID?

    static let none = SumiImportProfileTransition(
        sourceToTargetProfileID: [:],
        createdProfileIDs: [],
        retiringProfileIDs: [],
        fallbackProfileID: nil
    )
}

enum SumiImportTransactionError: LocalizedError {
    case runtimePersistenceFailed
    case commitFailed(
        importError: Error,
        rollbackErrors: [Error],
        preRestoreBackupURL: URL?
    )
    case recoveryFailed(
        rollbackErrors: [Error],
        preRestoreBackupURL: URL?
    )
    case commitFinalizationFailed(
        finalizationError: Error,
        preRestoreBackupURL: URL?
    )
    case profileRetirementPending(
        retirementError: Error,
        preRestoreBackupURL: URL?
    )

    var rollbackErrors: [Error] {
        switch self {
        case .runtimePersistenceFailed:
            []
        case .commitFailed(_, let rollbackErrors, _),
             .recoveryFailed(let rollbackErrors, _):
            rollbackErrors
        case .commitFinalizationFailed:
            []
        case .profileRetirementPending:
            []
        }
    }

    var preRestoreBackupURL: URL? {
        switch self {
        case .runtimePersistenceFailed:
            nil
        case .commitFailed(_, _, let backupURL),
             .recoveryFailed(_, let backupURL),
             .commitFinalizationFailed(_, let backupURL):
            backupURL
        case .profileRetirementPending(_, let backupURL):
            backupURL
        }
    }

    var errorDescription: String? {
        switch self {
        case .runtimePersistenceFailed:
            return "Sumi could not persist the imported browser data."
        case .commitFailed(let importError, let rollbackErrors, let backupURL):
            let rollbackDescription = rollbackErrors.isEmpty
                ? "The previous browser state was restored."
                : "Rollback reported \(rollbackErrors.count) error(s): \(Self.errorList(rollbackErrors))."
            return "Import failed: \(importError.localizedDescription) \(rollbackDescription)\(Self.backupDescription(backupURL))"
        case .recoveryFailed(let rollbackErrors, let backupURL):
            return "Sumi could not recover an interrupted import. \(Self.errorList(rollbackErrors))\(Self.backupDescription(backupURL))"
        case .commitFinalizationFailed(let finalizationError, let backupURL):
            return "Import effects were applied, but durable transaction finalization could not be confirmed: \(finalizationError.localizedDescription) Sumi will resolve the journal on next launch.\(Self.backupDescription(backupURL))"
        case .profileRetirementPending(let retirementError, let backupURL):
            return "Imported data was applied, but profile cleanup is still pending: \(retirementError.localizedDescription) Sumi will resume it on next launch.\(Self.backupDescription(backupURL))"
        }
    }

    private static func errorList(_ errors: [Error]) -> String {
        errors.map(\.localizedDescription).joined(separator: "; ")
    }

    private static func backupDescription(_ url: URL?) -> String {
        guard let url else { return "" }
        return " Pre-restore backup: \(url.path)"
    }
}
