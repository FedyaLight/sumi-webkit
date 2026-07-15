import Foundation

@available(macOS 15.5, *)
@MainActor
enum ExtensionRequestedTabBindingDiagnostics {
    static func record(
        tab: Tab,
        load: ExtensionRequestedTabLoad,
        opensTransientInternalTab: Bool,
        diagnosticProfileID: UUID?,
        resolvedProfileID: UUID?,
        hasTabAdapter: Bool
    ) {
        SafariExtensionPermissionLifecycleDiagnostics.logTabBinding(
            SafariExtensionTabBindingSnapshot(
                route: opensTransientInternalTab
                    ? .extensionInternal
                    : .normalBrowserTab,
                profileBucket: SafariExtensionPermissionLifecycleDiagnostics
                    .bucket(
                        resolvedProfileID ?? diagnosticProfileID
                    ),
                tabBucket: SafariExtensionPermissionLifecycleDiagnostics
                    .bucket(tab.id),
                dataStoreMatched: nil,
                controllerMatched: nil,
                tabAdapterCreated: hasTabAdapter,
                didOpenTabTiming: tab.extensionPageRuntimeOwner
                    .hasAnyDidOpenTabNotification()
                    ? .beforeNavigation
                    : .deferred,
                firstNavigationHost: SafariExtensionPermissionLifecycleDiagnostics
                    .host(from: load.url),
                firstCommitHost: nil
            )
        )
    }
}
