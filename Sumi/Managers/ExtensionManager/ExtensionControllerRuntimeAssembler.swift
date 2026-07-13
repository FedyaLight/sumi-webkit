import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextTabCompatibilityQuery {
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var contexts: ExtensionContextPublicationQuery?

    init(
        tabs: any ExtensionTabQuery,
        profiles: any ExtensionTabProfileResolving,
        contexts: ExtensionContextPublicationQuery
    ) {
        self.tabs = tabs
        self.profiles = profiles
        self.contexts = contexts
    }

    func matches(_ tab: Tab, context: WKWebExtensionContext) -> Bool {
        guard tab.isEphemeral == false,
              tabs?.extensionTab(for: tab.id) === tab,
              let tabProfileID = profiles?.profileID(for: tab),
              let contextProfileID = contexts?.currentIdentity(
                for: context
              )?.profileID
        else { return false }
        return tabProfileID == contextProfileID
    }
}

/// Construction-only lifetime storage for narrow controller runtime roles.
@available(macOS 15.5, *)
@MainActor
struct ExtensionControllerRuntimeComposition {
    let profiles: ExtensionTabProfileResolution
    let controllers: ExtensionExistingExactTabControllerQuery
    let webViews: ExtensionExactTabWebViewQuery
    let admission: ExtensionWebViewControllerAdmission
    let mismatch: ExtensionWebViewControllerMismatchQuery
    let repair: ExtensionTabWebViewRuntimeRepair
    let reconciler: ExtensionProfileWebViewRuntimeReconciler
    let contextCompatibility: ExtensionContextTabCompatibilityQuery
    let tabWebViewResolver: ExtensionTabWebViewResolver
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionControllerRuntimeAssembler {
    static func assemble(
        tabs: any ExtensionTabQuery,
        inventory: any ExtensionTabInventory,
        selectedWebViews: any ExtensionTabLiveWebViewQuery,
        residences: any ExtensionTabWebViewResidenceQuery,
        rebuilder: any ExtensionTabWebViewRebuilding,
        windowProfiles: (any ExtensionTabWindowProfileQuery)?,
        runtimeSession: ExtensionRuntimeSession,
        profileRuntime: ExtensionProfileRuntime,
        contexts: ExtensionContextPublicationQuery,
        preludeInstaller: any ExtensionPreludeInstalling,
        diagnostics: ExtensionRuntimeDiagnostics
    ) -> ExtensionControllerRuntimeComposition {
        let profiles = ExtensionTabProfileResolution(
            profileRuntime: profileRuntime,
            windowProfiles: windowProfiles
        )
        let controllers = ExtensionExistingExactTabControllerQuery(
            tabs: tabs,
            profileRuntime: profileRuntime,
            profiles: profiles
        )
        let webViews = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residences,
            selected: selectedWebViews
        )
        let admission = ExtensionWebViewControllerAdmission(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: webViews,
            preludeInstaller: preludeInstaller
        )
        let mismatch = ExtensionWebViewControllerMismatchQuery(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime
        )
        let repair = ExtensionTabWebViewRuntimeRepair(
            runtimeSession: runtimeSession,
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: webViews,
            admission: admission,
            mismatch: mismatch,
            rebuilder: rebuilder,
            diagnostics: diagnostics
        )
        let tabWebViewResolver = ExtensionTabWebViewResolver(
            profileRuntime: profileRuntime,
            contextPublications: contexts,
            profiles: profiles,
            webViews: webViews,
            controllerAdmission: admission
        )
        return ExtensionControllerRuntimeComposition(
            profiles: profiles,
            controllers: controllers,
            webViews: webViews,
            admission: admission,
            mismatch: mismatch,
            repair: repair,
            reconciler: ExtensionProfileWebViewRuntimeReconciler(
                inventory: inventory,
                tabs: tabs,
                profiles: profiles,
                profileRuntime: profileRuntime,
                repair: repair
            ),
            contextCompatibility: ExtensionContextTabCompatibilityQuery(
                tabs: tabs,
                profiles: profiles,
                contexts: contexts
            ),
            tabWebViewResolver: tabWebViewResolver
        )
    }
}
