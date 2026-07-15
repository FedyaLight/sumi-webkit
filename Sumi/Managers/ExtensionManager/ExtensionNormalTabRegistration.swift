import Foundation

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabControllerPreparing: AnyObject {
    @discardableResult
    func repair(
        _ tab: Tab,
        reason: String,
        publicationStage: ExtensionRuntimePublicationStage
    ) -> ExtensionTabWebViewRuntimeRepairOutcome
}

@available(macOS 15.5, *)
extension ExtensionTabWebViewRuntimeRepair: ExtensionTabControllerPreparing {}

/// Owns generation preparation and eligibility for an exact normal Tab. It
/// delegates controller mutation and WebKit publication to their transactions.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabRegistration: ExtensionDeferredTabRuntimeResuming {
    private weak var tabPublicationRevisions:
        ExtensionTabPublicationRevisionAuthority?
    private weak var runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority?
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var preparedTabs: (any ExtensionPreparedTabQuery)?
    private weak var controllers: (any ExtensionTabControllerPreparing)?
    private weak var opening: (any ExtensionNormalTabOpening)?
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority,
        runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
        tabs: any ExtensionTabQuery,
        preparedTabs: any ExtensionPreparedTabQuery,
        controllers: any ExtensionTabControllerPreparing,
        opening: any ExtensionNormalTabOpening,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.tabPublicationRevisions = tabPublicationRevisions
        self.runtimeLoadStatus = runtimeLoadStatus
        self.tabs = tabs
        self.preparedTabs = preparedTabs
        self.controllers = controllers
        self.opening = opening
        self.diagnostics = diagnostics
    }

    func register(
        _ tab: Tab,
        reason: String,
        publicationStage: ExtensionRuntimePublicationStage = .loadedRuntime
    ) {
        guard let generation = tabPublicationRevisions?.issue() else { return }
        guard tabs?.extensionTab(for: tab.id) === tab,
              canEnterGeneration(tab, generation: generation)
        else {
            return
        }
        tab.extensionPageRuntimeOwner.prepareGeneration(generation)
        guard let runtimeLoadStatus,
              publicationStage.admits(runtimeLoadStatus)
        else {
            return
        }

        tab.extensionPageRuntimeOwner.markEligible(for: generation)
        controllers?.repair(
            tab,
            reason: reason,
            publicationStage: publicationStage
        )
        publishIfNeeded(tab, reason: reason)
    }

    func markEligibleAfterCommittedNavigation(
        _ tab: Tab,
        reason: String
    ) {
        guard let generation = tabPublicationRevisions?.issue() else { return }
        guard tabs?.extensionTab(for: tab.id) === tab,
              canEnterGeneration(tab, generation: generation)
        else {
            return
        }
        tab.extensionPageRuntimeOwner.prepareGeneration(generation)
        guard runtimeLoadStatus?.extensionsLoaded == true else { return }
        tab.extensionPageRuntimeOwner.markEligible(for: generation)
        controllers?.repair(
            tab,
            reason: reason,
            publicationStage: .loadedRuntime
        )
        publishIfNeeded(tab, reason: reason)
    }

    func publishIfNeeded(_ tab: Tab, reason: String) {
        guard let generation = tabPublicationRevisions?.issue() else { return }
        guard tabs?.extensionTab(for: tab.id) === tab,
              canEnterGeneration(tab, generation: generation)
        else { return }
        tab.extensionPageRuntimeOwner.prepareGeneration(generation)
        guard runtimeLoadStatus?.extensionsLoaded == true,
              preparedTabs?.containsPreparedTab(tab) == true,
              tab.extensionPageRuntimeOwner
              .hasDidOpenTabNotification(for: generation) == false
        else {
            return
        }
        guard opening?.publishOpen(tab) == true else {
            diagnostics.trace(
                "normalTabRegistration deferred reason=\(reason) tab=\(tab.id.uuidString.prefix(8))"
            )
            return
        }
    }

    func resumeAfterInitialContextsLoaded(_ tab: Tab, reason: String) {
        guard let generation = tabPublicationRevisions?.issue()
        else { return }
        if tab.extensionPageRuntimeOwner
            .hasOpenNotificationForCurrentDocumentWithLoadedContexts(
                generation: generation
            ) {
            return
        }
        tab.extensionPageRuntimeOwner.clearOpenNotificationGeneration()
        register(tab, reason: reason)
    }

    private func canEnterGeneration(
        _ tab: Tab,
        generation: ExtensionTabPublicationRevision
    ) -> Bool {
        guard tab.extensionPageRuntimeOwner
            .canPublishFutureOpenNotification() else { return false }
        let openGeneration = tab.extensionPageRuntimeOwner
            .currentOpenNotificationGeneration()
        return openGeneration == nil || openGeneration == generation
    }
}
