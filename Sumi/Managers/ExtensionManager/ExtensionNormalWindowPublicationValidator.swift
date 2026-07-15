import Foundation

/// Combines browser identity and extension-runtime evidence without owning
/// either responsibility's dependencies.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowPublicationValidator {
    private let browserIdentity: ExtensionNormalWindowBrowserIdentityValidator
    private let runtime: ExtensionNormalWindowRuntimePublicationValidator

    init(
        windowQuery: any ExtensionWindowQuery,
        tabQuery: any ExtensionTabQuery,
        runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
        profileRuntime: ExtensionProfileRuntime,
        profiles: any ExtensionTabProfileResolving,
        windowProfileID: @escaping @MainActor (BrowserWindowState) -> UUID?,
        preparedTabs: ExtensionPreparedNormalTabQuery,
        controllers: ExtensionExistingExactTabControllerQuery,
        adapterStore: ExtensionBrowserAdapterStore,
        runtimePublicationEvidence: ExtensionRuntimePublicationEvidenceIssuer
    ) {
        browserIdentity = ExtensionNormalWindowBrowserIdentityValidator(
            windowQuery: windowQuery,
            tabQuery: tabQuery,
            profiles: profiles,
            windowProfileID: windowProfileID
        )
        runtime = ExtensionNormalWindowRuntimePublicationValidator(
            runtimeLoadStatus: runtimeLoadStatus,
            profileRuntime: profileRuntime,
            preparedTabs: preparedTabs,
            controllers: controllers,
            adapterStore: adapterStore,
            runtimePublicationEvidence: runtimePublicationEvidence
        )
    }

    func validate(
        _ projection: ExtensionNormalWindowProjection,
        for window: BrowserWindowState,
        publicationStage: ExtensionRuntimePublicationStage
    ) -> Bool {
        guard let selectedTab = browserIdentity.validate(
            projection,
            for: window
        ) else { return false }
        return runtime.validate(
            projection,
            window: window,
            selectedTab: selectedTab,
            publicationStage: publicationStage
        )
    }

    func preferredWindow(for tab: Tab) -> BrowserWindowState? {
        browserIdentity.preferredWindow(for: tab)
    }

    func isExactRegistered(_ window: BrowserWindowState) -> Bool {
        browserIdentity.isExactRegistered(window)
    }

    func profileID(for tab: Tab) -> UUID? {
        browserIdentity.profileID(for: tab)
    }

    func canPublishWithoutNormalWindow(_ tab: Tab) -> Bool {
        browserIdentity.canPublishWithoutNormalWindow(tab)
    }
}
