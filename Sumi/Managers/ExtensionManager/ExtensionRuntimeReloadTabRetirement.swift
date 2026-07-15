import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeReloadTabRetirement {
    private let profileRuntime: ExtensionProfileRuntime
    private let adapterResolution: ExtensionAdapterCatalog
    private let controllers: any ExtensionTabControllerQuery
    private let tabEvents: any ExtensionTabLifecycleEventSink
    private let tabProfiles: any ExtensionTabProfileResolving

    init(
        profileRuntime: ExtensionProfileRuntime,
        adapterResolution: ExtensionAdapterCatalog,
        controllers: any ExtensionTabControllerQuery,
        tabEvents: any ExtensionTabLifecycleEventSink,
        tabProfiles: any ExtensionTabProfileResolving
    ) {
        self.profileRuntime = profileRuntime
        self.adapterResolution = adapterResolution
        self.controllers = controllers
        self.tabEvents = tabEvents
        self.tabProfiles = tabProfiles
    }

    func closePublishedTabs(
        _ tabs: [Tab],
        generation: ExtensionTabPublicationRevision
    ) {
        for tab in tabs {
            guard tab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: generation),
                let profileID = tabProfiles.profileID(for: tab),
                let controller = profileRuntime.controller(for: profileID),
                controllers.existingController(for: tab) === controller,
                let adapter = adapterResolution.stableAdapter(for: tab),
                profileRuntime.contexts(for: profileID).values.contains(
                    where: { context in
                        context.openTabs.contains {
                            ($0 as AnyObject) === adapter
                        }
                    }
                ),
                tab.extensionPageRuntimeOwner
                    .claimDidOpenTabNotificationForClose(generation: generation)
            else { continue }
            tabEvents.emitDidCloseTab(
                tab,
                controller: controller,
                adapter: adapter
            )
        }
    }
}
