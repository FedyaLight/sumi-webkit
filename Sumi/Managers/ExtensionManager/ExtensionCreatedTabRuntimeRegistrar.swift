import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionCreatedTabRuntimeRegistrar {
    private let runtimeSession: ExtensionRuntimeSession
    private let profileRuntime: ExtensionProfileRuntime
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let tabOpenNotifier: any ExtensionTabOpenNotifying
    private let contextLoading: any ExtensionContentScriptContextLoading
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        runtimeSession: ExtensionRuntimeSession,
        profileRuntime: ExtensionProfileRuntime,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        tabOpenNotifier: any ExtensionTabOpenNotifying,
        contextLoading: any ExtensionContentScriptContextLoading,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.runtimeSession = runtimeSession
        self.profileRuntime = profileRuntime
        self.runtime = runtime
        self.tabOpenNotifier = tabOpenNotifier
        self.contextLoading = contextLoading
        self.diagnostics = diagnostics
    }

    func register(
        _ tab: Tab,
        reason: String
    ) {
        let generation = runtimeSession.tabOpenNotificationGeneration
        tab.extensionPageRuntimeOwner.prepareGeneration(generation)
        tab.extensionPageRuntimeOwner.markEligible(for: generation)

        guard tab.extensionPageRuntimeOwner
            .hasDidOpenTabNotification(for: generation) == false
        else {
            diagnostics.trace(
                "registerExtensionCreatedTab skip reason=\(reason) because=alreadyNotified generation=\(generation) \(tabDescription(tab))"
            )
            return
        }

        guard tabOpenNotifier.notifyTabOpened(tab) else {
            diagnostics.trace(
                "registerExtensionCreatedTab skip reason=\(reason) because=notifyFailed generation=\(generation) \(tabDescription(tab))"
            )
            return
        }

        if let profileId = profileRuntime.resolvedProfileId(
            for: tab,
            runtime: runtime()
        ) {
            let readiness: TabExtensionContextReadiness = contextLoading
                .profileHasLoadedContentScriptContexts(profileId: profileId)
                ? .loaded
                : .missing
            tab.extensionPageRuntimeOwner.noteOpenNotification(
                extensionContextBindingGeneration: profileRuntime
                    .contextBindingGeneration(for: profileId),
                contextReadiness: readiness
            )
        } else {
            tab.extensionPageRuntimeOwner.noteOpenNotification(
                extensionContextBindingGeneration: nil,
                contextReadiness: .unknown
            )
        }
        tab.extensionPageRuntimeOwner.markDidOpenTab(generation: generation)
        diagnostics.trace(
            "registerExtensionCreatedTab marked reason=\(reason) generation=\(generation) \(tabDescription(tab))"
        )
    }

    private func tabDescription(_ tab: Tab) -> String {
        "tab=\(tab.id.uuidString.prefix(8)) url=\(tab.url.absoluteString)"
    }
}
