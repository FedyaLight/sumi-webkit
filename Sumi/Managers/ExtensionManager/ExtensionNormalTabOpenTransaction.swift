import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabAdapterResolving: AnyObject {
    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter?
}

@available(macOS 15.5, *)
extension ExtensionAdapterCatalog: ExtensionTabAdapterResolving {}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionInitialDocumentReadiness: AnyObject {
    func profileHasLoadedExtensionContext(profileId: UUID) -> Bool

    func profileNeedsInitialDocumentExtensionContextLoad(
        profileId: UUID
    ) -> Bool
}

@available(macOS 15.5, *)
extension ExtensionInitialDocumentRuntimePreparationOwner:
    ExtensionInitialDocumentReadiness {}

@available(macOS 15.5, *)
extension ExtensionInitialDocumentReadiness {
    func profileHasLoadedExtensionContext(profileId: UUID) -> Bool {
        profileNeedsInitialDocumentExtensionContextLoad(profileId: profileId)
            == false
    }
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionNormalTabOpening: AnyObject {
    @discardableResult
    func publishOpen(_ tab: Tab) -> Bool

    @discardableResult
    func publishOpen(
        _ tab: Tab,
        during claim: ExtensionRuntimePublicationGate.ReloadClaim
    ) -> Bool
}

/// Exact claim-backed publication of one normal browser Tab into WebKit.
/// Every authority that may change across a synchronous WebKit callback is
/// captured before dispatch and revalidated after it returns.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabOpenTransaction: ExtensionNormalTabOpening {
    private weak var runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer?
    private weak var publicationGate: ExtensionRuntimePublicationGate?
    private weak var profileRuntime: ExtensionProfileRuntime?
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var adapters: ExtensionBrowserAdapterStore?
    private weak var adapterResolver: (any ExtensionTabAdapterResolving)?
    private weak var controllers: (any ExtensionTabControllerQuery)?
    private weak var controllerAdmission:
        (any ExtensionWebViewControllerAdmitting)?
    private weak var liveWebViews: (any ExtensionTabLiveWebViewQuery)?
    private weak var contextReadiness: (any ExtensionInitialDocumentReadiness)?
    private weak var deferredRegistration:
        (any ExtensionDeferredTabRegistrationScheduling)?
    private weak var admission: ExtensionTabPublicationAdmission?
    private weak var windowPublications:
        (any ExtensionTabPublicationEvidenceQuery)?
    private let events: ExtensionTabLifecycleEmitter
    private let diagnostics: ExtensionRuntimeDiagnostics
    #if DEBUG
        private var didDeferOpen: ((UUID, String) -> Void)?
    #endif

    init(
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        publicationGate: ExtensionRuntimePublicationGate,
        profileRuntime: ExtensionProfileRuntime,
        profiles: any ExtensionTabProfileResolving,
        tabs: any ExtensionTabQuery,
        adapters: ExtensionBrowserAdapterStore,
        adapterResolver: any ExtensionTabAdapterResolving,
        controllers: any ExtensionTabControllerQuery,
        controllerAdmission: any ExtensionWebViewControllerAdmitting,
        liveWebViews: any ExtensionTabLiveWebViewQuery,
        contextReadiness: any ExtensionInitialDocumentReadiness,
        deferredRegistration: any ExtensionDeferredTabRegistrationScheduling,
        admission: ExtensionTabPublicationAdmission,
        windowPublications: any ExtensionTabPublicationEvidenceQuery,
        events: ExtensionTabLifecycleEmitter,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.publicationGate = publicationGate
        self.profileRuntime = profileRuntime
        self.profiles = profiles
        self.tabs = tabs
        self.adapters = adapters
        self.adapterResolver = adapterResolver
        self.controllers = controllers
        self.controllerAdmission = controllerAdmission
        self.liveWebViews = liveWebViews
        self.contextReadiness = contextReadiness
        self.deferredRegistration = deferredRegistration
        self.admission = admission
        self.windowPublications = windowPublications
        self.events = events
        self.diagnostics = diagnostics
    }

    #if DEBUG
        func installDebugDidDeferOpen(
            _ callback: @escaping (UUID, String) -> Void
        ) {
            didDeferOpen = callback
        }
    #endif

    @discardableResult
    func publishOpen(_ tab: Tab) -> Bool {
        publishOpen(tab, reloadClaim: nil)
    }

    @discardableResult
    func publishOpen(
        _ tab: Tab,
        during claim: ExtensionRuntimePublicationGate.ReloadClaim
    ) -> Bool {
        publishOpen(tab, reloadClaim: claim)
    }

    private func publishOpen(
        _ tab: Tab,
        reloadClaim: ExtensionRuntimePublicationGate.ReloadClaim?
    ) -> Bool {
        func deferOpen(_ reason: String) -> Bool {
            #if DEBUG
                didDeferOpen?(tab.id, reason)
            #endif
            return false
        }

        guard let runtimePublicationEvidence,
              let profileRuntime,
              let controllerAdmission,
              let admission,
              tabs?.extensionTab(for: tab.id) === tab,
              let controller = controllers?.existingController(for: tab),
              let adapter = adapterResolver?.stableAdapter(for: tab),
              adapter.represents(tab)
        else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedMissingAuthority",
                pageURL: tab.url
            )
            return deferOpen("missingAuthority")
        }

        guard let profileID = profiles?.profileID(for: tab) else {
            return deferOpen("missingProfile")
        }
        guard contextReadiness?
            .profileHasLoadedExtensionContext(profileId: profileID)
            == true else {
            _ = deferredRegistration?
                .scheduleDeferredTabNotificationAfterContextLoad(
                    tab,
                    profileId: profileID,
                    extensionLoadRevision:
                        runtimePublicationEvidence.issue().extensionLoad,
                    reason: "notifyTabOpened"
                )
            return deferOpen("initialDocumentContextsNotLoaded")
        }

        guard let webView = liveWebViews?.extensionLiveWebView(for: tab),
              (webView as? FocusableWKWebView)?.owningTab === tab,
              controllerAdmission.admit(
                  controller,
                  profileID: profileID,
                  to: webView,
                  for: tab
              ).isUsable,
              liveWebViews?.extensionLiveWebView(for: tab) === webView,
              (webView as? FocusableWKWebView)?.owningTab === tab,
              webView.configuration.webExtensionController === controller
        else {
            return deferOpen("missingUsableWebView")
        }

        let admitted = if let reloadClaim {
            admission.prepareTabOpen(tab, during: reloadClaim)
        } else {
            admission.prepareTabOpen(tab)
        }
        guard admitted else { return deferOpen("windowProjectionUnavailable") }
        guard tab.extensionPageRuntimeOwner.canPublishFutureOpenNotification()
        else { return deferOpen("tabOpenPublicationRetired") }

        let runtimePublication = runtimePublicationEvidence.issue()
        let openGeneration = runtimePublication.tabPublication
        let contextBindingGeneration = profileRuntime
            .contextBindingGeneration(for: profileID)
        guard remainsCurrent(
            tab,
            reloadClaim: reloadClaim,
            controller: controller,
            adapter: adapter,
            webView: webView,
            profileID: profileID,
            runtimePublication: runtimePublication,
            contextBindingGeneration: contextBindingGeneration
        ) else {
            return deferOpen("openPublicationChangedDuringAdmission")
        }

        guard let openClaim = tab.extensionPageRuntimeOwner.reserveDidOpenTab(
            generation: openGeneration,
            publisher: controller,
            adapter: adapter
        ) else {
            return deferOpen("openPublicationClaimAlreadyCurrent")
        }
        tab.extensionPageRuntimeOwner.noteOpenNotification(
            extensionContextBindingGeneration: contextBindingGeneration,
            contextReadiness: .loaded
        )
        events.emitDidOpenTab(
            tab,
            controller: controller,
            adapter: adapter
        )

        guard remainsCurrent(
                tab,
                reloadClaim: reloadClaim,
                controller: controller,
                adapter: adapter,
                webView: webView,
                profileID: profileID,
                runtimePublication: runtimePublication,
                contextBindingGeneration: contextBindingGeneration
              ),
              tab.extensionPageRuntimeOwner.settleDidOpenTabNotification(
                  openClaim,
                  generation: openGeneration
              )
        else {
            if tab.extensionPageRuntimeOwner
                .claimDidOpenTabNotificationForClose(
                    openClaim,
                    generation: openGeneration
                ) {
                events.emitDidCloseTab(
                    tab,
                    controller: controller,
                    adapter: adapter
                )
            }
            return deferOpen("openPublicationChangedDuringCallback")
        }

        SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
            injected: true,
            extensionId: nil,
            reason: "didOpenTab",
            pageURL: tab.url
        )
        diagnostics.trace(
            "didOpenTab complete generation=\(openGeneration) tab=\(tab.id.uuidString.prefix(8))"
        )
        return true
    }

    private func remainsCurrent(
        _ tab: Tab,
        reloadClaim: ExtensionRuntimePublicationGate.ReloadClaim?,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter,
        webView: WKWebView,
        profileID: UUID,
        runtimePublication: ExtensionRuntimePublicationEvidence,
        contextBindingGeneration: UInt64
    ) -> Bool {
        guard let runtimePublicationEvidence,
              let publicationGate,
              let profileRuntime,
              let adapters
        else { return false }
        let gateIsCurrent = if let reloadClaim {
            publicationGate.reloadIsCurrent(reloadClaim)
        } else {
            publicationGate.acceptsBrowserEvents
        }
        return gateIsCurrent
            && runtimePublicationEvidence.isCurrent(runtimePublication)
            && profileRuntime.contextBindingGeneration(for: profileID)
                == contextBindingGeneration
            && contextReadiness?
                .profileHasLoadedExtensionContext(profileId: profileID)
                == true
            && tabs?.extensionTab(for: tab.id) === tab
            && profiles?.profileID(for: tab) == profileID
            && profileRuntime.controller(for: profileID) === controller
            && adapters.existingTabAdapter(for: tab.id) === adapter
            && adapter.represents(tab)
            && tab.extensionPageRuntimeOwner.canPublishFutureOpenNotification()
            && tab.extensionPageRuntimeOwner.isEligible(
                for: runtimePublication.tabPublication
            )
            && liveWebViews?.extensionLiveWebView(for: tab) === webView
            && (webView as? FocusableWKWebView)?.owningTab === tab
            && webView.configuration.webExtensionController === controller
            && windowPublications?.tabPublicationIsCurrent(
                tab,
                profileID: profileID
            ) == true
    }
}
