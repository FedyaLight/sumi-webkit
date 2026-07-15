import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionBrowserAttachmentAuthority {
    /// Browser-created/requested tab commands and auxiliary integration.
    @MainActor
    final class RequestedTabs {
        struct InitialPublicationEnvironment {
            let profiles: ExtensionTabProfileResolution
            let controllers: ExtensionExistingExactTabControllerQuery
            let preparer: ExtensionInitialTabPublicationPreparer
        }

        struct Environment {
            let initialPublication: InitialPublicationEnvironment
            let createdTabRegistrar: ExtensionCreatedTabRuntimeRegistrar
            let auxiliaryIntegration: AuxiliaryWindowExtensionIntegration
            let windowRouter: ExtensionWindowRequestRouter
            let pageContextMenu: ExtensionPageContextMenuItemsOwner
            let pageNavigation: ExtensionPageNavigationPreparationOwner
            let pageResolution: ExtensionPageResolutionOwner
        }

        private let attachedEnvironment: @MainActor () -> Environment?
        private let runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority
        private let profileRuntime: ExtensionProfileRuntime
        private let deferredOwners: ExtensionDeferredRuntimeOwnerStore

        init(
            attachment: ExtensionBrowserAttachmentAuthority,
            runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
            profileRuntime: ExtensionProfileRuntime,
            deferredOwners: ExtensionDeferredRuntimeOwnerStore
        ) {
            attachedEnvironment = { [weak attachment] in
                attachment?.requestedTabEnvironment()
            }
            self.runtimeLoadStatus = runtimeLoadStatus
            self.profileRuntime = profileRuntime
            self.deferredOwners = deferredOwners
        }

        func registerCreatedTab(_ tab: Tab, reason: String) {
            attachedEnvironment()?.createdTabRegistrar.register(
                tab,
                reason: reason
            )
        }

        func prepareInitialPublication(
            window: BrowserWindowState,
            tab: Tab,
            webView: FocusableWKWebView,
            reason: String
        ) -> InitialTabExtensionPreparation {
            guard window.isIncognito == false, tab.isEphemeral == false else {
                return .privateWindow
            }
            guard runtimeLoadStatus.extensionsLoaded else {
                return .notParticipating
            }
            guard let initialPublication = attachedEnvironment()?
                .initialPublication
            else { return .notParticipating }
                let windowProfileID = window.isIncognito
                    ? window.ephemeralProfile?.id
                    : window.currentProfileId ?? profileRuntime.currentProfileId
                let tabProfileID = initialPublication.profiles.profileID(for: tab)
                    ?? tab.profileId
                    ?? tab.resolveProfile()?.id
                    ?? profileRuntime.currentProfileId
                guard let windowProfileID, let tabProfileID else {
                    return .rejected
                }
                guard windowProfileID == tabProfileID else {
                    return .suppressed
                }
                guard initialPublication.controllers
                    .existingController(for: tab) != nil
                else { return .notParticipating }
                guard deferredOwners.initialDocumentRuntimePreparationOwner
                    .profileNeedsInitialDocumentExtensionContextLoad(
                        profileId: tabProfileID
                    ) == false
                else { return .suppressed }
                guard let receipt = initialPublication.preparer.prepare(
                        window: window,
                        tab: tab,
                        webView: webView,
                        reason: reason
                    )
                else { return .rejected }
                return .prepared(receipt)
        }

        func auxiliaryIntegration() -> AuxiliaryWindowExtensionIntegration? {
            attachedEnvironment()?.auxiliaryIntegration
        }

        func openWindow(
            tabURLs: [URL],
            controller: WKWebExtensionController,
            extensionContext: WKWebExtensionContext?,
            completion: @escaping (
                (any WKWebExtensionWindow)?,
                (any Error)?
            ) -> Void
        ) {
            guard tabURLs.count <= 1 else {
                completion(
                    nil,
                    ExtensionManagerCallbackError
                        .multipleWindowTabsUnsupported.nsError()
                )
                return
            }
            guard let windowRouter = attachedEnvironment()?.windowRouter else {
                completion(
                    nil,
                    ExtensionManagerCallbackError.browserManagerUnavailable
                        .nsError()
                )
                return
            }
            windowRouter.open(
                    tabURLs: tabURLs,
                    controller: controller,
                    extensionContext: extensionContext,
                    completion: completion
                )
        }

        func pageContextMenuItems(for tab: Tab) -> [NSMenuItem] {
            attachedEnvironment()?.pageContextMenu.menuItems(for: tab) ?? []
        }

        func preparePageNavigation(
            _ tab: Tab,
            targetURL: URL,
            reason: String
        ) -> TabWebViewReplacementOutcome {
            attachedEnvironment()?.pageNavigation.prepareNavigation(
                    tab,
                    targetURL: targetURL,
                    reason: reason
                ) ?? .notNeeded
        }

        func ownerExtensionID(
            extensionContext: WKWebExtensionContext?,
            openerTab: Tab?,
            extensionOwnedSourceURL: URL?,
            explicitExtensionID: String?
        ) -> String? {
            attachedEnvironment()?.pageResolution.ownerExtensionID(
                    extensionContext: extensionContext,
                    openerTab: openerTab,
                    extensionOwnedSourceURL: extensionOwnedSourceURL,
                    explicitExtensionID: explicitExtensionID
                )
        }
    }
}
