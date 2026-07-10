import Foundation

@MainActor
final class SumiImportTransaction {
    private let materializer: any SumiImportRuntimeMaterializing
    private let runtime: any SumiImportRuntimeMutating
    private let bookmarks: any SumiImportBookmarkMutating
    private let backupWriter: any SumiImportBackupWriting

    init(
        materializer: any SumiImportRuntimeMaterializing,
        runtime: any SumiImportRuntimeMutating,
        bookmarks: any SumiImportBookmarkMutating,
        backupWriter: any SumiImportBackupWriting
    ) {
        self.materializer = materializer
        self.runtime = runtime
        self.bookmarks = bookmarks
        self.backupWriter = backupWriter
    }

    func commit(_ plan: SumiImportPlan) async throws -> SumiImportReport {
        guard plan.hasMutations else {
            return SumiImportReport(
                warnings: plan.warnings,
                preRestoreBackupURL: nil,
                appliedCategories: [],
                bookmarkSummary: nil
            )
        }

        let checkpoint = plan.changesRuntime ? runtime.checkpoint() : nil
        let importedState = try checkpoint.map {
            try materializer.materialize(plan, preserving: $0)
        }
        let preRestoreBackupURL = plan.mode == .replace
            ? try backupWriter.writeAutomaticPreRestoreBackup(data: plan.baseline)
            : nil
        var bookmarkCheckpoint: SumiBookmarksSnapshot?

        do {
            if let importedState {
                try await runtime.install(importedState)
            }
            if plan.bookmarkMutation.changesBookmarks {
                bookmarkCheckpoint = bookmarks.checkpoint()
            }
            let bookmarkSummary = bookmarkCheckpoint != nil
                ? try bookmarks.commit(plan.bookmarkMutation)
                : nil
            return SumiImportReport(
                warnings: reportWarnings(plan.warnings, bookmarkSummary: bookmarkSummary),
                preRestoreBackupURL: preRestoreBackupURL,
                appliedCategories: plan.categories,
                bookmarkSummary: bookmarkSummary
            )
        } catch let importError {
            var rollbackError: Error?
            if let bookmarkCheckpoint {
                do {
                    try bookmarks.restore(bookmarkCheckpoint)
                } catch {
                    rollbackError = error
                }
            }
            if let checkpoint {
                do {
                    try await runtime.restore(checkpoint)
                } catch {
                    rollbackError = rollbackError ?? error
                }
            }
            if let rollbackError {
                throw SumiImportTransactionError.rollbackFailed(
                    importError: importError,
                    rollbackError: rollbackError
                )
            }
            throw importError
        }
    }

    private func reportWarnings(
        _ planningWarnings: [String],
        bookmarkSummary: SumiBookmarksImportSummary?
    ) -> [String] {
        guard let bookmarkSummary else { return planningWarnings }
        var warnings = planningWarnings
        if bookmarkSummary.duplicates > 0 {
            warnings.append("Skipped \(bookmarkSummary.duplicates) duplicate bookmarks.")
        }
        if bookmarkSummary.failed > 0 {
            warnings.append("Skipped \(bookmarkSummary.failed) invalid bookmarks.")
        }
        return warnings
    }
}
