import Foundation

@MainActor
final class SumiBrowserImportService {
    private let zenProfilesRootProvider: @MainActor () -> URL

    init(
        zenProfilesRootProvider: @escaping @MainActor () -> URL = {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/zen/Profiles", isDirectory: true)
        }
    ) {
        self.zenProfilesRootProvider = zenProfilesRootProvider
    }

    func previewArcImport() async throws -> SumiImportPreview {
        let sidebarURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
        return try await SumiBrowserImportPreviewWorker.previewArc(sidebarURL: sidebarURL)
    }

    func detectedZenProfiles() async -> [URL] {
        let root = zenProfilesRootProvider()
        return await SumiBrowserImportPreviewWorker.detectedZenProfiles(root: root)
    }

    func previewZenImport(profileURL: URL) async throws -> SumiImportPreview {
        try await SumiBrowserImportPreviewWorker.previewZen(profileURL: profileURL)
    }

    func previewFileImport(fileURL: URL) async throws -> SumiImportPreview {
        try await SumiBrowserImportPreviewWorker.previewFile(fileURL: fileURL)
    }
}

enum SumiBrowserImportPreviewWorker {
    static func previewArc(sidebarURL: URL) async throws -> SumiImportPreview {
        try await detached {
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
    }

    static func detectedZenProfiles(root: URL) async -> [URL] {
        (try? await detached {
            try enumerateZenProfiles(root: root)
        }) ?? []
    }

    static func previewZen(profileURL: URL) async throws -> SumiImportPreview {
        try await detached {
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
    }

    static func previewFile(fileURL: URL) async throws -> SumiImportPreview {
        try await detached {
            try SumiImportFilePreviewReader().preview(fileURL: fileURL)
        }
    }

    private static func enumerateZenProfiles(root: URL) throws -> [URL] {
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
            throw error
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
                return nil
            }
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func detached<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let interval = PerformanceTrace.beginInterval("Import.preview")
        defer { PerformanceTrace.endInterval("Import.preview", interval) }
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try operation()
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
