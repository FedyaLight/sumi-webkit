import Foundation

/// Identifies exactly which browser and profile an import should read.
struct SumiImportSourceSelection: Equatable, Sendable {
    var browser: SumiDetectedBrowser
    var profile: SumiDetectedBrowserProfile
}

@MainActor
final class SumiBrowserImportService {
    private let homeDirectoryProvider: @MainActor () -> URL
    private let applications: any SumiInstalledApplicationLocating

    init(
        homeDirectoryProvider: @escaping @MainActor () -> URL = {
            FileManager.default.homeDirectoryForCurrentUser
        },
        applications: any SumiInstalledApplicationLocating = SumiWorkspaceApplicationLocator()
    ) {
        self.homeDirectoryProvider = homeDirectoryProvider
        self.applications = applications
    }

    /// Every browser Sumi can import from, with per-profile detail and any
    /// access problem that stands in the way.
    func detectSources() async -> [SumiDetectedBrowser] {
        let home = homeDirectoryProvider()
        let applications = self.applications
        return await SumiBrowserImportPreviewWorker.detached {
            SumiBrowserSourceCatalog.detect(homeDirectory: home, applications: applications)
        } ?? []
    }

    func preview(_ selection: SumiImportSourceSelection) async throws -> SumiImportPreview {
        try await SumiBrowserImportPreviewWorker.preview(selection)
    }

    func previewFileImport(fileURL: URL) async throws -> SumiImportPreview {
        try await SumiBrowserImportPreviewWorker.previewFile(fileURL: fileURL)
    }
}

enum SumiBrowserImportPreviewWorker {
    static func preview(_ selection: SumiImportSourceSelection) async throws -> SumiImportPreview {
        let browser = selection.browser
        let profile = selection.profile
        return try await detached {
            var preview: SumiImportPreview
            switch browser.family {
            case .arc:
                preview = try previewArc(browser: browser)
            case .zen:
                preview = try previewZen(browser: browser, profile: profile)
            case .chromium:
                preview = try previewChromium(browser: browser, profile: profile)
            case .firefox:
                preview = try previewFirefox(browser: browser, profile: profile)
            case .safari:
                preview = try previewSafari(browser: browser)
            }

            // Bulk payloads are staged now, while the wizard is open, because
            // reading them can prompt for keychain authorization; the user
            // should meet that while deciding, not mid-import.
            if let staged = SumiImportBulkStagingCoordinator().stage(
                browser: browser,
                profile: profile,
                kinds: SumiImportBulkStagingCoordinator.supportedKinds(for: browser)
            ) {
                preview.bulkStaging = staged.manifest
                preview.warnings.append(contentsOf: staged.warnings)
            }
            return preview
        }
    }

    static func previewFile(fileURL: URL) async throws -> SumiImportPreview {
        try await detached {
            try SumiImportFilePreviewReader().preview(fileURL: fileURL)
        }
    }

    // MARK: - Per-family previews

    private static func previewArc(browser: SumiDetectedBrowser) throws -> SumiImportPreview {
        let parser = SumiArcImportParser(
            userDataURL: browser.dataRoot.appendingPathComponent("User Data", isDirectory: true)
        )
        let result = try parser.parseWithDiagnostics(
            sidebarURL: browser.dataRoot.appendingPathComponent("StorableSidebar.json")
        )
        return preview(title: browser.displayName, kind: .arc, data: result.data, warnings: result.warnings)
    }

    private static func previewZen(
        browser: SumiDetectedBrowser,
        profile: SumiDetectedBrowserProfile
    ) throws -> SumiImportPreview {
        let result = try SumiZenImportParser().parseWithDiagnostics(profileURL: profile.directoryURL)
        return preview(
            title: "\(browser.displayName): \(profile.displayName)",
            kind: .zen,
            data: result.data,
            warnings: result.warnings
        )
    }

    private static func previewChromium(
        browser: SumiDetectedBrowser,
        profile: SumiDetectedBrowserProfile
    ) throws -> SumiImportPreview {
        let result = try SumiChromiumImportParser(
            browserName: browser.displayName,
            userDataURL: browser.dataRoot,
            profileDirectoryName: profile.sourceDirectoryKey
        ).parseWithDiagnostics()
        return preview(
            title: "\(browser.displayName): \(profile.displayName)",
            kind: .chromium,
            data: result.data,
            warnings: result.warnings
        )
    }

    private static func previewFirefox(
        browser: SumiDetectedBrowser,
        profile: SumiDetectedBrowserProfile
    ) throws -> SumiImportPreview {
        let result = try SumiFirefoxImportParser(
            browserName: browser.displayName,
            profileURL: profile.directoryURL,
            directoryName: profile.sourceDirectoryKey
        ).parseWithDiagnostics()
        return preview(
            title: "\(browser.displayName): \(profile.displayName)",
            kind: .firefox,
            data: result.data,
            warnings: result.warnings
        )
    }

    private static func previewSafari(browser: SumiDetectedBrowser) throws -> SumiImportPreview {
        let result = try SumiSafariImportParser(
            browserName: browser.displayName,
            safariDirectoryURL: browser.dataRoot
        ).parseWithDiagnostics()
        return preview(title: browser.displayName, kind: .safari, data: result.data, warnings: result.warnings)
    }

    private static func preview(
        title: String,
        kind: SumiImportSourceKind,
        data: SumiPortableData,
        warnings: [String]
    ) -> SumiImportPreview {
        SumiImportPreview(
            title: title,
            sourceKind: kind,
            data: data,
            suggestedCategories: data.nonEmptyCategories,
            warnings: SumiImportPreviewWarningBuilder.warnings(for: data, source: title) + warnings,
            defaultMode: .merge
        )
    }

    // MARK: - Execution

    static func detached<T: Sendable>(
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

    static func detached<T: Sendable>(
        _ operation: @escaping @Sendable () -> T
    ) async -> T? {
        try? await detached { () throws -> T in operation() }
    }
}
