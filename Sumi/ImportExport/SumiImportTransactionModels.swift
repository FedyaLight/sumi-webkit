import Foundation

struct SumiImportRequest: Sendable {
    let sourceKind: SumiImportSourceKind
    let data: SumiPortableData
    let categories: Set<SumiImportCategory>
    let mode: SumiImportApplyMode
}

struct SumiImportReport: Sendable {
    let warnings: [String]
    let preRestoreBackupURL: URL?
    let appliedCategories: Set<SumiImportCategory>
    let bookmarkSummary: SumiBookmarksImportSummary?
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

enum SumiImportTransactionError: LocalizedError {
    case runtimePersistenceFailed
    case rollbackFailed(importError: Error, rollbackError: Error)

    var errorDescription: String? {
        switch self {
        case .runtimePersistenceFailed:
            return "Sumi could not persist the imported browser data."
        case .rollbackFailed(let importError, let rollbackError):
            return "Import failed (\(importError.localizedDescription)) and Sumi could not restore the previous browser state (\(rollbackError.localizedDescription))."
        }
    }
}
