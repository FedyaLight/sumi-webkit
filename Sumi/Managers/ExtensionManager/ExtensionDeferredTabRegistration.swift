import Foundation

@available(macOS 15.5, *)
@MainActor
protocol ExtensionInitialDocumentContextLoading: AnyObject {
    func ensureInitialExtensionContextsLoaded(for profileId: UUID) async
}

@available(macOS 15.5, *)
extension ExtensionInitialDocumentRuntimePreparationOwner:
    ExtensionInitialDocumentContextLoading {}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionDeferredTabRuntimeResuming: AnyObject {
    func resumeAfterInitialContextsLoaded(_ tab: Tab, reason: String)
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionDeferredTabRegistrationScheduling: AnyObject {
    @discardableResult
    func scheduleDeferredTabNotificationAfterContextLoad(
        _ tab: Tab,
        profileId: UUID,
        extensionLoadRevision: ExtensionLoadRevision,
        reason: String
    ) -> Task<Void, Never>
}

/// Waits for first-document extension contexts without allowing a later Tab
/// with the same UUID to inherit the original physical Tab's registration.
@available(macOS 15.5, *)
@MainActor
final class ExtensionDeferredTabRegistration:
    ExtensionDeferredTabRegistrationScheduling {
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
    }

    private weak var extensionLoadRevisions: ExtensionLoadRevisionAuthority?
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var contextLoading:
        (any ExtensionInitialDocumentContextLoading)?
    private weak var resumer: (any ExtensionDeferredTabRuntimeResuming)?
    private var entriesByTabID: [UUID: Entry] = [:]

    init(
        extensionLoadRevisions: ExtensionLoadRevisionAuthority,
        tabs: any ExtensionTabQuery,
        profiles: any ExtensionTabProfileResolving,
        contextLoading: any ExtensionInitialDocumentContextLoading
    ) {
        self.extensionLoadRevisions = extensionLoadRevisions
        self.tabs = tabs
        self.profiles = profiles
        self.contextLoading = contextLoading
    }

    func bind(resumer: any ExtensionDeferredTabRuntimeResuming) {
        precondition(self.resumer == nil)
        self.resumer = resumer
    }

    @discardableResult
    func scheduleDeferredTabNotificationAfterContextLoad(
        _ tab: Tab,
        profileId: UUID,
        extensionLoadRevision: ExtensionLoadRevision,
        reason: String
    ) -> Task<Void, Never> {
        let tabID = tab.id
        let token = UUID()
        let task = Task { @MainActor [weak self, weak tab] in
            guard let self, let tab else { return }
            defer {
                if self.entriesByTabID[tabID]?.token == token {
                    self.entriesByTabID.removeValue(forKey: tabID)
                }
            }
            guard Task.isCancelled == false,
                  self.extensionLoadRevisions?.isCurrent(
                      extensionLoadRevision
                  ) == true,
                  self.tabs?.extensionTab(for: tabID) === tab,
                  self.profiles?.profileID(for: tab) == profileId
            else { return }

            await self.contextLoading?
                .ensureInitialExtensionContextsLoaded(for: profileId)

            guard Task.isCancelled == false,
                  self.extensionLoadRevisions?.isCurrent(
                      extensionLoadRevision
                  ) == true,
                  self.tabs?.extensionTab(for: tabID) === tab,
                  self.profiles?.profileID(for: tab) == profileId
            else { return }
            self.resumer?.resumeAfterInitialContextsLoaded(
                tab,
                reason: "\(reason).afterContextLoad"
            )
        }
        entriesByTabID[tabID]?.task.cancel()
        entriesByTabID[tabID] = Entry(token: token, task: task)
        return task
    }

    func task(for tabID: UUID) -> Task<Void, Never>? {
        entriesByTabID[tabID]?.task
    }

    func cancelAll() {
        entriesByTabID.values.forEach { $0.task.cancel() }
        entriesByTabID.removeAll()
    }

    #if DEBUG
        func runtimeTasksForDrain() -> [Task<Void, Never>] {
            entriesByTabID.values.map(\.task)
        }
    #endif
}
