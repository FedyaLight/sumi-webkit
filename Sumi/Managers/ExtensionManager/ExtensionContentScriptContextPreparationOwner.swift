import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionContentScriptContextPreparationOwner {
    typealias ContextQuery = @MainActor (String, UUID) -> WKWebExtensionContext?
    typealias ContextLoad = @MainActor (String, UUID) async throws -> Void
    typealias FailureLog = @MainActor (Error, String, UUID, String) -> Void

    private let installedExtensions: InstalledExtensionCollection
    private let runtimeIsEnabled: @MainActor () -> Bool
    private let context: ContextQuery
    private let load: ContextLoad
    private let logFailure: FailureLog
    private let runtimeTasks =
        ExtensionProfileRuntimeTaskOwner<PageNavigationPrerequisiteResult>()

    init(
        installedExtensions: InstalledExtensionCollection,
        runtimeIsEnabled: @escaping @MainActor () -> Bool,
        context: @escaping ContextQuery,
        load: @escaping ContextLoad,
        logFailure: @escaping FailureLog
    ) {
        self.installedExtensions = installedExtensions
        self.runtimeIsEnabled = runtimeIsEnabled
        self.context = context
        self.load = load
        self.logFailure = logFailure
    }

    func profileHasLoadedContexts(profileID: UUID) -> Bool {
        guard runtimeIsEnabled() else { return true }
        let records = contentScriptExtensions()
        guard records.isEmpty == false else { return true }
        return records.allSatisfy {
            context($0.id, profileID)?.isLoaded == true
        }
    }

    func participatesInInitialDocumentRuntime() -> Bool {
        runtimeIsEnabled() && contentScriptExtensions().isEmpty == false
    }

    func profileHasLoadedExtensionContext(profileID: UUID) -> Bool {
        // A normal tab only needs the content-script contexts that can
        // actually inject into its document. Popup/options-only extensions do
        // not make browser tab publication wait for an unrelated background
        // context.
        profileHasLoadedContexts(profileID: profileID)
    }

    func profileNeedsLoad(profileID: UUID) -> Bool {
        profileHasLoadedContexts(profileID: profileID) == false
    }

    func ensureLoaded(profileID: UUID) async
        -> PageNavigationPrerequisiteResult {
        guard runtimeIsEnabled(), profileNeedsLoad(profileID: profileID) else {
            return .ready
        }
        return await runtimeTasks.run(profileID: profileID) {
            [weak self] in
            guard let self else { return .cancelled }
            let records = self.contentScriptExtensions()
            var loadedCount = 0
            var failedCount = 0
            for record in records {
                guard Task.isCancelled == false else { return .cancelled }
                do {
                    try await self.load(record.id, profileID)
                    loadedCount += 1
                } catch {
                    failedCount += 1
                    self.logFailure(
                        error,
                        record.id,
                        profileID,
                        "preload content-script context"
                    )
                }
            }
            if failedCount == 0 { return .ready }
            return loadedCount == 0 ? .failed : .degraded
        }
    }

    func cancelAll() {
        runtimeTasks.cancelAll()
    }

    #if DEBUG
        func runtimeTasksForDrain() -> [Task<Void, Never>] {
            runtimeTasks.tasksForDrain()
        }
    #endif

    private func contentScriptExtensions() -> [InstalledExtension] {
        installedExtensions.enabledContentScriptRecords
    }
}
