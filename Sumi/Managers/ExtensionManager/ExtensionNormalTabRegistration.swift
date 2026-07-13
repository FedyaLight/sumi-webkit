import Foundation

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabControllerPreparing: AnyObject {
    func ensureExtensionControllerAttachedForTab(
        _ tab: Tab,
        reason: String,
        allowWhenExtensionsNotLoaded: Bool
    )
}

@available(macOS 15.5, *)
extension ExtensionControllerAttachmentOwner: ExtensionTabControllerPreparing {}

/// Owns generation preparation and eligibility for an exact normal Tab. It
/// delegates controller mutation and WebKit publication to their transactions.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabRegistration: ExtensionDeferredTabRuntimeResuming {
    private weak var runtimeSession: ExtensionRuntimeSession?
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var preparedTabs: (any ExtensionPreparedTabQuery)?
    private weak var controllers: (any ExtensionTabControllerPreparing)?
    private weak var opening: (any ExtensionNormalTabOpening)?
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        runtimeSession: ExtensionRuntimeSession,
        tabs: any ExtensionTabQuery,
        preparedTabs: any ExtensionPreparedTabQuery,
        controllers: any ExtensionTabControllerPreparing,
        opening: any ExtensionNormalTabOpening,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.runtimeSession = runtimeSession
        self.tabs = tabs
        self.preparedTabs = preparedTabs
        self.controllers = controllers
        self.opening = opening
        self.diagnostics = diagnostics
    }

    func register(
        _ tab: Tab,
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        guard let runtimeSession else { return }
        let generation = runtimeSession.tabOpenNotificationGeneration
        guard tabs?.extensionTab(for: tab.id) === tab,
              canEnterGeneration(tab, generation: generation)
        else {
            return
        }
        tab.extensionPageRuntimeOwner.prepareGeneration(generation)
        guard runtimeSession.extensionsLoaded || allowWhenExtensionsNotLoaded
        else { return }

        tab.extensionPageRuntimeOwner.markEligible(for: generation)
        controllers?.ensureExtensionControllerAttachedForTab(
            tab,
            reason: reason,
            allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
        )
        publishIfNeeded(tab, reason: reason)
    }

    func markEligibleAfterCommittedNavigation(
        _ tab: Tab,
        reason: String
    ) {
        guard let runtimeSession else { return }
        let generation = runtimeSession.tabOpenNotificationGeneration
        guard tabs?.extensionTab(for: tab.id) === tab,
              canEnterGeneration(tab, generation: generation)
        else {
            return
        }
        tab.extensionPageRuntimeOwner.prepareGeneration(generation)
        guard runtimeSession.extensionsLoaded else { return }
        tab.extensionPageRuntimeOwner.markEligible(for: generation)
        controllers?.ensureExtensionControllerAttachedForTab(
            tab,
            reason: reason,
            allowWhenExtensionsNotLoaded: false
        )
        publishIfNeeded(tab, reason: reason)
    }

    func publishIfNeeded(_ tab: Tab, reason: String) {
        guard let runtimeSession else { return }
        let generation = runtimeSession.tabOpenNotificationGeneration
        guard tabs?.extensionTab(for: tab.id) === tab,
              canEnterGeneration(tab, generation: generation)
        else { return }
        tab.extensionPageRuntimeOwner.prepareGeneration(generation)
        guard runtimeSession.extensionsLoaded,
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
        guard let generation = runtimeSession?.tabOpenNotificationGeneration
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
        generation: UInt64
    ) -> Bool {
        guard tab.extensionPageRuntimeOwner
            .canPublishFutureOpenNotification() else { return false }
        let openGeneration = tab.extensionPageRuntimeOwner
            .currentOpenNotificationGeneration()
        return openGeneration == 0 || openGeneration == generation
    }
}
