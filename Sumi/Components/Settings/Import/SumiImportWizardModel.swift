import Foundation
import Observation

/// The work the wizard needs from the rest of the app. Settings UI is barred
/// from reaching into the browser's runtime object graph, so every capability
/// arrives here as a closure the composition root supplies.
struct SumiImportWizardActions {
    var detectSources: () async -> [SumiDetectedBrowser]
    var preparePreview: (SumiImportSourceSelection) async throws -> SumiImportPreview
    var applyImport: (SumiImportRequest) async throws -> SumiImportReport
}

@MainActor
@Observable
final class SumiImportWizardModel {
    enum Step: Equatable {
        case source
        case profile
        case categories
        case applying
        case finished(String)
    }

    private(set) var step: Step = .source
    private(set) var browsers: [SumiDetectedBrowser] = []
    private(set) var isDetecting = false
    private(set) var isPreparingPreview = false
    private(set) var preview: SumiImportPreview?
    private(set) var errorMessage: String?
    var explainerBrowser: SumiDetectedBrowser?

    var selectedBrowser: SumiDetectedBrowser?
    var selectedProfile: SumiDetectedBrowserProfile?
    var selectedCategories: Set<SumiImportCategory> = []
    var selectedBulkKinds: Set<SumiImportBulkKind> = []

    private let actions: SumiImportWizardActions
    private let staging = SumiImportBulkStagingStore()
    private var work: Task<Void, Never>?

    init(actions: SumiImportWizardActions) {
        self.actions = actions
    }

    var canImport: Bool {
        guard step == .categories, preview != nil else { return false }
        guard requiresProfiles == false
            || selectedCategories.contains(.profiles)
        else {
            return false
        }
        return selectedCategories.isEmpty == false || selectedBulkKinds.isEmpty == false
    }

    var requiresProfilesForBrowsingData: Bool {
        guard selectedBulkKinds.isEmpty == false, let preview else { return false }
        return Set(preview.data.profiles.compactMap(\.sourceDirectoryKey)).count > 1
    }

    var requiresProfiles: Bool {
        requiresProfilesForBrowsingData
            || selectedCategories.contains(.spaces)
            || selectedCategories.contains(.essentials)
    }

    func detect() {
        work?.cancel()
        isDetecting = true
        errorMessage = nil
        work = Task { @MainActor in
            let found = await actions.detectSources()
            guard Task.isCancelled == false else { return }
            browsers = found
            isDetecting = false
        }
    }

    /// Choosing a browser skips straight past the profile step when there is
    /// only one profile to choose — the step would be a list of one.
    func select(_ browser: SumiDetectedBrowser) {
        guard browser.isImportable else {
            explainerBrowser = browser
            return
        }
        selectedBrowser = browser
        errorMessage = nil
        if browser.profiles.count == 1, let only = browser.profiles.first {
            select(only)
        } else {
            step = .profile
        }
    }

    func select(_ profile: SumiDetectedBrowserProfile) {
        guard let browser = selectedBrowser else { return }
        selectedProfile = profile
        loadPreview(SumiImportSourceSelection(browser: browser, profile: profile))
    }

    func back() {
        switch step {
        case .source:
            return
        case .profile:
            selectedBrowser = nil
            step = .source
        case .categories:
            discardPreview()
            preview = nil
            selectedProfile = nil
            step = (selectedBrowser?.profiles.count ?? 0) > 1 ? .profile : .source
            if step == .source { selectedBrowser = nil }
        case .applying, .finished:
            return
        }
    }

    func apply() {
        guard let preview else { return }
        work?.cancel()
        step = .applying
        errorMessage = nil
        work = Task { @MainActor in
            do {
                let report = try await actions.applyImport(
                    SumiImportRequest(
                        sourceKind: preview.sourceKind,
                        data: preview.data,
                        categories: selectedCategories,
                        mode: .merge,
                        bulkStaging: preview.bulkStaging,
                        bulkKinds: selectedBulkKinds
                    )
                )
                guard Task.isCancelled == false else { return }
                discardPreview()
                var messages = report.warnings
                if let backup = report.preRestoreBackupURL {
                    messages.append("Pre-import backup: \(backup.lastPathComponent)")
                }
                step = .finished(messages.isEmpty ? "Import complete." : messages.joined(separator: "\n"))
            } catch {
                guard Task.isCancelled == false else { return }
                errorMessage = error.localizedDescription
                step = .categories
            }
        }
    }

    func cancelWork() {
        work?.cancel()
        work = nil
        if step != .applying {
            discardPreview()
            preview = nil
        }
    }

    func setBulkKind(_ kind: SumiImportBulkKind, enabled: Bool) {
        if enabled {
            selectedBulkKinds.insert(kind)
            if requiresProfilesForBrowsingData {
                selectedCategories.insert(.profiles)
            }
        } else {
            selectedBulkKinds.remove(kind)
        }
    }

    func setCategory(_ category: SumiImportCategory, enabled: Bool) {
        if enabled {
            selectedCategories.insert(category)
            if requiresProfiles {
                selectedCategories.insert(.profiles)
            }
        } else if category != .profiles || requiresProfiles == false {
            selectedCategories.remove(category)
        }
    }

    private func loadPreview(_ selection: SumiImportSourceSelection) {
        work?.cancel()
        discardPreview()
        preview = nil
        isPreparingPreview = true
        errorMessage = nil
        step = .categories
        work = Task { @MainActor in
            defer { isPreparingPreview = false }
            do {
                let loaded = try await actions.preparePreview(selection)
                guard Task.isCancelled == false else {
                    if let stagingID = loaded.bulkStaging?.stagingID {
                        staging.discard(stagingID)
                    }
                    return
                }
                preview = loaded
                selectedCategories = loaded.suggestedCategories
                selectedBulkKinds = loaded.bulkStaging?.kinds ?? []
                if requiresProfiles {
                    selectedCategories.insert(.profiles)
                }
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                errorMessage = error.localizedDescription
                preview = nil
            }
        }
    }

    private func discardPreview() {
        guard let stagingID = preview?.bulkStaging?.stagingID else { return }
        staging.discard(stagingID)
    }
}

extension SumiBrowserAccessIssue {
    var explanation: String {
        switch self {
        case .fullDiskAccessRequired:
            return "Sumi needs Full Disk Access to read this browser's data."
        case let .sourceBrowserRunning(name):
            return "\(name) is running. Anything it has not written to disk yet will not be imported."
        case .noProfilesFound:
            return "No profiles with importable data were found."
        case let .unreadable(detail):
            return detail
        }
    }

    var isBlocking: Bool {
        if case .sourceBrowserRunning = self { return false }
        return true
    }
}
