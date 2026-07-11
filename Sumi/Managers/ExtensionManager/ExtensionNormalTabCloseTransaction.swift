import Foundation

/// Atomically claims one exact did-open generation before crossing WebKit's
/// synchronous close callback, then retires only the adapter that was closed.
/// A nested close sees the tombstone; a same-UUID replacement survives.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabCloseTransaction {
    private let runtimeSession: ExtensionRuntimeSession
    private let profileRuntime: ExtensionProfileRuntime
    private let adapterStore: ExtensionBrowserAdapterStore
    private let adapterResolution: ExtensionAdapterResolutionOwner
    private let windowPublications: ExtensionWindowPublicationQuery
    private let events: any ExtensionTabLifecycleEventSink
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let extensionsLoaded: @MainActor () -> Bool

    init(
        runtimeSession: ExtensionRuntimeSession,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore,
        adapterResolution: ExtensionAdapterResolutionOwner,
        windowPublications: ExtensionWindowPublicationQuery,
        events: any ExtensionTabLifecycleEventSink,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        extensionsLoaded: @escaping @MainActor () -> Bool
    ) {
        self.runtimeSession = runtimeSession
        self.profileRuntime = profileRuntime
        self.adapterStore = adapterStore
        self.adapterResolution = adapterResolution
        self.windowPublications = windowPublications
        self.events = events
        self.runtime = runtime
        self.extensionsLoaded = extensionsLoaded
    }

    func close(_ tab: Tab) {
        guard windowPublications.isAuxiliarySessionTab(tab) == false,
              extensionsLoaded()
        else {
            return
        }

        let generation = runtimeSession.tabOpenNotificationGeneration
        guard tab.extensionPageRuntimeOwner.isEligible(for: generation),
              tab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: generation),
              let profileID = profileRuntime.resolvedProfileId(
                  for: tab,
                  runtime: runtime()
              ), let controller = profileRuntime.controller(for: profileID),
              let adapter = adapterResolution.stableAdapter(for: tab),
              adapterStore.tabAdapters[tab.id] === adapter,
              adapter.represents(tab),
              tab.extensionPageRuntimeOwner
                .claimDidOpenTabNotificationForClose(generation: generation)
        else {
            return
        }

        events.emitDidCloseTab(
            tab,
            controller: controller,
            adapter: adapter
        )
        _ = adapterStore.removeTabAdapter(
            for: tab.id,
            ifIdenticalTo: adapter
        )
    }
}
