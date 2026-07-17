import AppKit
import Foundation
import WebKit

/// The sole authority for the browser attachment lifecycle. Attached service
/// storage never escapes: nested role projections can only perform operations
/// belonging to their own bounded protocol surface.
@available(macOS 15.5, *)
@MainActor
final class ExtensionBrowserAttachmentAuthority {
    #if DEBUG
        typealias DidInstall = @MainActor (
            _ inspection: ExtensionAttachedBrowserRuntimeInspection
        ) -> Void
    #endif

    struct Receipt: Equatable {
        fileprivate let browserIdentity: ObjectIdentifier
        fileprivate let generation: UInt64
    }

    enum Admission: Equatable {
        case install
        case alreadyAttached
        case rejectDifferentBrowser
        case rejectRetired
    }

    private struct Attachment {
        let receipt: Receipt
        let lifetime: ExtensionAttachedBrowserRuntime
    }

    private enum State {
        case detached(nextGeneration: UInt64)
        case attached(Attachment)
        case retired(lastGeneration: UInt64)
    }

    private var state = State.detached(nextGeneration: 1)
    #if DEBUG
        private let didInstall: DidInstall?

        init(didInstall: DidInstall? = nil) {
            self.didInstall = didInstall
        }
    #else
        init() {}
    #endif

    func admission(for browserIdentity: ObjectIdentifier) -> Admission {
        switch state {
        case .detached:
            return .install
        case .attached(let attachment):
            return attachment.receipt.browserIdentity == browserIdentity
                ? .alreadyAttached
                : .rejectDifferentBrowser
        case .retired:
            return .rejectRetired
        }
    }

    func install(
        _ lifetime: ExtensionAttachedBrowserRuntime,
        browserIdentity: ObjectIdentifier
    ) -> Receipt? {
        guard case .detached(let generation) = state,
              lifetime.browserIdentity == browserIdentity
        else { return nil }
        let receipt = Receipt(
            browserIdentity: browserIdentity,
            generation: generation
        )
        state = .attached(Attachment(receipt: receipt, lifetime: lifetime))
        #if DEBUG
            didInstall?(ExtensionAttachedBrowserRuntimeInspection(lifetime))
        #endif
        return receipt
    }

    func isCurrent(_ receipt: Receipt) -> Bool {
        guard case .attached(let attachment) = state else { return false }
        return attachment.receipt == receipt
    }

    func retireCurrentAttachment() {
        guard case .attached(let attachment) = state else { return }
        attachment.lifetime.browserRoutes.retire()
        state = .retired(lastGeneration: attachment.receipt.generation)
    }

    func normalTabQueryEnvironment() -> NormalTabQuery.Environment? {
        guard let lifetime = attachedLifetime else { return nil }
        return NormalTabQuery.Environment(
            tabs: NormalTabQuery.TabEnvironment(
                adapters: lifetime.adapters,
                publishedTabs: lifetime.normalTabs.publishedTabs,
                profiles: lifetime.controller.profiles
            ),
            controller: NormalTabQuery.ControllerEnvironment(
                contextCompatibility: lifetime.controller.contextCompatibility,
                webViews: lifetime.controller.webViews,
                tabWebViewResolver: lifetime.controller.tabWebViewResolver,
                controllers: lifetime.controller.controllers
            ),
            browser: NormalTabQuery.BrowserEnvironment(
                windows: lifetime.bridge.windows,
                webViews: lifetime.bridge.webViews,
                profileQuery: lifetime.profileQuery
            )
        )
    }

    func browserEventEnvironment() -> BrowserEvents.Environment? {
        guard let lifetime = attachedLifetime else { return nil }
        return BrowserEvents.Environment(
            publications: BrowserEvents.PublicationEnvironment(
                gate: lifetime.publications.gate,
                normalWindows: lifetime.publications.normalWindows,
                auxiliaryWindows: lifetime.publications.auxiliaryWindows,
                tabActivation: lifetime.publications.tabActivation,
                tabClosure: lifetime.publications.tabClosure,
                reconciler: lifetime.publications.reconciler
            ),
            browser: BrowserEvents.BrowserEnvironment(
                auxiliaryWindows: lifetime.bridge.auxiliaryWindows,
                windows: lifetime.bridge.windows
            )
        )
    }

    func websiteDataMutationAdmission()
        -> ExtensionWebsiteDataMutationAdmission? {
        attachedLifetime?.websiteDataAdmission
    }

    func requestedTabEnvironment() -> RequestedTabs.Environment? {
        guard let lifetime = attachedLifetime else { return nil }
        return RequestedTabs.Environment(
            initialPublication: RequestedTabs.InitialPublicationEnvironment(
                profiles: lifetime.controller.profiles,
                controllers: lifetime.controller.controllers,
                preparer: lifetime.requestedTabs.initialTabPreparer
            ),
            createdTabRegistrar: lifetime.requestedTabs.createdTabRegistrar,
            auxiliaryIntegration: lifetime.requestedTabs.auxiliaryIntegration,
            windowRouter: lifetime.requestedTabs.windowRouter,
            pageContextMenu: lifetime.requestedTabs.pageContextMenu,
            pageNavigation: lifetime.requestedTabs.pageNavigation,
            pageResolution: lifetime.requestedTabs.pageResolution
        )
    }

    func normalTabLifecycleEnvironment()
        -> NormalTabLifecycle.Environment? {
        guard let lifetime = attachedLifetime else { return nil }
        return NormalTabLifecycle.Environment(
            liveWebViewPreparation:
                lifetime.normalTabs.liveWebViewPreparation,
            tabRegistration: lifetime.normalTabs.tabRegistration,
            tabRebind: lifetime.normalTabs.tabRebind,
            tabProperties: lifetime.normalTabs.tabProperties,
            deferredTabRegistration:
                lifetime.normalTabs.deferredTabRegistration
        )
    }

    func controllerCallbackEnvironment()
        -> ControllerCallbacks.Environment? {
        guard let lifetime = attachedLifetime else { return nil }
        return ControllerCallbacks.Environment(
            openingCallbacks: lifetime.requestedTabs.openingCallbacks,
            optionsComposer: lifetime.optionsComposer
        )
    }

    func reloadEnvironment() -> Reloads.Environment? {
        guard let lifetime = attachedLifetime else { return nil }
        return Reloads.Environment(
            publications: Reloads.PublicationEnvironment(
                reload: lifetime.publications.reload,
                reconciler: lifetime.publications.reconciler,
                tabActivation: lifetime.publications.tabActivation,
                auxiliaryWindows: lifetime.bridge.auxiliaryWindows
            ),
            controllerReconciler: lifetime.controller.reconciler
        )
    }

    func actionBrowserEnvironment()
        -> ActionBrowserProjection.Environment? {
        guard let lifetime = attachedLifetime else { return nil }
        return ActionBrowserProjection.Environment(
            browser: ActionBrowserProjection.BrowserEnvironment(
                windows: lifetime.bridge.windows,
                presentation: lifetime.bridge.presentation,
                tabs: lifetime.bridge.tabs
            ),
            controller: ActionBrowserProjection.ControllerEnvironment(
                profiles: lifetime.controller.profiles,
                webViews: lifetime.controller.webViews
            ),
            normalTabs: ActionBrowserProjection.NormalTabEnvironment(
                publishedTabs: lifetime.normalTabs.publishedTabs,
                registration: lifetime.normalTabs.tabRegistration
            ),
            adapters: lifetime.adapters,
            profileQuery: lifetime.profileQuery
        )
    }

    func retirementEnvironment() -> Retirement.Environment? {
        guard let lifetime = attachedLifetime else { return nil }
        return Retirement.Environment(
            browser: Retirement.BrowserEnvironment(
                availability: lifetime.bridge.availability,
                tabs: lifetime.bridge.tabs,
                webViews: lifetime.bridge.webViews,
                auxiliaryWindows: lifetime.bridge.auxiliaryWindows
            ),
            activity: Retirement.ActivityEnvironment(
                deferredTabRegistration:
                    lifetime.normalTabs.deferredTabRegistration,
                publicationReconciler: lifetime.publications.reconciler
            )
        )
    }

    func windowRegistrationReceipt(
        for window: BrowserWindowState
    ) -> WindowRegistry.WindowRegistrationReceipt? {
        attachedLifetime?.bridge.windows.registrationReceipt(for: window)
    }

    func registeredWindow(
        ifCurrent receipt: WindowRegistry.WindowRegistrationReceipt
    ) -> BrowserWindowState? {
        attachedLifetime?.bridge.windows.window(ifCurrent: receipt)
    }

    func allRegisteredWindows() -> [BrowserWindowState] {
        attachedLifetime?.bridge.windows.allExtensionWindowStates ?? []
    }

    func containsExactResidence(
        _ tab: Tab,
        in window: BrowserWindowState
    ) -> Bool {
        guard let lifetime = attachedLifetime else { return false }
        return lifetime.bridge.tabResidences.containsExact(tab, in: window)
    }

    private var attachedLifetime: ExtensionAttachedBrowserRuntime? {
        guard case .attached(let attachment) = state else { return nil }
        return attachment.lifetime
    }
}
