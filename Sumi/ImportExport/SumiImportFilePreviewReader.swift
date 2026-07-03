import Foundation

@MainActor
struct SumiImportFilePreviewReader {
    private let transferService: SumiTransferExportService
    private let backupService: SumiBackupService

    init(
        transferService: SumiTransferExportService = SumiTransferExportService(),
        backupService: SumiBackupService = SumiBackupService()
    ) {
        self.transferService = transferService
        self.backupService = backupService
    }

    func preview(fileURL: URL) throws -> SumiImportPreview {
        let raw = try Data(contentsOf: fileURL)
        if isSumiBackupCandidate(fileURL: fileURL, data: raw) {
            let archive = try backupService.readBackup(from: raw)
            return SumiImportPreview(
                title: fileURL.lastPathComponent,
                sourceKind: .sumiBackup,
                data: archive.data,
                suggestedCategories: Set(archive.includedCategories),
                warnings: archive.warnings,
                defaultMode: .replace
            )
        }

        let data = try transferService.importBrowser2ZenDocument(from: raw)
        return SumiImportPreview(
            title: fileURL.lastPathComponent,
            sourceKind: .browser2zen,
            data: data,
            suggestedCategories: data.nonEmptyCategories,
            warnings: SumiImportPreviewWarningBuilder.warnings(for: data, source: "Browser Export"),
            defaultMode: .merge
        )
    }

    private func isSumiBackupCandidate(fileURL: URL, data: Data) -> Bool {
        if fileURL.pathExtension.caseInsensitiveCompare("sumibackup") == .orderedSame {
            return true
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return false
        }
        guard let dictionary = object as? [String: Any],
              let format = dictionary["format"] as? String
        else {
            return false
        }
        return format == SumiPortableArchive.format
    }
}
