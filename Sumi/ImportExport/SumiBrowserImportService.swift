import Foundation

@MainActor
final class SumiBrowserImportService {
    private let filePreviewReader: SumiImportFilePreviewReader
    private let zenProfilesRootProvider: @MainActor () -> URL

    init(
        transferService: SumiTransferExportService = SumiTransferExportService(),
        backupService: SumiBackupService = SumiBackupService(),
        zenProfilesRootProvider: @escaping @MainActor () -> URL = {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/zen/Profiles", isDirectory: true)
        }
    ) {
        filePreviewReader = SumiImportFilePreviewReader(
            transferService: transferService,
            backupService: backupService
        )
        self.zenProfilesRootProvider = zenProfilesRootProvider
    }

    func previewArcImport() throws -> SumiImportPreview {
        let sidebarURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
        let result = try SumiArcImportParser().parseWithDiagnostics(sidebarURL: sidebarURL)
        return SumiImportPreview(
            title: "Arc",
            sourceKind: .arc,
            data: result.data,
            suggestedCategories: result.data.nonEmptyCategories,
            warnings: SumiImportPreviewWarningBuilder.warnings(for: result.data, source: "Arc") + result.warnings,
            defaultMode: .merge
        )
    }

    func detectedZenProfiles() -> [URL] {
        let root = zenProfilesRootProvider()
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain,
               cocoaError.code == CocoaError.fileReadNoSuchFile.rawValue {
                return []
            }
            RuntimeDiagnostics.emit(
                "[ImportExport] Failed to enumerate Zen profiles at \(root.path): \(error.localizedDescription)"
            )
            return []
        }
        return children.compactMap { url in
            do {
                guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                      FileManager.default.fileExists(atPath: url.appendingPathComponent("places.sqlite").path)
                else {
                    return nil
                }
                return url
            } catch {
                RuntimeDiagnostics.emit(
                    "[ImportExport] Skipping Zen profile candidate at \(url.path): \(error.localizedDescription)"
                )
                return nil
            }
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func previewZenImport(profileURL: URL) throws -> SumiImportPreview {
        let result = try SumiZenImportParser().parseWithDiagnostics(profileURL: profileURL)
        return SumiImportPreview(
            title: "Zen: \(profileURL.lastPathComponent)",
            sourceKind: .zen,
            data: result.data,
            suggestedCategories: result.data.nonEmptyCategories,
            warnings: SumiImportPreviewWarningBuilder.warnings(for: result.data, source: "Zen") + result.warnings,
            defaultMode: .merge
        )
    }

    func previewFileImport(fileURL: URL) throws -> SumiImportPreview {
        try filePreviewReader.preview(fileURL: fileURL)
    }
}
